# Remove o agente RPInfo do Simplifica Compras desta máquina: para e apaga a tarefa agendada
# "SimplificaCompras-AgenteRPInfo". Não mexe em outras tarefas (ex.: o agente do PRICETAB).
# A pasta do agente (config.json, logs, auditoria) fica; apague-a à mão se quiser.
$nomeTarefa = 'SimplificaCompras-AgenteRPInfo'
$tarefa = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
if (-not $tarefa) {
    Write-Host 'O agente RPInfo não está instalado nesta máquina.'
    return
}
Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
# O Stop-ScheduledTask nem sempre derruba o powershell filho: encerra o processo do agente também.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$PSScriptRoot*agente.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false
Write-Host "Agente RPInfo removido (tarefa '$nomeTarefa' apagada)." -ForegroundColor Green
