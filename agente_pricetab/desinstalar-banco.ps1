# Remove o agente do conector de banco do Simplifica Compras desta máquina: para e apaga a tarefa agendada
# "SimplificaCompras-AgenteBanco". Não mexe em outras tarefas (agente do PRICETAB, agente RPInfo).
# A pasta do agente (config.json, logs, auditoria) fica; apague-a à mão se quiser.
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$nomeTarefa = 'SimplificaCompras-AgenteBanco'
$tarefa = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
if (-not $tarefa) {
    Write-Host 'O agente do conector de banco não está instalado nesta máquina.'
    return
}
Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
# O Stop-ScheduledTask nem sempre derruba o powershell filho: encerra o processo do agente também.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$pasta*agente.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false
Write-Host "Agente do conector de banco removido (tarefa '$nomeTarefa' apagada)." -ForegroundColor Green
