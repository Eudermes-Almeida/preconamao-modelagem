# Instala o agente Simplifica Compras no MODO RPInfo nesta máquina (computador da rede da loja).
#   1. Pergunta o endereço do servidor Simplifica, a chave da loja, o endereço INTERNO da API da
#      RPInfo, o usuário/senha (só leitura) e o CNPJ da unidade (Enter aceita o valor sugerido).
#   2. Grava o config.json e PROTEGE a chave e a senha pelo Windows (DPAPI): só este computador lê.
#   3. Testa a conexão com a API da RPInfo e com o servidor Simplifica.
#   4. Registra a tarefa "SimplificaCompras-AgenteRPInfo", que inicia junto com o Windows.
#   5. Inicia o agente e mostra o resultado da primeira coleta completa.
# Como administrador, a tarefa roda como SYSTEM ao ligar o Windows (sem ninguém logado); sem
# administrador, roda quando este usuário entra no Windows.
# Não mexe em outras tarefas do Simplifica Compras (ex.: o agente do PRICETAB).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$nomeTarefa = 'SimplificaCompras-AgenteRPInfo'
$caminhoConfig = Join-Path $PSScriptRoot 'config.json'
$caminhoModelo = Join-Path $PSScriptRoot 'config.exemplo.rpinfo.json'

function Perguntar([string]$texto, [string]$sugestao) {
    $resposta = Read-Host "$texto [$sugestao]"
    if ([string]::IsNullOrWhiteSpace($resposta)) { return $sugestao }
    return $resposta.Trim()
}

# Segredo: digitado sem aparecer na tela (um * por caractere); Enter mantém o já protegido.
# Nesta tela o Ctrl+V NÃO cola: vira um caractere de controle (aparece um * só). Colar = botão
# direito do mouse. Valor com caractere de controle ou curto demais é recusado e perguntado de novo.
function Perguntar-Segredo([string]$texto, [bool]$jaExiste) {
    $sufixo = if ($jaExiste) { ' (Enter mantém o já protegido)' } else { '' }
    for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
        $seguro = Read-Host -AsSecureString "$texto$sufixo"
        $valor = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro))
        if ([string]::IsNullOrWhiteSpace($valor)) {
            if ($jaExiste) { return $null }
            Write-Host "  $texto é obrigatório." -ForegroundColor Yellow
            continue
        }
        $valor = $valor.Trim()
        if ($valor -match '[\x00-\x1F\x7F]' -or $valor.Length -lt 4) {
            Write-Host '  Valor inválido. Para COLAR nesta tela use o BOTÃO DIREITO do mouse (Ctrl+V não funciona aqui);' -ForegroundColor Yellow
            Write-Host '  deve aparecer um * para cada caractere. Tente de novo.' -ForegroundColor Yellow
            continue
        }
        return $valor
    }
    Write-Host "Não foi possível ler: $texto. Rode o instalador de novo." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '=== Simplifica Compras - instalação do agente RPInfo ===' -ForegroundColor Cyan
Write-Host 'O agente consulta a API da RPInfo DENTRO da rede da loja e só envia preços para o Simplifica'
Write-Host 'Compras (conexão de saída). Nenhuma porta é aberta nesta máquina.'
Write-Host ''

$base = if (Test-Path $caminhoConfig) { Get-Content $caminhoConfig -Raw -Encoding UTF8 | ConvertFrom-Json } else { Get-Content $caminhoModelo -Raw -Encoding UTF8 | ConvertFrom-Json }
$r = $base.rpinfo
$config = [ordered]@{
    modo                  = 'rpinfo'
    url                   = Perguntar 'Endereço do servidor Simplifica Compras' $base.url
    intervaloSinalMinutos = if ($base.intervaloSinalMinutos) { $base.intervaloSinalMinutos } else { 1 }
    auditoria             = -not ($base.auditoria -eq $false)
    rpinfo                = [ordered]@{
        url              = Perguntar 'Endereço INTERNO da API da RPInfo' $r.url
        usuario          = Perguntar 'Usuário da API (só leitura)' $r.usuario
        cnpj             = Perguntar 'CNPJ da unidade (loja) na RPInfo' $r.cnpj
        tamanhoPagina    = if ($r.tamanhoPagina) { $r.tamanhoPagina } else { 100 }
        intervaloMinutos = [double](Perguntar 'Coleta incremental a cada quantos minutos' $(if ($r.intervaloMinutos) { $r.intervaloMinutos } else { 5 }))
        folgaMinutos     = if ($r.folgaMinutos) { $r.folgaMinutos } else { 10 }
        horarioCompleta  = Perguntar 'Horário da coleta completa diária (HH:mm)' $(if ($r.horarioCompleta) { $r.horarioCompleta } else { '12:00' })
    }
}
$chave = Perguntar-Segredo 'Chave da loja (fornecida pela Simplifica Compras)' ([bool]$base.chaveProtegida)
$senha = Perguntar-Segredo 'Senha da API da RPInfo' ([bool]$r.senhaProtegida)
if ($config.rpinfo.horarioCompleta -notmatch '^\d{2}:\d{2}$') { throw 'Horário inválido (use HH:mm, ex.: 12:00).' }

