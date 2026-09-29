# Instala o agente Simplifica Compras nesta máquina (PC/servidor da loja).
#   1. Pergunta a chave da loja e a pasta do PRICETAB (Enter aceita o valor sugerido).
#   2. Testa a conexão com a API.
#   3. Registra a tarefa "SimplificaCompras-AgentePricetab", que inicia junto com o Windows.
#   4. Inicia o agente e mostra o resultado do primeiro envio.
# Como administrador, a tarefa roda como SYSTEM ao ligar o Windows (sem ninguém logado); sem
# administrador, roda quando este usuário entra no Windows.
# Para instalar sem perguntas: instalar.ps1 -Url ... -Chave ... -Pasta ... -SemPerguntas

param(
    [string]$Url,
    [string]$Chave,
    [string]$Pasta,
    [string]$Arquivo,
    [switch]$SemPerguntas
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$nomeTarefa = 'SimplificaCompras-AgentePricetab'
$caminhoConfig = Join-Path $PSScriptRoot 'config.json'
$caminhoModelo = Join-Path $PSScriptRoot 'config.exemplo.json'

function Perguntar([string]$texto, [string]$sugestao) {
    if ($SemPerguntas) { return $sugestao }
    $resposta = Read-Host "$texto [$sugestao]"
    if ([string]::IsNullOrWhiteSpace($resposta)) { return $sugestao }
    return $resposta.Trim()
}

Write-Host ''
Write-Host '=== Simplifica Compras - instalação do agente do PRICETAB ===' -ForegroundColor Cyan
Write-Host ''

$base = if (Test-Path $caminhoConfig) { Get-Content $caminhoConfig -Raw -Encoding UTF8 | ConvertFrom-Json } else { Get-Content $caminhoModelo -Raw -Encoding UTF8 | ConvertFrom-Json }
$config = [ordered]@{
    url                   = if ($Url) { $Url } else { Perguntar 'Endereço da API' $base.url }
    chave                 = if ($Chave) { $Chave } else { Perguntar 'Chave da loja (fornecida pela Simplifica Compras)' $base.chave }
    pasta                 = if ($Pasta) { $Pasta } else { Perguntar 'Pasta onde fica o PRICETAB' $base.pasta }
    arquivo               = if ($Arquivo) { $Arquivo } else { Perguntar 'Nome do arquivo' $base.arquivo }
    intervaloSinalMinutos = if ($base.intervaloSinalMinutos) { [int]$base.intervaloSinalMinutos } else { 5 }
}

if (-not $config.chave -or $config.chave -like '*COLE*') { throw 'Informe a chave da loja.' }
if (-not (Test-Path (Join-Path $config.pasta $config.arquivo))) {
    Write-Host "Aviso: '$(Join-Path $config.pasta $config.arquivo)' não existe agora. O agente espera ele aparecer." -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Testando a conexão com a API...'
try {
    $resposta = Invoke-WebRequest -Uri "$($config.url.TrimEnd('/'))/cargas/situacao" -Headers @{ 'X-Chave-Loja' = $config.chave } -UseBasicParsing -TimeoutSec 90
    $situacao = [Text.Encoding]::UTF8.GetString($resposta.RawContentStream.ToArray()) | ConvertFrom-Json
    Write-Host "  OK - conectado como: $($situacao.loja)" -ForegroundColor Green
} catch {
    $codigo = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($codigo -eq 401) { throw 'A API recusou a chave da loja (401). Confira a chave.' }
    throw "Não foi possível falar com a API: $($_.Exception.Message)"
}

$config | ConvertTo-Json | Set-Content $caminhoConfig -Encoding UTF8

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
    -Description 'Simplifica Compras: envia o PRICETAB.TXT da loja para a API quando ele muda.' | Out-Null
Write-Host "Tarefa '$nomeTarefa' registrada: inicia $modo." -ForegroundColor Green

Start-ScheduledTask -TaskName $nomeTarefa
Write-Host 'Agente iniciado. Aguardando o primeiro envio (até 90 s)...'
$pastaLogs = Join-Path $PSScriptRoot 'logs'
$fim = (Get-Date).AddSeconds(90)
$resultado = $null
while ((Get-Date) -lt $fim -and -not $resultado) {
    Start-Sleep -Seconds 3
    $log = Get-ChildItem $pastaLogs -Filter 'agente-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($log) {
        $resultado = Get-Content $log.FullName -Encoding UTF8 -Tail 20 |
            Where-Object { $_ -match 'Arquivo enviado|Falha|não encontrad' } | Select-Object -Last 1
    }
}
Write-Host ''
if ($resultado -match 'Arquivo enviado') {
    Write-Host "  $resultado" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Instalação concluída. O agente segue rodando em segundo plano.' -ForegroundColor Green
} elseif ($resultado) {
    Write-Host "  $resultado" -ForegroundColor Yellow
    Write-Host "Instalado, mas veja o aviso acima. Log completo em: $pastaLogs" -ForegroundColor Yellow
} else {
    Write-Host "Instalado. Sem envio em 90 s (o arquivo pode já estar aplicado). Log em: $pastaLogs" -ForegroundColor Yellow
}
