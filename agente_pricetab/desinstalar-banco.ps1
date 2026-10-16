# Remove o agente da integração via VIEW (banco de dados) do Simplifica Compras desta máquina, como o
# desinstalar.sh do Linux: para e apaga a tarefa agendada "SimplificaCompras-AgenteBanco" e APAGA a pasta
# do agente, inclusive o config.json com a chave da loja e a senha do banco, a fila, a auditoria e os
# logs. Não mexe em outras tarefas (agente do PRICETAB, agente RPInfo), no sistema da loja nem nos
# drivers ODBC (podem ser usados por outros programas).
$nomeTarefa = 'SimplificaCompras-AgenteBanco'
$descricao = 'agente da integração via VIEW (banco de dados)'

$tarefa = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
# A pasta instalada é a da tarefa: o desinstalador pode estar rodando de outra cópia (ex.: o pendrive).
$pasta = if ($tarefa -and $tarefa.Actions[0].WorkingDirectory) { $tarefa.Actions[0].WorkingDirectory } else { $PSScriptRoot }
$pasta = [IO.Path]::GetFullPath($pasta).TrimEnd('\')
if (-not $tarefa -and -not (Test-Path (Join-Path $pasta 'config.json'))) {
    Write-Host "O $descricao não está instalado nesta máquina."
    Read-Host 'Tecle Enter para fechar' | Out-Null
    return
}

Write-Host "Isto remove o $descricao desta máquina: a tarefa agendada e a pasta"
Write-Host "  $pasta"
Write-Host 'com a configuração (chave da loja e senha do banco), a fila, a auditoria e os logs.'
$resposta = Read-Host 'Confirma? (s/n) [n]'
if ($resposta -ne 's') {
    Write-Host 'Nada foi removido.'
    Read-Host 'Tecle Enter para fechar' | Out-Null
    return
}

if ($tarefa) {
    Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false
}
# O Stop-ScheduledTask nem sempre derruba o powershell filho: encerra o processo do agente também.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$pasta*agente.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

# Só apaga uma pasta de agente (tem o agente.ps1) e nunca a raiz de um disco.
if (-not (Test-Path (Join-Path $pasta 'agente.ps1')) -or $pasta -match '^[A-Za-z]:$') {
    Write-Host "Tarefa '$nomeTarefa' apagada, mas a pasta $pasta não parece ser do agente: apague-a à mão." -ForegroundColor Yellow
    Read-Host 'Tecle Enter para fechar' | Out-Null
    return
}

# 1) Dados e credenciais: apagados agora.
foreach ($item in 'config.json', 'config.novo.json', 'estado.json', 'fila', 'auditoria', 'logs') {
    Remove-Item (Join-Path $pasta $item) -Recurse -Force -ErrorAction SilentlyContinue
}
$sobrou = @('config.json', 'config.novo.json', 'estado.json') | Where-Object { Test-Path (Join-Path $pasta $_) }
if ($sobrou) {
    Write-Host "ATENÇÃO: não foi possível apagar $($sobrou -join ', ') em $pasta. Apague à mão." -ForegroundColor Red
} else {
    Write-Host "Agente removido: tarefa '$nomeTarefa' apagada e a chave da loja e a senha do banco apagadas desta máquina." -ForegroundColor Green
}

# 2) Programa: a pasta inteira. Na cópia de desenvolvimento (modelagem_dados_postgresgente_pricetab,
# com o .git logo acima) ficam os scripts. Só olha 1 nível acima: a pasta do usuário do Windows também
# pode ser um repositório git, e o agente instalado dentro dela tem que ser apagado.
if ((Test-Path (Join-Path $pasta '.git')) -or (Test-Path (Join-Path (Split-Path -Parent $pasta) '.git'))) {
    Write-Host 'Pasta de desenvolvimento (git): os scripts do agente foram mantidos.'
    Read-Host 'Tecle Enter para fechar' | Out-Null
    return
}
Write-Host 'Para instalar em outro computador, peça à Simplifica Compras a liberação do agente da loja.'
Read-Host 'Tecle Enter para fechar' | Out-Null
if ($PSScriptRoot.TrimEnd('\') -ieq $pasta) {
    # Rodando de dentro da pasta: ela só some depois que esta janela fechar.
    Start-Process cmd.exe -ArgumentList "/c ping -n 4 127.0.0.1 >nul & rmdir /s /q `"$pasta`"" -WorkingDirectory $env:TEMP -WindowStyle Hidden
} else {
    Remove-Item $pasta -Recurse -Force -ErrorAction SilentlyContinue
}
