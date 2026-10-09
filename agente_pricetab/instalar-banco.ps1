# Instala o agente Simplifica Compras no MODO BANCO nesta máquina (computador da rede da loja).
#   1. Mostra os drivers ODBC instalados e pergunta qual usar (o driver oficial do banco do ERP:
#      MySQL Connector/ODBC, ODBC Driver for SQL Server, psqlODBC, Firebird ODBC, Oracle...).
#   2. Pergunta o endereço do servidor Simplifica, a chave da loja, o servidor/porta/nome do banco,
#      o usuário (só SELECT na VIEW) e a senha, o nome da VIEW e se ela tem data_alteracao.
#   3. Grava o config.json e PROTEGE a chave e a senha pelo Windows (DPAPI): só este computador lê.
#   4. Testa a leitura da VIEW e a conexão com o servidor Simplifica.
#   5. Registra a tarefa "SimplificaCompras-AgenteBanco", que inicia junto com o Windows, inicia o
#      agente e mostra o resultado da primeira leitura completa.
# Como administrador, a tarefa roda como SYSTEM ao ligar o Windows (sem ninguém logado); sem
# administrador, roda quando este usuário entra no Windows.
# Não mexe em outras tarefas do Simplifica Compras (agente do PRICETAB, agente RPInfo).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$nomeTarefa = 'SimplificaCompras-AgenteBanco'
$caminhoConfig = Join-Path $pasta 'config.json'
$caminhoModelo = Join-Path $pasta 'config.exemplo.banco.json'

function Perguntar([string]$texto, [string]$sugestao) {
    $resposta = Read-Host "$texto [$sugestao]"
    if ([string]::IsNullOrWhiteSpace($resposta)) { return $sugestao }
    return $resposta.Trim()
}

# Segredo: digitado sem aparecer na tela (um * por caractere); Enter mantém o já protegido.
# Nesta tela o Ctrl+V NÃO cola: colar = botão direito do mouse.
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

# Lê um parâmetro (Driver=, Server=...) de uma conexão ODBC já gravada, para sugerir de novo.
function Parte([string]$conexao, [string]$nome) {
    if ($conexao -match "(?i)(^|;)$nome=\{?([^};]*)\}?") { return $Matches[2] }
    return $null
}

Write-Host ''
Write-Host '=== Simplifica Compras - instalação do agente do conector de banco ===' -ForegroundColor Cyan
Write-Host 'O agente lê a VIEW vw_simplifica_precos no banco do ERP DENTRO da rede da loja, com um usuário'
Write-Host 'que só tem SELECT nela, e só envia preços para o Simplifica Compras (conexão de saída).'
Write-Host 'Nenhuma porta é aberta nesta máquina e nada é gravado no ERP.'
Write-Host ''

$drivers = @(Get-OdbcDriver -Platform '64-bit' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object -Unique)
if (-not $drivers.Count) {
    Write-Host 'Nenhum driver ODBC de 64 bits encontrado neste computador.' -ForegroundColor Red
    Write-Host 'Instale o driver ODBC OFICIAL do banco do ERP (ex.: MySQL Connector/ODBC, ODBC Driver for SQL' -ForegroundColor Red
    Write-Host 'Server, psqlODBC) e rode este instalador de novo.' -ForegroundColor Red
    exit 1
}
Write-Host 'Drivers ODBC instalados neste computador:'
for ($i = 0; $i -lt $drivers.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $drivers[$i]) }

$base = if (Test-Path $caminhoConfig) { Get-Content $caminhoConfig -Raw -Encoding UTF8 | ConvertFrom-Json } else { Get-Content $caminhoModelo -Raw -Encoding UTF8 | ConvertFrom-Json }
$b = $base.banco
$driverAnterior = Parte ([string]$b.conexao) 'Driver'
$sugestaoDriver = if ($driverAnterior -and $drivers -contains $driverAnterior) { [array]::IndexOf($drivers, $driverAnterior) + 1 }
    else { $mysql = @($drivers | Where-Object { $_ -match 'MySQL.*Unicode' }); if ($mysql.Count) { [array]::IndexOf($drivers, $mysql[0]) + 1 } else { 1 } }
$escolha = [int](Perguntar 'Número do driver do banco do ERP' $sugestaoDriver)
if ($escolha -lt 1 -or $escolha -gt $drivers.Count) { throw "Número de driver inválido: $escolha." }
$driver = $drivers[$escolha - 1]

