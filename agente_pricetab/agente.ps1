# Agente Simplifica Compras: vigia o PRICETAB.TXT da loja e envia para a API sempre que ele muda.
#
# - Só envia o arquivo depois que ele termina de ser gravado (tamanho e data parados por 3 s e
#   nenhum outro programa com o arquivo aberto para escrita): nunca manda um arquivo pela metade.
# - Não reenvia o mesmo conteúdo (compara o SHA-256 com o do último envio).
# - Envia os bytes exatamente como estão (Latin-1), sem conversão: os acentos não se perdem.
# - Falhou (internet, servidor)? Tenta de novo em 10 s, 30 s, 1 min, 2 min e depois a cada 5 min.
# - Ao iniciar e a cada N minutos manda o "sinal de vida"; se o servidor não tiver o arquivo que
#   está na loja (envio perdido), ele pede e o agente reenvia.
# - Registra tudo em logs\agente-AAAA-MM-DD.log (guarda 30 dias).
#
# Só LÊ o arquivo e só faz conexões de SAÍDA (HTTPS) para a API. Configuração em config.json.

param([string]$Config = (Join-Path $PSScriptRoot 'config.json'))

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$url = $cfg.url.TrimEnd('/')
$arquivo = Join-Path $cfg.pasta $cfg.arquivo
$intervaloSinal = if ($cfg.intervaloSinalMinutos) { [int]$cfg.intervaloSinalMinutos } else { 5 }
$pastaLogs = Join-Path $PSScriptRoot 'logs'
$caminhoEstado = Join-Path $PSScriptRoot 'estado.json'
$cabecalhos = @{ 'X-Chave-Loja' = $cfg.chave }
$esperasSegundos = @(10, 30, 60, 120, 300)
New-Item -ItemType Directory -Force $pastaLogs | Out-Null

function Registrar([string]$mensagem) {
    $linha = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $mensagem
    Add-Content -Path (Join-Path $pastaLogs ('agente-{0:yyyy-MM-dd}.log' -f (Get-Date))) -Value $linha -Encoding UTF8
    Write-Host $linha
}

