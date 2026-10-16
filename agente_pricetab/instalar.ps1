# Instala o agente Simplifica Compras nesta máquina (PC/servidor da loja).
#   1. Pergunta a chave da loja e a pasta do PRICETAB (Enter aceita o valor sugerido). A chave é
#      gravada PROTEGIDA pelo Windows (DPAPI da máquina, proteger.ps1): só este computador lê.
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
    [switch]$SemPerguntas,
    # Exceção: PRICETAB numa pasta de rede (a conta LOCAL SERVICE não lê). Roda como SYSTEM.
    [switch]$ContaSystem
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$nomeTarefa = 'SimplificaCompras-AgentePricetab'
$caminhoConfig = Join-Path $PSScriptRoot 'config.json'
$caminhoModelo = Join-Path $PSScriptRoot 'config.exemplo.json'

function Perguntar([string]$texto, [string]$sugestao, [switch]$Segredo) {
    if ($SemPerguntas) { return $sugestao }
    # A chave nunca aparece inteira na tela (a janela pode ser fotografada ou compartilhada).
    $exibida = if ($Segredo -and $sugestao -and $sugestao.Length -gt 12) { $sugestao.Substring(0, 8) + '...' + $sugestao.Substring($sugestao.Length - 4) } else { $sugestao }
    $resposta = Read-Host "$texto [$exibida]"
    if ([string]::IsNullOrWhiteSpace($resposta)) { return $sugestao }
    return $resposta.Trim()
}

Write-Host ''
Write-Host '=== Simplifica Compras - instalação do agente do PRICETAB ===' -ForegroundColor Cyan
Write-Host ''

# Conta da tarefa quando instalado como administrador: LOCAL SERVICE, conta de serviço do próprio
# Windows, SEM privilégios de administrador e sem senha (nada é criado no computador); ela só grava
# na pasta do agente. -ContaSystem é a exceção documentada (PRICETAB numa pasta de REDE, que a LOCAL
# SERVICE não lê): volta a tarefa para SYSTEM. Sempre pelo SID S-1-5-19: o nome muda com o idioma do
# Windows ("SERVIÇO LOCAL" em português).
function Conta-ServicoLocal { (New-Object Security.Principal.SecurityIdentifier 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value }

function Liberar-PastaAgente([string]$caminho) {
    & icacls $caminho /grant '*S-1-5-19:(OI)(CI)M' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Não foi possível dar à conta LOCAL SERVICE acesso à pasta do agente ($caminho)." }
}

# Modo PRICETAB: a LOCAL SERVICE precisa LER a pasta do arquivo. Pasta de rede ela não lê: devolve
# $false. Pasta local sem leitura para ela (nem para Todos/Usuários/SERVICE): libera só a leitura.
function Liberar-LeituraPricetab([string]$pastaPricetab) {
    if ($pastaPricetab -like '\\*') { return $false }
    if (-not (Test-Path $pastaPricetab)) { return $true }
    $leitores = 'S-1-5-19', 'S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-6'
    $temLeitura = (Get-Acl $pastaPricetab).Access | Where-Object {
        $sid = try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { '' }
        $_.AccessControlType -eq 'Allow' -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadData) -and $leitores -contains $sid
    }
    if (-not $temLeitura) {
        & icacls $pastaPricetab /grant '*S-1-5-19:(OI)(CI)RX' | Out-Null
        Write-Host "Leitura da pasta do PRICETAB ($pastaPricetab) liberada para a conta LOCAL SERVICE (só leitura)."
    }
    return $true
}

