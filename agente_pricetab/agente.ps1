# Agente Simplifica Compras: leva os preços da loja para a API do Simplifica Compras.
#
# Um agente só, com MODOS (config.json, campo "modo"):
#   "arquivo" (padrão) - vigia o PRICETAB.TXT e envia sempre que ele muda;
#   "rpinfo"           - consulta a API da RPInfo ("RP Services") NA REDE INTERNA da loja e envia
#                        pacotes JSON só com os campos de produto e preço;
#   "banco"            - lê, por ODBC, a VIEW padrão vw_simplifica_precos no banco do ERP DENTRO da
#                        loja (usuário só com SELECT nela) e envia pacotes JSON (POST /cargas/banco).
#
# Segurança (vale para os dois modos):
# - Só faz conexões de SAÍDA. Não abre porta, não aceita conexões, não executa nada que venha de
#   fora: as respostas do servidor são só marcações fixas de sim/não ("envie de novo", "faça uma
#   completa"). Sem atualização automática: toda versão nova é instalada pela TI da loja.
# - Chave da loja e senha da API podem ficar PROTEGIDAS pelo Windows (DPAPI, ver proteger.ps1):
#   só este computador consegue ler. Nunca aparecem no log.
# - Esperas crescentes com variação aleatória entre tentativas (não sobrecarrega a rede nem o servidor).
# - Modo rpinfo: só envia código, código de barras, descrição, preços, oferta (só as já vigentes),
#   departamento, balança e se está ativo. Custo, margem, estoque, fornecedor e dados fiscais NÃO
#   saem da loja. Cópia legível de cada pacote enviado na pasta "auditoria" (modo auditoria).
#
# Uso: agente.ps1 [-Config caminho] [-TestarConexao]
#   -TestarConexao (modo rpinfo): testa login, unidade, departamentos e 1ª página da API e sai.
#   -TestarConexao (modo banco): lê a VIEW, confere a coluna data_alteracao e o servidor, e sai.

param([string]$Config = (Join-Path $PSScriptRoot 'config.json'), [switch]$TestarConexao)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$versaoAgente = '2.1'

$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$url = $cfg.url.TrimEnd('/')
$modo = if ($cfg.modo) { [string]$cfg.modo } else { 'arquivo' }
$intervaloSinal = if ($cfg.intervaloSinalMinutos) { [double]$cfg.intervaloSinalMinutos } else { 5 }
$pastaLogs = Join-Path $PSScriptRoot 'logs'
$caminhoEstado = Join-Path $PSScriptRoot 'estado.json'
$esperasSegundos = @(10, 30, 60, 120, 300)
$aleatorio = New-Object Random
New-Item -ItemType Directory -Force $pastaLogs | Out-Null

function Registrar([string]$mensagem) {
    $linha = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $mensagem
    Add-Content -Path (Join-Path $pastaLogs ('agente-{0:yyyy-MM-dd}.log' -f (Get-Date))) -Value $linha -Encoding UTF8
    Write-Host $linha
}

