# Protege a chave da loja ou a senha da API no config.json do agente (DPAPI do Windows, escopo do
# computador): o valor fica cifrado e só ESTE computador consegue ler. O valor em texto aberto é
# apagado do config.json. Restrinja a pasta do agente à conta que o executa e aos administradores.
#
# Uso (rodar no computador onde o agente vai funcionar):
#   proteger.ps1 -Campo chave        -> pergunta a chave da loja (não aparece na tela)
#   proteger.ps1 -Campo senha        -> pergunta a senha da API da RPInfo (modo rpinfo)
#   -Valor <texto> evita a pergunta (uso em laboratório/automação; não deixe no histórico).

param(
    [Parameter(Mandatory = $true)][ValidateSet('chave', 'senha')][string]$Campo,
    [string]$Valor,
    [string]$Config = (Join-Path $PSScriptRoot 'config.json')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

if (-not $Valor) {
    $seguro = Read-Host -AsSecureString ("Digite a " + $(if ($Campo -eq 'chave') { 'chave da loja' } else { 'senha da API' }))
    $Valor = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro))
}
if (-not $Valor) { throw 'Valor vazio.' }

$cifrado = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($Valor), $null,
    [Security.Cryptography.DataProtectionScope]::LocalMachine)
$texto = 'dpapi:' + [Convert]::ToBase64String($cifrado)

$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Campo -eq 'chave') {
    $cfg | Add-Member -NotePropertyName chaveProtegida -NotePropertyValue $texto -Force
    $cfg.PSObject.Properties.Remove('chave')
} else {
    if (-not $cfg.rpinfo) { throw 'config.json sem a seção "rpinfo".' }
    $cfg.rpinfo | Add-Member -NotePropertyName senhaProtegida -NotePropertyValue $texto -Force
    $cfg.rpinfo.PSObject.Properties.Remove('senha')
}
[IO.File]::WriteAllText($Config, ($cfg | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
Write-Host "Campo '$Campo' protegido em $Config (o texto aberto foi removido)."
