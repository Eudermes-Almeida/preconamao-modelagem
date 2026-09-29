# Remove o agente Simplifica Compras desta máquina: para e apaga a tarefa agendada. A pasta do
# agente (com config.json e logs) fica; apague-a à mão se quiser.
$nomeTarefa = 'SimplificaCompras-AgentePricetab'
$tarefa = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
if (-not $tarefa) {
    Write-Host 'O agente não está instalado nesta máquina.'
    return
}
Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
# O Stop-ScheduledTask nem sempre derruba o powershell filho: encerra o processo do agente também.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$PSScriptRoot*agente.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false
Write-Host "Agente removido (tarefa '$nomeTarefa' apagada)." -ForegroundColor Green