function Limpar-LogsAntigos {
    Get-ChildItem $pastaLogs -Filter 'agente-*.log' |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Ler-Estado {
    if (Test-Path $caminhoEstado) {
        try { return Get-Content $caminhoEstado -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ ultimoHashEnviado = $null; ultimoEnvioEm = $null }
}

function Salvar-Estado($estado) {
    $estado | ConvertTo-Json | Set-Content $caminhoEstado -Encoding UTF8
}

function Hash-Sha256([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

# Devolve os bytes do arquivo, 'AUSENTE' ou 'OCUPADO' (ainda sendo gravado: tenta no próximo ciclo).
function Ler-ArquivoEstavel {
    if (-not (Test-Path $arquivo)) { return 'AUSENTE' }
    $antes = Get-Item $arquivo
    Start-Sleep -Seconds 3
    if (-not (Test-Path $arquivo)) { return 'OCUPADO' }
    $depois = Get-Item $arquivo
    if ($antes.Length -ne $depois.Length -or $antes.LastWriteTimeUtc -ne $depois.LastWriteTimeUtc) { return 'OCUPADO' }
    try {
        # FileShare.Read: falha se outro programa ainda estiver com o arquivo aberto para escrita.
        $fluxo = [IO.File]::Open($arquivo, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $memoria = New-Object IO.MemoryStream
            $fluxo.CopyTo($memoria)
            return , $memoria.ToArray()
        } finally { $fluxo.Dispose() }
    } catch {
        return 'OCUPADO'
    }
}

function Descrever-Erro($erro) {
    $resposta = $erro.Exception.Response
    if ($resposta -and $resposta.StatusCode) { return "HTTP $([int]$resposta.StatusCode) ($($erro.Exception.Message))" }
    return $erro.Exception.Message
}

function Enviar-Arquivo([byte[]]$bytes) {
    $resposta = Invoke-WebRequest -Uri "$url/cargas/pricetab" -Method Post -Body $bytes `
        -ContentType 'text/plain; charset=ISO-8859-1' -Headers $cabecalhos -UseBasicParsing -TimeoutSec 120
    $texto = [Text.Encoding]::UTF8.GetString($resposta.RawContentStream.ToArray())
    return $texto | ConvertFrom-Json
}

function Enviar-Sinal($hash) {
    $corpo = [Text.Encoding]::UTF8.GetBytes((@{ hash = $hash } | ConvertTo-Json -Compress))
    $resposta = Invoke-WebRequest -Uri "$url/cargas/sinal" -Method Post -Body $corpo `
        -ContentType 'application/json; charset=utf-8' -Headers $cabecalhos -UseBasicParsing -TimeoutSec 30
    return [Text.Encoding]::UTF8.GetString($resposta.RawContentStream.ToArray()) | ConvertFrom-Json
}

# ----------------------------------------------------------------------------------------------

Registrar "Agente iniciado. Vigiando '$arquivo' -> $url (sinal a cada $intervaloSinal min)."
Limpar-LogsAntigos
$estado = Ler-Estado
$pendente = $true                 # na partida, confere o arquivo atual
$ultimoVisto = $null              # "tamanho|data" da última leitura estável
$hashAtual = $null                # hash da última leitura estável (vai no sinal de vida)
$situacaoArquivo = $null          # para registrar "não encontrado" só uma vez
$tentativasFalhas = 0
$proximaTentativa = Get-Date
$proximoSinal = (Get-Date).AddSeconds(15)
$vigia = $null
$diaLimpeza = (Get-Date).Date

while ($true) {
    # Vigia do Windows: acorda assim que o arquivo muda; sem mudança, confere mesmo assim a cada 5 s
    # (cobre aviso perdido, arquivo renomeado, pasta de rede).
    if (-not $vigia) {
        if (Test-Path $cfg.pasta) {
            $vigia = New-Object IO.FileSystemWatcher $cfg.pasta, $cfg.arquivo
            $vigia.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
        } else {
            if ($situacaoArquivo -ne 'SEM_PASTA') { Registrar "Pasta não encontrada: $($cfg.pasta). Aguardando." }
            $situacaoArquivo = 'SEM_PASTA'
            Start-Sleep -Seconds 5
        }
    }
    if ($vigia) {
        try {
            $mudanca = $vigia.WaitForChanged([IO.WatcherChangeTypes]::All, 5000)
            if (-not $mudanca.TimedOut) { $pendente = $true }
        } catch {
            $vigia.Dispose(); $vigia = $null   # pasta sumiu: recria o vigia no próximo ciclo
        }
    }

    $visto = if (Test-Path $arquivo) { $info = Get-Item $arquivo; "$($info.Length)|$($info.LastWriteTimeUtc.Ticks)" } else { 'AUSENTE' }
    if ($visto -ne $ultimoVisto) { $pendente = $true }

    if ($pendente -and (Get-Date) -ge $proximaTentativa) {
        $conteudo = Ler-ArquivoEstavel
        if ($conteudo -is [byte[]]) {
            $situacaoArquivo = 'OK'
            $hash = Hash-Sha256 $conteudo
            $hashAtual = $hash
            $enviado = $true
            if ($hash -ne $estado.ultimoHashEnviado) {
                try {
                    $resposta = Enviar-Arquivo $conteudo
                    Registrar ("Arquivo enviado ({0:N0} bytes, hash {1}): {2} - {3}" -f $conteudo.Length, $hash.Substring(0, 12), $resposta.situacao, $resposta.mensagem)
                    $estado.ultimoHashEnviado = $hash
                    $estado.ultimoEnvioEm = (Get-Date).ToString('o')
                    Salvar-Estado $estado
                    $tentativasFalhas = 0
                } catch {
                    $enviado = $false
                    $espera = $esperasSegundos[[Math]::Min($tentativasFalhas, $esperasSegundos.Count - 1)]
                    $tentativasFalhas++
                    $proximaTentativa = (Get-Date).AddSeconds($espera)
                    Registrar "Falha ao enviar o arquivo: $(Descrever-Erro $_). Nova tentativa em $espera s."
                }
            }
            if ($enviado) {
                $pendente = $false
                $ultimoVisto = $visto
            }
        } elseif ($conteudo -eq 'AUSENTE') {
            if ($situacaoArquivo -ne 'AUSENTE') { Registrar "Arquivo não encontrado: $arquivo" }
            $situacaoArquivo = 'AUSENTE'
            $hashAtual = $null
            $pendente = $false
            $ultimoVisto = $visto
        }
        # 'OCUPADO': ainda sendo gravado; confere de novo no próximo ciclo.
    }

    if ((Get-Date) -ge $proximoSinal -and -not $pendente) {
        try {
            $resposta = Enviar-Sinal $hashAtual
            if ($resposta.enviarArquivo) {
                Registrar 'O servidor não tem o arquivo atual da loja: reenviando.'
                $estado.ultimoHashEnviado = $null
                $pendente = $true
            }
            $proximoSinal = (Get-Date).AddMinutes($intervaloSinal)
        } catch {
            Registrar "Falha no sinal de vida: $(Descrever-Erro $_). Nova tentativa em 1 min."
            $proximoSinal = (Get-Date).AddMinutes(1)
        }
    }

    if ((Get-Date).Date -ne $diaLimpeza) {
        $diaLimpeza = (Get-Date).Date
        Limpar-LogsAntigos
    }
}