function Limpar-Antigos([string]$pasta, [string]$filtro) {
    if (Test-Path $pasta) {
        Get-ChildItem $pasta -Filter $filtro |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# Segredo protegido pelo Windows (DPAPI, escopo do computador): "dpapi:<base64>" -> texto.
function Ler-Segredo($valor) {
    if ($null -eq $valor) { return $null }
    $texto = [string]$valor
    if (-not $texto.StartsWith('dpapi:')) { return $texto }
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String($texto.Substring(6))
    $claro = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Text.Encoding]::UTF8.GetString($claro)
}

$chave = Ler-Segredo $(if ($cfg.chaveProtegida) { $cfg.chaveProtegida } else { $cfg.chave })
if (-not $cfg.chaveProtegida) { Registrar 'Aviso: a chave da loja está em texto aberto no config.json. Proteja com proteger.ps1.' }

# Identificação do agente (só 1 agente por loja): computador + pasta de instalação, em resumo.
function Id-Agente {
    $maquina = try { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid } catch { $env:COMPUTERNAME }
    $resumo = Hash-Texto ("$maquina|$PSScriptRoot".ToLowerInvariant())
    return 'ag-' + $resumo.Substring(0, 32)
}

function Hash-Sha256([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

function Hash-Texto([string]$texto) { return Hash-Sha256 ([Text.Encoding]::UTF8.GetBytes($texto)) }

$cabecalhos = @{ 'X-Chave-Loja' = $chave; 'X-Agente-Id' = (Id-Agente) }

# Espera da próxima tentativa: cresce a cada falha e varia ±20% (várias lojas não tentam juntas).
function Espera-Segundos([int]$falhas) {
    $base = $esperasSegundos[[Math]::Min($falhas, $esperasSegundos.Count - 1)]
    return [int]($base * (0.8 + 0.4 * $aleatorio.NextDouble()))
}

function Descrever-Erro($erro) {
    $resposta = $erro.Exception.Response
    if ($resposta -and $resposta.StatusCode) {
        $detalhe = ''
        try {
            # O PowerShell 5.1 às vezes já leu o corpo do erro (fica em ErrorDetails); senão, lê aqui.
            $corpo = if ($erro.ErrorDetails -and $erro.ErrorDetails.Message) { $erro.ErrorDetails.Message } else {
                $fluxo = $resposta.GetResponseStream()
                if ($fluxo.CanSeek) { $fluxo.Position = 0 }
                (New-Object IO.StreamReader($fluxo, [Text.Encoding]::UTF8)).ReadToEnd()
            }
            # Só a mensagem (nunca o stackTrace que algumas APIs devolvem).
            try {
                $json = $corpo | ConvertFrom-Json
                if ($json.error) { $detalhe = [string]$json.error }
                elseif ($json.response.messages) { $detalhe = (($json.response.messages | Select-Object -First 2 | ForEach-Object { $_.message }) -join ' | ') }
                elseif ($json.content -is [string]) { $detalhe = $json.content }
            } catch { $detalhe = $corpo }
            if ($detalhe.Length -gt 200) { $detalhe = $detalhe.Substring(0, 200) + '...' }
        } catch { }
        return "HTTP $([int]$resposta.StatusCode)$(if ($detalhe) { ': ' + $detalhe })"
    }
    return $erro.Exception.Message
}

function Ler-Estado($padrao) {
    if (Test-Path $caminhoEstado) {
        try { return Get-Content $caminhoEstado -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return $padrao
}

function Salvar-Estado($estado) {
    $estado | ConvertTo-Json | Set-Content $caminhoEstado -Encoding UTF8
}

function Ler-Corpo($resposta) {
    return [Text.Encoding]::UTF8.GetString($resposta.RawContentStream.ToArray())
}

function Enviar-Sinal($hash) {
    $corpo = [Text.Encoding]::UTF8.GetBytes((@{ hash = $hash } | ConvertTo-Json -Compress))
    $resposta = Invoke-WebRequest -Uri "$url/cargas/sinal" -Method Post -Body $corpo `
        -ContentType 'application/json; charset=utf-8' -Headers $cabecalhos -UseBasicParsing -TimeoutSec 30
    return (Ler-Corpo $resposta) | ConvertFrom-Json
}

# ==============================================================================================
# MODO "arquivo": vigia o PRICETAB.TXT
# ==============================================================================================
# - Só envia o arquivo depois que ele termina de ser gravado (tamanho e data parados por 3 s e
#   nenhum outro programa com o arquivo aberto para escrita): nunca manda um arquivo pela metade.
# - Não reenvia o mesmo conteúdo (compara o SHA-256 com o do último envio).
# - Envia os bytes exatamente como estão (Latin-1), sem conversão: os acentos não se perdem.
# - Ao iniciar e a cada N minutos manda o "sinal de vida"; se o servidor não tiver o arquivo que
#   está na loja (envio perdido), ele pede e o agente reenvia.

function Executar-ModoArquivo {
    $arquivo = Join-Path $cfg.pasta $cfg.arquivo

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

    function Enviar-Arquivo([byte[]]$bytes) {
        $resposta = Invoke-WebRequest -Uri "$url/cargas/pricetab" -Method Post -Body $bytes `
            -ContentType 'text/plain; charset=ISO-8859-1' -Headers $cabecalhos -UseBasicParsing -TimeoutSec 120
        return (Ler-Corpo $resposta) | ConvertFrom-Json
    }

    Registrar "Agente $versaoAgente (modo arquivo) iniciado. Vigiando '$arquivo' -> $url (sinal a cada $intervaloSinal min)."
    Limpar-Antigos $pastaLogs 'agente-*.log'
    $estado = Ler-Estado ([pscustomobject]@{ ultimoHashEnviado = $null; ultimoEnvioEm = $null })
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
                        $espera = Espera-Segundos $tentativasFalhas
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
                if ($resposta.enviarArquivo -eq $true) {
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
            Limpar-Antigos $pastaLogs 'agente-*.log'
        }
    }
}

# ==============================================================================================
# MODO "rpinfo": consulta a API da RPInfo na rede interna e envia pacotes JSON
# ==============================================================================================
# Ciclo:
# - COMPLETA ao iniciar, no horário combinado (rpinfo.horarioCompleta, 1 vez por dia) e quando a
#   resposta ao sinal trouxer "fazerCompleta": todos os produtos ativos, de 100 em 100. Monta a
#   FOTO LOCAL e envia um pacote COMPLETO se a foto mudou.
# - INCREMENTAL a cada rpinfo.intervaloMinutos: produtos alterados desde a última coleta (com folga),
#   inclusive os desativados, + excluídos do dia. Envia um pacote PARCIAL só se algo mudou.
# - Pacotes que não puderem ser enviados (internet/servidor) ficam na pasta "fila" e saem na ordem.
# - Oferta FUTURA não sai da loja antes da data: o pacote leva o produto sem a oferta, e o agente
#   reenvia o produto quando a oferta começa.

$camposProduto = @('Codigo', 'CodigoBarras', 'Descricao', 'Preco', 'PrecoPDV', 'PrecoNormal', 'Oferta', 'DtIniOferta',
    'DataOferta', 'Balanca', 'CodigoDepartamento', 'Departamento', 'Ativo')

function Executar-ModoRpinfo {
    $r = $cfg.rpinfo
    $apiUrl = ([string]$r.url).TrimEnd('/')
    $usuario = [string]$r.usuario
    $senha = Ler-Segredo $(if ($r.senhaProtegida) { $r.senhaProtegida } else { $r.senha })
    if (-not $r.senhaProtegida) { Registrar 'Aviso: a senha da API está em texto aberto no config.json. Proteja com proteger.ps1.' }
    $cnpj = [string]$r.cnpj
    $tamanhoPagina = if ($r.tamanhoPagina) { [int]$r.tamanhoPagina } else { 100 }
    $intervaloMin = if ($r.intervaloMinutos) { [double]$r.intervaloMinutos } else { 5 }
    $folgaMin = if ($r.folgaMinutos) { [double]$r.folgaMinutos } else { 10 }
    $horarioCompleta = if ($r.horarioCompleta) { [string]$r.horarioCompleta } else { '12:00' }
    $auditoria = -not ($cfg.auditoria -eq $false)
    $pastaFila = Join-Path $PSScriptRoot 'fila'
    $pastaAuditoria = Join-Path $PSScriptRoot 'auditoria'
    New-Item -ItemType Directory -Force $pastaFila, $pastaAuditoria | Out-Null

    $script:token = $null
    $foto = @{}        # Codigo -> produto (campos mínimos, como veio da RPInfo)
    $jsonEnviado = @{} # Codigo -> JSON do produto como vai no pacote (oferta futura retirada)
    $departamentos = @{}

    function Api-Login {
        $corpo = [Text.Encoding]::UTF8.GetBytes((@{ usuario = $usuario; senha = $senha } | ConvertTo-Json -Compress))
        $resposta = Invoke-WebRequest -Uri "$apiUrl/v1.2/auth" -Method Post -Body $corpo -ContentType 'application/json; charset=utf-8' `
            -UseBasicParsing -TimeoutSec 60
        $json = (Ler-Corpo $resposta) | ConvertFrom-Json
        if (-not $json.response.content.token) { throw 'Login da API sem token na resposta.' }
        $script:token = [string]$json.response.content.token
    }

    # GET na API interna; 401 (token vencido): login de novo UMA vez e repete.
    function Api-Get([string]$caminho) {
        if (-not $script:token) { Api-Login }
        try {
            $resposta = Invoke-WebRequest -Uri "$apiUrl$caminho" -Headers @{ token = $script:token } -UseBasicParsing -TimeoutSec 60
        } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) {
                Api-Login
                $resposta = Invoke-WebRequest -Uri "$apiUrl$caminho" -Headers @{ token = $script:token } -UseBasicParsing -TimeoutSec 60
            } else { throw }
        }
        $json = (Ler-Corpo $resposta) | ConvertFrom-Json
        if ($json.response.status -ne 'ok') {
            $msg = (($json.response.messages | Select-Object -First 2 | ForEach-Object { $_.message }) -join ' | ')
            throw "API respondeu sem status ok: $msg"
        }
        return $json.response
    }

    # Páginas pelo último código (fim: página incompleta ou vazia). Chama $cadaItem para cada item.
    function Api-Paginar([scriptblock]$caminho, [string]$lista, [string]$campoCodigo, [scriptblock]$cadaItem) {
        $ultimo = 0; $paginas = 0
        while ($paginas -lt 2000) {
            $resp = Api-Get (& $caminho $ultimo)
            $paginas++
            $itens = @($resp.$lista)
            foreach ($item in $itens) { & $cadaItem $item }
            if ($itens.Count -lt $tamanhoPagina) { break }
            $proximo = [long]$itens[$itens.Count - 1].$campoCodigo
            if ($proximo -le $ultimo) { throw "Paginação não avançou (último código $proximo)." }
            $ultimo = $proximo
        }
        return $paginas
    }

    function Ler-Departamentos {
        $lidos = @((Api-Get '/v1.1/departamentos').content)
        if ($lidos.Count) {
            $departamentos.Clear()
            foreach ($d in $lidos) { $departamentos[[string]$d.codigo] = [string]$d.descricao }
        }
        return $departamentos.Count
    }

    function Minimo($p) {
        $m = [ordered]@{}
        foreach ($c in $camposProduto) { $m[$c] = $p.$c }
        $m['codBarrasAlterados'] = @(@($p.codBarrasAlterados) | Where-Object { $_ } | ForEach-Object {
            [ordered]@{ codigoBarras = $_.codigoBarras; precoVenda = $_.precoVenda; fatorEmbalagem = $_.fatorEmbalagem } })
        return $m
    }

    # O produto como vai no pacote: oferta que ainda não começou é retirada (não vaza estratégia).
    function Json-Envio($m) {
        $e = [ordered]@{}
        foreach ($k in $m.Keys) { $e[$k] = $m[$k] }
        if ($e['Oferta'] -eq 'S' -and $e['DtIniOferta']) {
            try {
                $inicio = [datetime]::ParseExact([string]$e['DtIniOferta'], 'dd-MM-yyyy', $null)
                if ($inicio.Date -gt (Get-Date).Date) {
                    $e['Oferta'] = 'N'; $e['PrecoNormal'] = 0; $e['DtIniOferta'] = ''; $e['DataOferta'] = ''
                }
            } catch { }
        }
        return ($e | ConvertTo-Json -Compress -Depth 4)
    }

    function Hash-Foto {
        $partes = foreach ($k in ($jsonEnviado.Keys | Sort-Object)) { "$k=$(Hash-Texto $jsonEnviado[$k])" }
        return Hash-Texto (($partes) -join "`n")
    }

    function Departamentos-Json {
        $d = [ordered]@{}
        foreach ($k in ($departamentos.Keys | Sort-Object)) { $d[$k] = $departamentos[$k] }
        return ($d | ConvertTo-Json -Compress)
    }

    # Monta o pacote, guarda a cópia de auditoria e põe na fila (a fila envia na ordem).
    function Enfileirar([string]$tipo, [string[]]$produtosJson, [object[]]$excluidos, [string]$hashFoto) {
        $agora = Get-Date
        $exc = if ($excluidos -and $excluidos.Count) { '[' + (($excluidos | ForEach-Object { [string]$_ }) -join ',') + ']' } else { '[]' }
        $texto = '{"tipo":"' + $tipo + '","geradoEm":"' + $agora.ToString('yyyy-MM-ddTHH:mm:sszzz') + '","versaoAgente":"' + $versaoAgente +
            '","hashFoto":"' + $hashFoto + '","departamentos":' + (Departamentos-Json) + ',"produtos":[' + ($produtosJson -join ',') +
            '],"excluidos":' + $exc + '}'
        $nome = '{0:yyyyMMdd-HHmmss-fff}-{1}' -f $agora, $tipo
        if ($auditoria) { [IO.File]::WriteAllText((Join-Path $pastaAuditoria "$nome.json"), $texto, (New-Object Text.UTF8Encoding $false)) }
        $memoria = New-Object IO.MemoryStream
        $gz = New-Object IO.Compression.GZipStream($memoria, [IO.Compression.CompressionMode]::Compress)
        $bytes = [Text.Encoding]::UTF8.GetBytes($texto)
        $gz.Write($bytes, 0, $bytes.Length); $gz.Close()
        [IO.File]::WriteAllBytes((Join-Path $pastaFila "$nome.json.gz"), $memoria.ToArray())
        Registrar ("Pacote {0} na fila: {1} produto(s), {2} excluído(s), {3:N0} bytes compactado (foto {4})." -f
            $tipo, $produtosJson.Count, @($excluidos).Count, $memoria.ToArray().Length, $hashFoto.Substring(0, 12))
    }

    # Envia a fila na ordem. Para no 1º erro (tenta de novo depois, com espera crescente).
    function Enviar-Fila {
        foreach ($f in (Get-ChildItem $pastaFila -Filter '*.json.gz' | Sort-Object Name)) {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            try {
                $resposta = Invoke-WebRequest -Uri "$url/cargas/rpinfo" -Method Post -Body $bytes -ContentType 'application/gzip' `
                    -Headers $cabecalhos -UseBasicParsing -TimeoutSec 120
                $json = (Ler-Corpo $resposta) | ConvertFrom-Json
                Registrar "Pacote $($f.Name) enviado: $($json.situacao) - $($json.mensagem)"
                Remove-Item $f.FullName -Force
            } catch {
                $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                if ($status -eq 400) {
                    # Pacote recusado como inválido: guardar à parte (não trava a fila) e avisar.
                    Move-Item $f.FullName (Join-Path $pastaFila ($f.Name + '.recusado')) -Force
                    Registrar "Pacote $($f.Name) RECUSADO pelo servidor: $(Descrever-Erro $_). Guardado como .recusado."
                    continue
                }
                throw
            }
        }
    }

    function Coleta-Completa {
        $inicio = Get-Date
        $null = Ler-Departamentos
        $novaFoto = @{}
        $unidadeUrl = [uri]::EscapeDataString($cnpj)
        $paginas = Api-Paginar { param($u) "/v3.2/produtounidade/listaprodutos/$u/unidade/$unidadeUrl/detalhado/ativos?limit=$tamanhoPagina" } `
            'produtos' 'Codigo' { param($p) $novaFoto[[string]$p.Codigo] = Minimo $p }
        $novoJson = @{}
        foreach ($k in $novaFoto.Keys) { $novoJson[$k] = Json-Envio $novaFoto[$k] }
        $foto.Clear(); foreach ($k in $novaFoto.Keys) { $foto[$k] = $novaFoto[$k] }
        $jsonEnviado.Clear(); foreach ($k in $novoJson.Keys) { $jsonEnviado[$k] = $novoJson[$k] }
        $hash = Hash-Foto
        Registrar ("Coleta COMPLETA: {0} página(s), {1} produto(s) em {2:N1} s." -f $paginas, $foto.Count, ((Get-Date) - $inicio).TotalSeconds)
        return @{ hash = $hash; inicio = $inicio }
    }

    function Coleta-Incremental([datetime]$desde) {
        $inicio = Get-Date
        $null = Ler-Departamentos
        $unidadeUrl = [uri]::EscapeDataString($cnpj)
        $quando = $desde.ToString('dd-MM-yyyy HH:mm:ss').Replace(' ', '%20')
        $mudados = New-Object System.Collections.Generic.List[string]
        $excluidos = New-Object System.Collections.Generic.List[object]
        $paginas = Api-Paginar { param($u) "/v3.2/produtounidade/listaprodutos/$u/unidade/$unidadeUrl/detalhado/dataHoraManutencao/$quando`?limit=$tamanhoPagina" } `
            'produtos' 'Codigo' {
                param($p)
                $k = [string]$p.Codigo
                if ($p.Ativo -eq $false) {
                    if ($foto.ContainsKey($k)) { $foto.Remove($k); $jsonEnviado.Remove($k); $excluidos.Add([long]$k) }
                } else {
                    $m = Minimo $p
                    $j = Json-Envio $m
                    $foto[$k] = $m
                    if ($jsonEnviado[$k] -ne $j) { $jsonEnviado[$k] = $j; $mudados.Add($k) }
                }
            }
        $paginas += Api-Paginar { param($u) "/v1.1/produto/excluidos/lastid/$u/dataexclusao/$($desde.ToString('dd-MM-yyyy'))" } `
            'excluidos' 'codigoProduto' {
                param($e)
                $k = [string]$e.codigoProduto
                if ($foto.ContainsKey($k)) { $foto.Remove($k); $jsonEnviado.Remove($k); $excluidos.Add([long]$k) }
            }
        # Oferta futura que começou hoje: o produto não mudou na API, mas muda o que pode sair da loja.
        foreach ($k in @($foto.Keys)) {
            if ($foto[$k]['Oferta'] -eq 'S') {
                $j = Json-Envio $foto[$k]
                if ($jsonEnviado[$k] -ne $j) { $jsonEnviado[$k] = $j; if (-not $mudados.Contains($k)) { $mudados.Add($k) } }
            }
        }
        Registrar ("Coleta incremental desde {0:dd/MM HH:mm}: {1} página(s), {2} mudado(s), {3} excluído(s)/desativado(s) em {4:N1} s." -f
            $desde, $paginas, $mudados.Count, $excluidos.Count, ((Get-Date) - $inicio).TotalSeconds)
        return @{ mudados = $mudados; excluidos = $excluidos; inicio = $inicio }
    }

    if ($TestarConexao) {
        Registrar "Teste de conexão com a API RPInfo em $apiUrl (unidade $cnpj)..."
        try {
            Api-Login; Registrar '  Login: OK (token recebido).'
            $unidades = @((Api-Get '/v1.6/unidades').content)
            $achou = @($unidades | Where-Object { [string]$_.cnpj -eq $cnpj })
            if ($achou.Count) { Registrar "  Unidade: OK ($($achou[0].nome))." } else { Registrar "  Unidade: CNPJ $cnpj NÃO encontrado entre $($unidades.Count) unidade(s)." }
            Registrar "  Departamentos: $(Ler-Departamentos)."
            $resp = Api-Get "/v3.2/produtounidade/listaprodutos/0/unidade/$([uri]::EscapeDataString($cnpj))/detalhado/ativos?limit=$tamanhoPagina"
            Registrar "  1ª página de produtos: $(@($resp.produtos).Count) produto(s). Conexão com a API: OK."
        } catch { Registrar "  FALHOU: $(Descrever-Erro $_)" }
        try { $null = Enviar-Sinal $null; Registrar "  Servidor Simplifica ($url): OK." } catch { Registrar "  Servidor Simplifica ($url): FALHOU: $(Descrever-Erro $_)" }
        return
    }

    Registrar "Agente $versaoAgente (modo rpinfo) iniciado. API interna $apiUrl (unidade $cnpj) -> $url. Incremental a cada $intervaloMin min; completa ao iniciar e às $horarioCompleta; sinal a cada $intervaloSinal min."
    Limpar-Antigos $pastaLogs 'agente-*.log'
    $estado = Ler-Estado ([pscustomobject]@{ hashFotoEnviada = $null; ultimaCompleta = $null; completaNoHorario = $null; incrementalDesde = $null })
    foreach ($campo in 'hashFotoEnviada', 'ultimaCompleta', 'completaNoHorario', 'incrementalDesde') {
        if (-not ($estado.PSObject.Properties.Name -contains $campo)) { $estado | Add-Member -NotePropertyName $campo -NotePropertyValue $null }
    }
    $precisaCompleta = $true         # ao iniciar
    $reenviarFoto = $false
    $falhasColeta = 0; $proximaColeta = Get-Date
    $falhasEnvio = 0; $proximoEnvio = Get-Date
    $proximoSinal = (Get-Date).AddSeconds(20)
    $diaLimpeza = (Get-Date).Date

    while ($true) {
        $agora = Get-Date
        # Horário combinado: 1 completa por dia, a partir do horário.
        $hoje = $agora.ToString('yyyy-MM-dd')
        if (-not $precisaCompleta -and $agora.ToString('HH:mm') -ge $horarioCompleta -and $estado.completaNoHorario -ne $hoje) {
            Registrar "Horário da coleta completa ($horarioCompleta)."
            $estado.completaNoHorario = $hoje
            $precisaCompleta = $true
        }

        if ($agora -ge $proximaColeta -and ($precisaCompleta -or -not $estado.incrementalDesde -or
                $agora -ge ([datetime]$estado.incrementalDesde).AddMinutes($intervaloMin))) {
            try {
                if ($precisaCompleta -or -not $foto.Count) {
                    $res = Coleta-Completa
                    if ($res.hash -ne $estado.hashFotoEnviada -or $reenviarFoto) {
                        Enfileirar 'COMPLETA' @($jsonEnviado.Values) @() $res.hash
                        $estado.hashFotoEnviada = $res.hash
                    } else { Registrar 'Foto igual à última enviada: nada a enviar.' }
                    $estado.ultimaCompleta = $hoje
                    # Completa feita a partir do horário combinado (inclusive a de quando o agente liga)
                    # já vale como a completa do dia: não repete logo em seguida.
                    if ($agora.ToString('HH:mm') -ge $horarioCompleta) { $estado.completaNoHorario = $hoje }
                    $precisaCompleta = $false; $reenviarFoto = $false
                } else {
                    $desde = ([datetime]$estado.incrementalDesde).AddMinutes(-$folgaMin)
                    $res = Coleta-Incremental $desde
                    if ($res.mudados.Count -or $res.excluidos.Count) {
                        $hash = Hash-Foto
                        # .ToArray(): no PowerShell 5.1, @() sobre uma List[object] vazia dá erro de tipos.
                        $produtos = [string[]]($res.mudados.ToArray() | ForEach-Object { $jsonEnviado[$_] })
                        Enfileirar 'PARCIAL' $produtos $res.excluidos.ToArray() $hash
                        $estado.hashFotoEnviada = $hash
                    }
                }
                $estado.incrementalDesde = $res.inicio.ToString('o')
                Salvar-Estado $estado
                $falhasColeta = 0
            } catch {
                $espera = Espera-Segundos $falhasColeta
                $falhasColeta++
                $proximaColeta = (Get-Date).AddSeconds($espera)
                Registrar "Falha na coleta da API RPInfo: $(Descrever-Erro $_) (linha $($_.InvocationInfo.ScriptLineNumber)). Nova tentativa em $espera s."
            }
        }

        if ((Get-Date) -ge $proximoEnvio -and (Get-ChildItem $pastaFila -Filter '*.json.gz' | Select-Object -First 1)) {
            try { Enviar-Fila; $falhasEnvio = 0 } catch {
                $espera = Espera-Segundos $falhasEnvio
                $falhasEnvio++
                $proximoEnvio = (Get-Date).AddSeconds($espera)
                Registrar "Falha ao enviar pacote: $(Descrever-Erro $_). Fica na fila; nova tentativa em $espera s."
            }
        }

        if ((Get-Date) -ge $proximoSinal) {
            try {
                $resposta = Enviar-Sinal $estado.hashFotoEnviada
                if ($resposta.fazerCompleta -eq $true -and -not $precisaCompleta) {
                    Registrar 'O servidor sinalizou "fazer completa".'
                    $precisaCompleta = $true; $proximaColeta = Get-Date
                }
                if ($resposta.enviarArquivo -eq $true -and -not (Get-ChildItem $pastaFila -Filter '*.json.gz' | Select-Object -First 1)) {
                    Registrar 'O servidor não tem a foto atual da loja: nova completa e reenvio.'
                    $precisaCompleta = $true; $reenviarFoto = $true; $proximaColeta = Get-Date
                }
                $proximoSinal = (Get-Date).AddMinutes($intervaloSinal)
            } catch {
                Registrar "Falha no sinal de vida: $(Descrever-Erro $_). Nova tentativa em 1 min."
                $proximoSinal = (Get-Date).AddMinutes(1)
            }
        }

        if ((Get-Date).Date -ne $diaLimpeza) {
            $diaLimpeza = (Get-Date).Date
            Limpar-Antigos $pastaLogs 'agente-*.log'
            Limpar-Antigos $pastaAuditoria '*.json'
        }
        Start-Sleep -Seconds 5
    }
}

# ----------------------------------------------------------------------------------------------
# Modo "banco": lê a VIEW padrão (vw_simplifica_precos) no banco do ERP DENTRO da loja, por ODBC
# (driver oficial do fabricante instalado pela TI: MySQL, SQL Server, PostgreSQL, Firebird,
# Oracle...), com um usuário que só tem SELECT na VIEW. Envia pacotes para POST /cargas/banco.
# Contrato da VIEW: laboratorio/conector_banco/CONTRATO_VIEW.md.
# ----------------------------------------------------------------------------------------------
$colunasView = @('codigo_barras', 'descricao', 'preco', 'preco_promocional', 'promocao_ate', 'unidade', 'secao',
    'codigo_interno', 'ativo')

function Executar-ModoBanco {
    $b = $cfg.banco
    $conexao = [string]$b.conexao
    $usuario = [string]$b.usuario
    $senha = Ler-Segredo $(if ($b.senhaProtegida) { $b.senhaProtegida } else { $b.senha })
    if (-not $b.senhaProtegida) { Registrar 'Aviso: a senha do banco está em texto aberto no config.json. Proteja com proteger.ps1.' }
    $view = if ($b.view) { [string]$b.view } else { 'vw_simplifica_precos' }
    if ($view -notmatch '^[A-Za-z_][A-Za-z0-9_.]*$') { throw "Nome de VIEW inválido no config.json: '$view'." }
    $usaIncremental = -not ($b.incremental -eq $false)   # VIEW tem a coluna data_alteracao
    $intervaloMin = if ($b.intervaloMinutos) { [double]$b.intervaloMinutos } else { 5 }
    $folgaMin = if ($b.folgaMinutos) { [double]$b.folgaMinutos } else { 10 }
    $horarioCompleta = if ($b.horarioCompleta) { [string]$b.horarioCompleta } else { '12:00' }
    $auditoria = -not ($cfg.auditoria -eq $false)
    $pastaFila = Join-Path $PSScriptRoot 'fila'
    $pastaAuditoria = Join-Path $PSScriptRoot 'auditoria'
    New-Item -ItemType Directory -Force $pastaFila, $pastaAuditoria | Out-Null
    $inv = [Globalization.CultureInfo]::InvariantCulture

    $foto = @{}        # codigo_barras -> JSON da linha como vai no pacote
    $internoDe = @{}   # codigo_barras -> codigo_interno (para avisar o servidor de linhas que sumiram)

    function Valor($v) {
        if ($v -is [DBNull] -or $null -eq $v) { return $null }
        if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd HH:mm:ss') }
        if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) { return $v.ToString($inv) }
        return ([string]$v).Trim()
    }

    # Lê a VIEW (toda, ou só o que mudou desde $desde). Devolve codigo_barras -> linha (ordered).
    function Ler-View($desde) {
        $cs = $conexao.TrimEnd(';') + ";Uid=$usuario;Pwd=$senha;"
        $con = New-Object System.Data.Odbc.OdbcConnection $cs
        $linhas = @{}
        try {
            $con.Open()
            $cmd = $con.CreateCommand()
            $cmd.CommandTimeout = 300
            $sql = "SELECT $($colunasView -join ', ') FROM $view"
            if ($null -ne $desde) {
                $sql += ' WHERE data_alteracao >= ?'
                $p = New-Object System.Data.Odbc.OdbcParameter('desde', [System.Data.Odbc.OdbcType]::DateTime)
                $p.Value = $desde
                $null = $cmd.Parameters.Add($p)
            }
            $cmd.CommandText = $sql
            $leitor = $cmd.ExecuteReader()
            while ($leitor.Read()) {
                $l = [ordered]@{}
                for ($i = 0; $i -lt $colunasView.Count; $i++) { $l[$colunasView[$i]] = Valor ($leitor.GetValue($i)) }
                if ($l['codigo_barras']) { $linhas[$l['codigo_barras']] = $l }
            }
            $leitor.Close()
        } finally { $con.Close() }
        return $linhas
    }

    function Json-Linha($l) { return ($l | ConvertTo-Json -Compress) }

    function Hash-Foto {
        $partes = foreach ($k in ($foto.Keys | Sort-Object)) { "$k=$(Hash-Texto $foto[$k])" }
        return Hash-Texto (($partes) -join "`n")
    }

    function Enfileirar([string]$tipo, [string[]]$linhasJson, [string[]]$excluidos, [string]$hashFoto) {
        $agora = Get-Date
        $exc = '[' + ((@($excluidos) | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { ConvertTo-Json ([string]$_) -Compress }) -join ',') + ']'
        $texto = '{"tipo":"' + $tipo + '","geradoEm":"' + $agora.ToString('yyyy-MM-ddTHH:mm:sszzz') + '","versaoAgente":"' + $versaoAgente +
            '","hashFoto":"' + $hashFoto + '","linhas":[' + ($linhasJson -join ',') + '],"excluidos":' + $exc + '}'
        $nome = '{0:yyyyMMdd-HHmmss-fff}-{1}' -f $agora, $tipo
        if ($auditoria) { [IO.File]::WriteAllText((Join-Path $pastaAuditoria "$nome.json"), $texto, (New-Object Text.UTF8Encoding $false)) }
        $memoria = New-Object IO.MemoryStream
        $gz = New-Object IO.Compression.GZipStream($memoria, [IO.Compression.CompressionMode]::Compress)
        $bytes = [Text.Encoding]::UTF8.GetBytes($texto)
        $gz.Write($bytes, 0, $bytes.Length); $gz.Close()
        [IO.File]::WriteAllBytes((Join-Path $pastaFila "$nome.json.gz"), $memoria.ToArray())
        Registrar ("Pacote {0} na fila: {1} linha(s), {2} produto(s) excluído(s), {3:N0} bytes compactado (foto {4})." -f
            $tipo, $linhasJson.Count, @($excluidos).Count, $memoria.ToArray().Length, $hashFoto.Substring(0, 12))
    }

    function Enviar-Fila {
        foreach ($f in (Get-ChildItem $pastaFila -Filter '*.json.gz' | Sort-Object Name)) {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            try {
                $resposta = Invoke-WebRequest -Uri "$url/cargas/banco" -Method Post -Body $bytes -ContentType 'application/gzip' `
                    -Headers $cabecalhos -UseBasicParsing -TimeoutSec 120
                $json = (Ler-Corpo $resposta) | ConvertFrom-Json
                Registrar "Pacote $($f.Name) enviado: $($json.situacao) - $($json.mensagem)"
                Remove-Item $f.FullName -Force
            } catch {
                $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                if ($status -eq 400) {
                    Move-Item $f.FullName (Join-Path $pastaFila ($f.Name + '.recusado')) -Force
                    Registrar "Pacote $($f.Name) RECUSADO pelo servidor: $(Descrever-Erro $_). Guardado como .recusado."
                    continue
                }
                throw
            }
        }
    }

    # Completa: a VIEW inteira vira a foto.
    function Coleta-Completa {
        $inicio = Get-Date
        $lidas = Ler-View $null
        $foto.Clear(); $internoDe.Clear()
        foreach ($k in $lidas.Keys) { $foto[$k] = Json-Linha $lidas[$k]; $internoDe[$k] = $lidas[$k]['codigo_interno'] }
        Registrar ("Leitura COMPLETA da VIEW {0}: {1} linha(s) em {2:N1} s." -f $view, $foto.Count, ((Get-Date) - $inicio).TotalSeconds)
        return @{ hash = (Hash-Foto); inicio = $inicio }
    }

    # Incremental: só o que mudou (data_alteracao) ou, sem essa coluna, a VIEW inteira comparada com a
    # foto (aí também acha as linhas que sumiram). Devolve linhas mudadas e internos a avisar.
    function Coleta-Incremental([datetime]$desde) {
        $inicio = Get-Date
        $mudados = New-Object System.Collections.Generic.List[string]
        $excluidos = New-Object System.Collections.Generic.List[string]
        $lidas = if ($usaIncremental) { Ler-View $desde } else { Ler-View $null }
        foreach ($k in $lidas.Keys) {
            $j = Json-Linha $lidas[$k]
            if ($foto[$k] -ne $j) { $foto[$k] = $j; $internoDe[$k] = $lidas[$k]['codigo_interno']; $mudados.Add($k) }
        }
        # O servidor tira da loja os códigos de um produto (codigo_interno) que não vierem no pacote
        # PARCIAL: manda TODOS os códigos de barras de cada produto que mudou, não só a linha mudada.
        $internosMudados = @{}
        foreach ($k in $mudados) { if ($internoDe[$k]) { $internosMudados[[string]$internoDe[$k]] = $true } }
        if ($internosMudados.Count) {
            foreach ($k in @($foto.Keys)) {
                if (-not $mudados.Contains($k) -and $internoDe[$k] -and $internosMudados.ContainsKey([string]$internoDe[$k])) { $mudados.Add($k) }
            }
        }
        if (-not $usaIncremental) {
            foreach ($k in @($foto.Keys)) {
                if (-not $lidas.ContainsKey($k)) {
                    if ($internoDe[$k]) { $excluidos.Add([string]$internoDe[$k]) }
                    $foto.Remove($k); $internoDe.Remove($k)
                }
            }
        }
        Registrar ("Leitura incremental{0}: {1} linha(s) lida(s), {2} mudada(s), {3} removida(s) em {4:N1} s." -f
            $(if ($usaIncremental) { " desde {0:dd/MM HH:mm}" -f $desde } else { ' (VIEW inteira, sem data_alteracao)' }),
            $lidas.Count, $mudados.Count, $excluidos.Count, ((Get-Date) - $inicio).TotalSeconds)
        return @{ mudados = $mudados; excluidos = $excluidos; inicio = $inicio }
    }

    if ($TestarConexao) {
        Registrar "Teste de conexão com o banco (VIEW $view)..."
        try {
            $lidas = Ler-View $null
            $kg = @($lidas.Values | Where-Object { $_['unidade'] -eq 'KG' }).Count
            $of = @($lidas.Values | Where-Object { $_['preco_promocional'] }).Count
            Registrar "  VIEW lida: $($lidas.Count) linha(s) ($kg por kg, $of com preço promocional). Conexão com o banco: OK."
            if ($usaIncremental) { $null = Ler-View ((Get-Date).AddDays(-1)); Registrar '  Coluna data_alteracao: OK (leitura incremental disponível).' }
        } catch { Registrar "  FALHOU: $(Descrever-Erro $_)" }
        try { $null = Enviar-Sinal $null; Registrar "  Servidor Simplifica ($url): OK." } catch { Registrar "  Servidor Simplifica ($url): FALHOU: $(Descrever-Erro $_)" }
        return
    }

    Registrar "Agente $versaoAgente (modo banco) iniciado. VIEW $view -> $url. Incremental a cada $intervaloMin min ($(if ($usaIncremental) { 'por data_alteracao' } else { 'VIEW inteira comparada' })); completa ao iniciar e às $horarioCompleta; sinal a cada $intervaloSinal min."
    Limpar-Antigos $pastaLogs 'agente-*.log'
    $estado = Ler-Estado ([pscustomobject]@{ hashFotoEnviada = $null; ultimaCompleta = $null; completaNoHorario = $null; incrementalDesde = $null })
    foreach ($campo in 'hashFotoEnviada', 'ultimaCompleta', 'completaNoHorario', 'incrementalDesde') {
        if (-not ($estado.PSObject.Properties.Name -contains $campo)) { $estado | Add-Member -NotePropertyName $campo -NotePropertyValue $null }
    }
    $precisaCompleta = $true
    $reenviarFoto = $false
    $falhasColeta = 0; $proximaColeta = Get-Date
    $falhasEnvio = 0; $proximoEnvio = Get-Date
    $proximoSinal = (Get-Date).AddSeconds(20)
    $diaLimpeza = (Get-Date).Date

    while ($true) {
        $agora = Get-Date
        $hoje = $agora.ToString('yyyy-MM-dd')
        if (-not $precisaCompleta -and $agora.ToString('HH:mm') -ge $horarioCompleta -and $estado.completaNoHorario -ne $hoje) {
            Registrar "Horário da leitura completa ($horarioCompleta)."
            $estado.completaNoHorario = $hoje
            $precisaCompleta = $true
        }

        if ($agora -ge $proximaColeta -and ($precisaCompleta -or -not $estado.incrementalDesde -or
                $agora -ge ([datetime]$estado.incrementalDesde).AddMinutes($intervaloMin))) {
            try {
                if ($precisaCompleta -or -not $foto.Count) {
                    $res = Coleta-Completa
                    if ($res.hash -ne $estado.hashFotoEnviada -or $reenviarFoto) {
                        Enfileirar 'COMPLETA' @($foto.Values) @() $res.hash
                        $estado.hashFotoEnviada = $res.hash
                    } else { Registrar 'Foto igual à última enviada: nada a enviar.' }
                    $estado.ultimaCompleta = $hoje
                    if ($agora.ToString('HH:mm') -ge $horarioCompleta) { $estado.completaNoHorario = $hoje }
                    $precisaCompleta = $false; $reenviarFoto = $false
                } else {
                    $res = Coleta-Incremental (([datetime]$estado.incrementalDesde).AddMinutes(-$folgaMin))
                    if ($res.mudados.Count -or $res.excluidos.Count) {
                        $hash = Hash-Foto
                        # Linha que virou ativo = N vai no pacote como está (o servidor a tira da loja).
                        $linhas = [string[]]($res.mudados.ToArray() | ForEach-Object { $foto[$_] })
                        Enfileirar 'PARCIAL' $linhas $res.excluidos.ToArray() $hash
                        $estado.hashFotoEnviada = $hash
                    }
                }
                $estado.incrementalDesde = $res.inicio.ToString('o')
                Salvar-Estado $estado
                $falhasColeta = 0
            } catch {
                $espera = Espera-Segundos $falhasColeta
                $falhasColeta++
                $proximaColeta = (Get-Date).AddSeconds($espera)
                Registrar "Falha na leitura do banco: $(Descrever-Erro $_) (linha $($_.InvocationInfo.ScriptLineNumber)). Nova tentativa em $espera s."
            }
        }

        if ((Get-Date) -ge $proximoEnvio -and (Get-ChildItem $pastaFila -Filter '*.json.gz' | Select-Object -First 1)) {
            try { Enviar-Fila; $falhasEnvio = 0 } catch {
                $espera = Espera-Segundos $falhasEnvio
                $falhasEnvio++
                $proximoEnvio = (Get-Date).AddSeconds($espera)
                Registrar "Falha ao enviar pacote: $(Descrever-Erro $_). Fica na fila; nova tentativa em $espera s."
            }
        }

        if ((Get-Date) -ge $proximoSinal) {
            try {
                $resposta = Enviar-Sinal $estado.hashFotoEnviada
                if ($resposta.fazerCompleta -eq $true -and -not $precisaCompleta) {
                    Registrar 'O servidor sinalizou "fazer completa".'
                    $precisaCompleta = $true; $proximaColeta = Get-Date
                }
                if ($resposta.enviarArquivo -eq $true -and -not (Get-ChildItem $pastaFila -Filter '*.json.gz' | Select-Object -First 1)) {
                    Registrar 'O servidor não tem a foto atual da loja: nova completa e reenvio.'
                    $precisaCompleta = $true; $reenviarFoto = $true; $proximaColeta = Get-Date
                }
                $proximoSinal = (Get-Date).AddMinutes($intervaloSinal)
            } catch {
                Registrar "Falha no sinal de vida: $(Descrever-Erro $_). Nova tentativa em 1 min."
                $proximoSinal = (Get-Date).AddMinutes(1)
            }
        }

        if ((Get-Date).Date -ne $diaLimpeza) {
            $diaLimpeza = (Get-Date).Date
            Limpar-Antigos $pastaLogs 'agente-*.log'
            Limpar-Antigos $pastaAuditoria '*.json'
        }
        Start-Sleep -Seconds 5
    }
}

# ----------------------------------------------------------------------------------------------

switch ($modo) {
    'arquivo' { Executar-ModoArquivo }
    'rpinfo' { Executar-ModoRpinfo }
    'banco' { Executar-ModoBanco }
    default { Registrar "Modo desconhecido no config.json: '$modo' (use 'arquivo', 'rpinfo' ou 'banco')."; exit 1 }
}
