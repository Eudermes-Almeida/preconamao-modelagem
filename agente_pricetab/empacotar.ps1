# Gera o pacote de uma versão do agente para entregar à TI das lojas (pendência C7 do flyer TI):
#   PACOTES_AGENTE\agente-simplifica-<versão>.zip, com
#     pendrive_agente_windows\{agente_pricetab, agente_rpinfo, agente_banco}  (mesma estrutura do SUPER_PENDRIVER)
#     pendrive_agente_linux\{agente_pricetab, agente_rpinfo, agente_banco}
#     NOVIDADES-<versão>.md   (o que mudou, se precisa reconfigurar, segurança, compatibilidade)
#     SHA256.txt              (resumo SHA-256 de cada arquivo, para a TI conferir)
#   e o SHA-256 do próprio zip, para mandar à TI por outro canal (ex.: no corpo do e-mail).
# A versão vem do agente.ps1 ($versaoAgente); exige novidades\NOVIDADES-<versão>.md.
# -AtualizarPendrive: copia também para o SUPER_PENDRIVER (a planilha PASSO A PASSO fica).
# Nunca leva config.json, estado.json, logs, fila nem auditoria (são da loja).
param([switch]$AtualizarPendrive)

$ErrorActionPreference = 'Stop'
$origem = $PSScriptRoot
$raiz = Split-Path (Split-Path $origem)                     # pasta do projeto (fora do git)
$saida = Join-Path $raiz 'PACOTES_AGENTE'

$versao = if ((Get-Content (Join-Path $origem 'agente.ps1') -Raw -Encoding UTF8) -match "\`$versaoAgente = '([^']+)'") { $Matches[1] } else { throw 'Versão não encontrada no agente.ps1' }
$novidades = Join-Path $origem "novidades\NOVIDADES-$versao.md"
if (-not (Test-Path $novidades)) { throw "Falta $novidades (o que mudou nesta versão)." }

$propriedades = Join-Path (Split-Path (Split-Path $origem)) 'back_end_preco_na_mao\src\main\resources\application.properties'
if ((Test-Path $propriedades) -and -not ((Get-Content $propriedades -Raw) -match "agente\.versao-atual=\$\{AGENTE_VERSAO_ATUAL:$([regex]::Escape($versao))\}")) {
    Write-Host "Aviso: agente.versao-atual no application.properties do backend não é $versao (o painel não vai marcar as lojas antigas)." -ForegroundColor Yellow
}

# Arquivos de cada pasta (iguais ao pendrive oficial).
$windows = @{
    'agente_pricetab' = 'LEIA-ME-TI.md', 'agente.ps1', 'config.exemplo.json', 'desinstalar.cmd', 'desinstalar.ps1', 'instalar.cmd', 'instalar.ps1', 'proteger.ps1'
    'agente_rpinfo'   = 'agente.ps1', 'config.exemplo.rpinfo.json', 'desinstalar-rpinfo.cmd', 'desinstalar-rpinfo.ps1', 'instalar-rpinfo.cmd', 'instalar-rpinfo.ps1', 'proteger.ps1'
    'agente_banco'    = 'CONTRATO_VIEW.md', 'LEIA-ME-TI-BANCO.md', 'agente.ps1', 'config.exemplo.banco.json', 'desinstalar-banco.cmd', 'desinstalar-banco.ps1', 'instalar-banco.cmd', 'instalar-banco.ps1', 'proteger.ps1'
}
$linux = 'CONTRATO_VIEW.md', 'LEIA-ME-TI-BANCO.md', 'LEIA-ME-TI-LINUX.md', 'agente.ps1', 'desinstalar.sh', 'instalar.sh'

$nome = "agente-simplifica-$versao"
$montagem = Join-Path $env:TEMP $nome
Remove-Item $montagem -Recurse -Force -ErrorAction SilentlyContinue
foreach ($pasta in $windows.Keys) {
    $destino = Join-Path $montagem "pendrive_agente_windows\$pasta"
    New-Item -ItemType Directory -Force $destino | Out-Null
    $windows[$pasta] | ForEach-Object { Copy-Item (Join-Path $origem $_) $destino }
}
foreach ($pasta in 'agente_pricetab', 'agente_rpinfo', 'agente_banco') {
    $destino = Join-Path $montagem "pendrive_agente_linux\$pasta"
    New-Item -ItemType Directory -Force $destino | Out-Null
    $linux | ForEach-Object { Copy-Item (Join-Path $origem $_) $destino }
}
Copy-Item $novidades $montagem

# SHA256.txt: um arquivo por linha, no formato do sha256sum (a TI confere com sha256sum -c no Linux
# ou comparando com Get-FileHash no Windows).
$linhas = Get-ChildItem $montagem -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relativo = $_.FullName.Substring($montagem.Length + 1).Replace('\', '/')
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relativo
}
[IO.File]::WriteAllText((Join-Path $montagem 'SHA256.txt'), (($linhas -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

New-Item -ItemType Directory -Force $saida | Out-Null
$zip = Join-Path $saida "$nome.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $montagem '*') -DestinationPath $zip
$hashZip = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hashZip  $nome.zip" | Set-Content (Join-Path $saida "$nome.zip.sha256.txt") -Encoding ASCII

if ($AtualizarPendrive) {
    $pendrive = Join-Path $raiz 'SUPER_PENDRIVER'
    foreach ($sub in 'pendrive_agente_windows', 'pendrive_agente_linux') {
        Copy-Item (Join-Path $montagem "$sub\*") (Join-Path $pendrive $sub) -Recurse -Force
    }
    Write-Host "SUPER_PENDRIVER atualizado para a versão $versao."
}
Remove-Item $montagem -Recurse -Force

Write-Host ''
Write-Host "Pacote: $zip ($((Get-ChildItem $zip).Length) bytes, $($linhas.Count) arquivos)" -ForegroundColor Green
Write-Host "SHA-256 do zip (mande à TI por outro canal): $hashZip" -ForegroundColor Green