# Grava o config SEM segredos e protege a chave e a senha (mantém as já protegidas se o Enter foi usado).
if ($base.chaveProtegida) { $config['chaveProtegida'] = $base.chaveProtegida }
if ($r.senhaProtegida) { $config.rpinfo['senhaProtegida'] = $r.senhaProtegida }
[IO.File]::WriteAllText($caminhoConfig, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
$proteger = Join-Path $PSScriptRoot 'proteger.ps1'
if ($chave) { & $proteger -Campo chave -Valor $chave -Config $caminhoConfig | Out-Null }
if ($senha) { & $proteger -Campo senha -Valor $senha -Config $caminhoConfig | Out-Null }
$chave = $null; $senha = $null
Write-Host 'Configuração gravada; chave e senha protegidas pelo Windows.' -ForegroundColor Green

Write-Host ''
Write-Host 'Testando as conexões...'
$teste = & (Join-Path $PSScriptRoot 'agente.ps1') -Config $caminhoConfig -TestarConexao 6>&1 | Out-String
$teste -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object {
    $linha = if ($_.Length -gt 20) { $_.Substring(20) } else { $_ }
    $cor = if ($linha -match 'FALHOU|NÃO encontrado') { 'Red' } else { 'Gray' }
    Write-Host "  $linha" -ForegroundColor $cor
}
if ($teste -match 'FALHOU|NÃO encontrado') {
    Write-Host ''
    Write-Host 'O teste de conexão falhou (veja acima). Nada foi registrado no Windows.' -ForegroundColor Red
    Write-Host 'Corrija e rode o instalador de novo (na chave e na senha, cole com o BOTÃO DIREITO do mouse).' -ForegroundColor Red
    exit 1
}

$administrador = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$existente = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
if ($existente) {
    Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false
}

$acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot 'agente.ps1')`"" `
    -WorkingDirectory $PSScriptRoot
# Sem limite de tempo; se o agente cair, o Windows reinicia a cada 1 min.
$opcoes = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew
if ($administrador) {
    $gatilho = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $modo = 'ao ligar o Windows (conta SYSTEM)'
} else {
    $usuario = "$env:USERDOMAIN\$env:USERNAME"
    $gatilho = New-ScheduledTaskTrigger -AtLogOn -User $usuario
    $principal = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited
    $modo = "quando $usuario entrar no Windows (para iniciar sem ninguém logado, instale como administrador)"
}
Register-ScheduledTask -TaskName $nomeTarefa -Action $acao -Trigger $gatilho -Principal $principal -Settings $opcoes `
    -Description 'Simplifica Compras: consulta a API da RPInfo na rede da loja e envia os preços (só conexões de saída).' | Out-Null
Write-Host "Tarefa '$nomeTarefa' registrada: inicia $modo." -ForegroundColor Green

Start-ScheduledTask -TaskName $nomeTarefa
Write-Host 'Agente iniciado. Aguardando a primeira coleta completa (até 3 min)...'
$pastaLogs = Join-Path $PSScriptRoot 'logs'
$inicio = Get-Date
$fim = $inicio.AddMinutes(3)
$resultado = $null
while ((Get-Date) -lt $fim -and -not $resultado) {
    Start-Sleep -Seconds 3
    $log = Get-ChildItem $pastaLogs -Filter 'agente-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($log) {
        $resultado = Get-Content $log.FullName -Encoding UTF8 -Tail 30 |
            Where-Object { $_ -ge $inicio.ToString('yyyy-MM-dd HH:mm:ss') -and $_ -match 'enviado:|Foto igual|Falha' } | Select-Object -Last 1
    }
}
Write-Host ''
if ($resultado -match 'enviado:|Foto igual') {
    Write-Host "  $resultado" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Instalação concluída. O agente segue rodando em segundo plano.' -ForegroundColor Green
} elseif ($resultado) {
    Write-Host "  $resultado" -ForegroundColor Yellow
    Write-Host "Instalado, mas veja o aviso acima. Log completo em: $pastaLogs" -ForegroundColor Yellow
} else {
    Write-Host "Instalado. A primeira coleta ainda não terminou em 3 min. Acompanhe o log em: $pastaLogs" -ForegroundColor Yellow
}