$servidorBanco = Perguntar 'Endereço do servidor do banco do ERP (na rede da loja)' $(if (Parte ([string]$b.conexao) 'Server') { Parte ([string]$b.conexao) 'Server' } else { '127.0.0.1' })
$portaPadrao = if ($driver -match 'MySQL') { '3306' } elseif ($driver -match 'SQL Server') { '1433' } elseif ($driver -match 'PostgreSQL') { '5432' } else { '' }
$porta = Perguntar 'Porta do banco' $(if (Parte ([string]$b.conexao) 'Port') { Parte ([string]$b.conexao) 'Port' } else { $portaPadrao })
$nomeBanco = Perguntar 'Nome do banco (database) onde está a VIEW' $(if (Parte ([string]$b.conexao) 'Database') { Parte ([string]$b.conexao) 'Database' } else { 'erp' })
$conexao = if ($driver -match 'SQL Server') { "Driver={$driver};Server=$servidorBanco,$porta;Database=$nomeBanco;" }
    else { "Driver={$driver};Server=$servidorBanco;Port=$porta;Database=$nomeBanco;" + $(if ($driver -match 'MySQL') { 'CHARSET=utf8mb4;' } else { '' }) }

$config = [ordered]@{
    modo                  = 'banco'
    url                   = Perguntar 'Endereço do servidor Simplifica Compras' $base.url
    intervaloSinalMinutos = if ($base.intervaloSinalMinutos) { $base.intervaloSinalMinutos } else { 1 }
    auditoria             = -not ($base.auditoria -eq $false)
    banco                 = [ordered]@{
        conexao          = $conexao
        usuario          = Perguntar 'Usuário do banco (só SELECT na VIEW)' $(if ($b.usuario -and $b.usuario -notmatch ' ') { $b.usuario } else { 'simplifica_leitura' })
        view             = Perguntar 'Nome da VIEW' $(if ($b.view) { $b.view } else { 'vw_simplifica_precos' })
        incremental      = (Perguntar 'A VIEW tem a coluna data_alteracao? (S/N)' $(if ($b.incremental -eq $false) { 'N' } else { 'S' })) -match '^[sS]'
        intervaloMinutos = [double](Perguntar 'Leitura incremental a cada quantos minutos' $(if ($b.intervaloMinutos) { $b.intervaloMinutos } else { 5 }))
        folgaMinutos     = if ($b.folgaMinutos) { $b.folgaMinutos } else { 10 }
        horarioCompleta  = Perguntar 'Horário da leitura completa diária (HH:mm)' $(if ($b.horarioCompleta) { $b.horarioCompleta } else { '12:00' })
    }
}
$chave = Perguntar-Segredo 'Chave da loja (fornecida pela Simplifica Compras)' ([bool]$base.chaveProtegida)
$senha = Perguntar-Segredo 'Senha do usuário do banco' ([bool]$b.senhaProtegida)
if ($config.banco.horarioCompleta -notmatch '^\d{2}:\d{2}$') { throw 'Horário inválido (use HH:mm, ex.: 12:00).' }

# Grava o config SEM segredos e protege a chave e a senha (mantém as já protegidas se o Enter foi usado).
if ($base.chaveProtegida) { $config['chaveProtegida'] = $base.chaveProtegida }
if ($b.senhaProtegida) { $config.banco['senhaProtegida'] = $b.senhaProtegida }
[IO.File]::WriteAllText($caminhoConfig, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
$proteger = Join-Path $pasta 'proteger.ps1'
if ($chave) { & $proteger -Campo chave -Valor $chave -Config $caminhoConfig | Out-Null }
if ($senha) { & $proteger -Campo senha -Valor $senha -Config $caminhoConfig | Out-Null }
$chave = $null; $senha = $null
Write-Host 'Configuração gravada; chave e senha protegidas pelo Windows.' -ForegroundColor Green

Write-Host ''
Write-Host 'Testando as conexões...'
$teste = & (Join-Path $pasta 'agente.ps1') -Config $caminhoConfig -TestarConexao 6>&1 | Out-String
$teste -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object {
    $linha = if ($_.Length -gt 20) { $_.Substring(20) } else { $_ }
    $cor = if ($linha -match 'FALHOU') { 'Red' } else { 'Gray' }
    Write-Host "  $linha" -ForegroundColor $cor
}
if ($teste -match 'FALHOU' -or $teste -notmatch 'VIEW lida') {
    Write-Host ''
    Write-Host 'O teste de conexão falhou (veja acima). Nada foi registrado no Windows.' -ForegroundColor Red
    Write-Host 'Confira driver, endereço, porta, banco, usuário/senha e a permissão de SELECT na VIEW, e rode de novo.' -ForegroundColor Red
    exit 1
}

$administrador = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$existente = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
if ($existente) {
    Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false
}

$acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $pasta 'agente.ps1')`"" `
    -WorkingDirectory $pasta
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
    -Description 'Simplifica Compras: lê a VIEW de preços no banco do ERP da loja e envia os preços (só conexões de saída).' | Out-Null
Write-Host "Tarefa '$nomeTarefa' registrada: inicia $modo." -ForegroundColor Green

Start-ScheduledTask -TaskName $nomeTarefa
Write-Host 'Agente iniciado. Aguardando a primeira leitura completa (até 3 min)...'
$pastaLogs = Join-Path $pasta 'logs'
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
    Write-Host "Instalado. A primeira leitura ainda não terminou em 3 min. Acompanhe o log em: $pastaLogs" -ForegroundColor Yellow
}