$ehAdministrador = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Já instalado (a tarefa existe e a pasta dela tem config.json): oferece ATUALIZAR só o programa,
# como o instalar.sh do Linux. A pasta instalada é a da tarefa: este instalador pode estar rodando
# da pasta da versão nova (ex.: o pendrive) - aí o programa novo é copiado para a pasta instalada.
$tarefaInstalada = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
$pastaInstalada = if ($tarefaInstalada) { $tarefaInstalada.Actions[0].WorkingDirectory } else { $null }
if ($pastaInstalada -and (Test-Path (Join-Path $pastaInstalada 'config.json')) -and -not $SemPerguntas) {
    function Versao-Agente([string]$arquivo) {
        if ((Test-Path $arquivo) -and ((Get-Content $arquivo -Raw -Encoding UTF8) -match "\`$versaoAgente = '([^']+)'")) { return $Matches[1] }
        return '?'
    }
    $versaoInstalada = Versao-Agente (Join-Path $pastaInstalada 'agente.ps1')
    $versaoPacote = Versao-Agente (Join-Path $PSScriptRoot 'agente.ps1')
    Write-Host "Este agente já está instalado em $pastaInstalada (versão $versaoInstalada; este pacote: versão $versaoPacote)."
    Write-Host '  1 = ATUALIZAR só o programa (mantém a configuração: chave, senha e demais respostas)'
    Write-Host '  2 = RECONFIGURAR (refaz as perguntas; Enter mantém cada valor atual)'
    if ((Read-Host 'Escolha [1]') -ne '2') {
        Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
            Where-Object { $_.CommandLine -like "*$pastaInstalada*agente.ps1*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        if ([IO.Path]::GetFullPath($pastaInstalada).TrimEnd('\') -ine [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')) {
            # Só o programa: a configuração, o estado, a fila, a auditoria e os logs da loja ficam.
            Get-ChildItem $PSScriptRoot -File | Where-Object { $_.Name -notin 'config.json', 'config.novo.json', 'estado.json' } |
                Copy-Item -Destination $pastaInstalada -Force
            Write-Host "Programa da versão $versaoPacote copiado para $pastaInstalada."
        }
        # Chave em texto aberto (agente do PRICETAB até a 2.5): passa a ficar protegida pelo Windows.
        $cfgChave = Get-Content (Join-Path $pastaInstalada 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $proteger = Join-Path $PSScriptRoot 'proteger.ps1'
        if ($cfgChave.chave -and -not $cfgChave.chaveProtegida -and (Test-Path $proteger)) {
            & $proteger -Campo chave -Valor $cfgChave.chave -Config (Join-Path $pastaInstalada 'config.json') | Out-Null
            Write-Host 'A chave da loja, que estava em texto aberto no config.json, foi protegida pelo Windows.'
        }
        # Tarefa antiga como SYSTEM (versões até a 2.5): passa para a LOCAL SERVICE, sem privilégios.
        if ($ehAdministrador -and -not $ContaSystem -and $tarefaInstalada.Principal.UserId -match 'SYSTEM|SISTEMA') {
            $cfgInstalado = Get-Content (Join-Path $pastaInstalada 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $pricetabLocal = if ((-not $cfgInstalado.modo -or $cfgInstalado.modo -eq 'arquivo') -and $cfgInstalado.pasta) { Liberar-LeituraPricetab $cfgInstalado.pasta } else { $true }
            if ($pricetabLocal) {
                Liberar-PastaAgente $pastaInstalada
                Set-ScheduledTask -TaskName $nomeTarefa -Principal (New-ScheduledTaskPrincipal -UserId (Conta-ServicoLocal) -LogonType ServiceAccount -RunLevel Limited) | Out-Null
                Write-Host 'A tarefa passou a rodar com a conta LOCAL SERVICE (sem privilégios de administrador).'
            } else {
                Write-Host 'O PRICETAB está numa pasta de rede: a tarefa continua com a conta SYSTEM.' -ForegroundColor Yellow
            }
        }
        $inicio = Get-Date
        Start-ScheduledTask -TaskName $nomeTarefa
        Write-Host 'Agente reiniciado. Conferindo a versão no log (até 60 s)...'
        $linha = $null
        $fim = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $fim -and -not $linha) {
            Start-Sleep -Seconds 3
            $log = Get-ChildItem (Join-Path $pastaInstalada 'logs') -Filter 'agente-*.log' -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $inicio } | Sort-Object LastWriteTime | Select-Object -Last 1
            if ($log) { $linha = Get-Content $log.FullName -Encoding UTF8 -Tail 30 | Where-Object { $_ -match 'Agente \S+ \(modo .*iniciado' } | Select-Object -Last 1 }
        }
        if ($linha -match "Agente $([regex]::Escape($versaoPacote)) ") {
            Write-Host "  $linha" -ForegroundColor Green
            Write-Host "Atualização concluída: agente $versaoPacote rodando com a configuração de antes." -ForegroundColor Green
        } elseif ($linha) {
            Write-Host "  $linha" -ForegroundColor Yellow
            Write-Host "O agente reiniciou, mas não na versão $versaoPacote. Confira se os arquivos foram copiados." -ForegroundColor Yellow
        } else {
            Write-Host "O agente não registrou a partida em 60 s. Log em: $(Join-Path $pastaInstalada 'logs')" -ForegroundColor Yellow
        }
        return
    }
    Write-Host ''
}


$base = if (Test-Path $caminhoConfig) { Get-Content $caminhoConfig -Raw -Encoding UTF8 | ConvertFrom-Json } else { Get-Content $caminhoModelo -Raw -Encoding UTF8 | ConvertFrom-Json }
# Chave já protegida (reconfiguração): o Enter mantém; para o teste de conexão, decifra aqui (DPAPI da
# máquina: só este computador consegue).
$chaveAtual = $base.chave
if ($base.chaveProtegida -like 'dpapi:*') {
    Add-Type -AssemblyName System.Security
    $chaveAtual = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect(
        [Convert]::FromBase64String($base.chaveProtegida.Substring(6)), $null, [Security.Cryptography.DataProtectionScope]::LocalMachine))
}
$config = [ordered]@{
    url                   = if ($Url) { $Url } else { Perguntar 'Endereço da API' $base.url }
    chave                 = if ($Chave) { $Chave } else { Perguntar 'Chave da loja (fornecida pela Simplifica Compras)' $chaveAtual -Segredo }
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
# A chave não fica em texto aberto: o proteger.ps1 cifra pelo Windows e apaga o texto aberto.
& (Join-Path $PSScriptRoot 'proteger.ps1') -Campo chave -Valor $config.chave -Config $caminhoConfig | Out-Null
Write-Host 'Configuração gravada; chave protegida pelo Windows (só este computador lê).' -ForegroundColor Green

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
    if ($ContaSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $modo = 'ao ligar o Windows (conta SYSTEM, pedida com -ContaSystem)'
    } else {
        if (-not (Liberar-LeituraPricetab $config.pasta)) {
            throw "A pasta do PRICETAB ($($config.pasta)) é de rede, e a conta LOCAL SERVICE não lê pastas de rede. Copie o arquivo para uma pasta local OU instale com: instalar.ps1 -ContaSystem (e libere a pasta de rede para a conta do computador)."
        }
        Liberar-PastaAgente $PSScriptRoot
        $principal = New-ScheduledTaskPrincipal -UserId (Conta-ServicoLocal) -LogonType ServiceAccount -RunLevel Limited
        $modo = 'ao ligar o Windows (conta LOCAL SERVICE, sem privilégios de administrador)'
    }
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
