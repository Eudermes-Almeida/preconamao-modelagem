#!/usr/bin/env bash
# Instala o agente Simplifica Compras num servidor LINUX da loja (Ubuntu, Debian, Rocky/Alma...).
# Uso (na pasta onde estão agente.ps1 e este arquivo):   sudo bash instalar.sh
#
#   1. Confere o PowerShell 7 (no Ubuntu/Debian oferece instalar do repositório oficial da Microsoft).
#   2. Pergunta o MODO: arquivo (PRICETAB.TXT), rpinfo (API da RPInfo) ou banco (VIEW por ODBC),
#      e as informações de cada modo. Chave e senhas são digitadas sem aparecer na tela.
#   3. Cria o usuário de serviço "simplifica" (sem login, sem senha, sem sudo) e instala em
#      /opt/simplifica-compras/agente; o config.json fica legível SÓ por esse usuário (chmod 600).
#   4. Testa as conexões (como o usuário do serviço) antes de registrar qualquer coisa.
#   5. Registra o serviço systemd "simplifica-agente": inicia com o servidor e reinicia sozinho se
#      cair. Mostra o resultado da primeira leitura.
# Já instalado: oferece só ATUALIZAR o programa (mantém a configuração) ou reconfigurar.
# O agente só faz conexões de SAÍDA: nenhuma porta é aberta neste servidor.

set -uo pipefail

ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINO=/opt/simplifica-compras/agente
SERVICO=simplifica-agente
USUARIO=simplifica
URL_PADRAO=https://preconamao-backend.onrender.com

verde()    { printf '\033[32m%s\033[0m\n' "$*"; }
amarelo()  { printf '\033[33m%s\033[0m\n' "$*"; }
vermelho() { printf '\033[31m%s\033[0m\n' "$*"; }
ciano()    { printf '\033[36m%s\033[0m\n' "$*"; }

# Pergunta com sugestão (Enter aceita a sugestão).
perguntar() {
    local resposta
    read -r -p "$1 [$2]: " resposta || true
    resposta="$(printf '%s' "$resposta" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    printf '%s' "${resposta:-$2}"
}

# Segredo: não aparece na tela. Com valor anterior, Enter mantém o anterior.
perguntar_segredo() {
    local texto="$1" anterior="${2:-}" valor tentativa sufixo=''
    [ -n "$anterior" ] && sufixo=' (Enter mantém o atual)'
    for tentativa in 1 2 3; do
        read -r -s -p "$texto$sufixo: " valor || true
        echo >&2
        valor="$(printf '%s' "$valor" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        if [ -z "$valor" ]; then
            if [ -n "$anterior" ]; then printf '%s' "$anterior"; return 0; fi
            amarelo "  $texto é obrigatório." >&2; continue
        fi
        if [ "${#valor}" -lt 4 ] || printf '%s' "$valor" | grep -q '[[:cntrl:]]'; then
            amarelo '  Valor inválido (mínimo 4 caracteres). Tente de novo.' >&2; continue
        fi
        printf '%s' "$valor"; return 0
    done
    vermelho "Não foi possível ler: $texto. Rode o instalador de novo." >&2
    exit 1
}

# Lê um parâmetro (Driver=, Server=...) de uma conexão ODBC, para sugerir de novo.
parte() { printf '%s' "$1" | tr ';' '\n' | sed -n "s/^$2=[{]\{0,1\}\([^}]*\)[}]\{0,1\}$/\1/Ip" | head -n 1; }

# Espera o resultado da primeira leitura no log do agente (até 3 min).
esperar_resultado() {
    local inicio="$1" fim=$((SECONDS + 180)) linha=''
    echo 'Aguardando a primeira leitura e envio (até 3 min)...'
    while [ $SECONDS -lt $fim ]; do
        sleep 3
        linha="$(cat "$DESTINO"/logs/agente-*.log 2>/dev/null | awk -v i="$inicio" '$0 >= i' |
                 grep -E 'enviado|Foto igual|Falha|FALHOU' | tail -n 1)"
        [ -n "$linha" ] && break
    done
    echo
    if printf '%s' "$linha" | grep -qE 'enviado|Foto igual'; then
        verde "  $linha"
        echo; verde 'Pronto. O agente segue rodando como serviço (inicia junto com o servidor).'
    elif [ -n "$linha" ]; then
        amarelo "  $linha"; amarelo 'Instalado, mas veja o aviso acima.'
    else
        amarelo 'Instalado. A primeira leitura ainda não terminou em 3 min; acompanhe o log abaixo.'
    fi
    echo
    echo "  Situação do serviço:  systemctl status $SERVICO"
    echo "  Acompanhar ao vivo:   journalctl -u $SERVICO -f"
    echo "  Logs do agente:       $DESTINO/logs"
    echo "  Desinstalar:          sudo bash $DESTINO/desinstalar.sh"
}

# Serviço systemd (regravado também ao atualizar: versões novas podem trazer ajustes).
# Proteções: roda como "simplifica" sem nenhum privilégio de administrador, só escreve na própria
# pasta, não vê /home nem dispositivos, só usa rede IP (+ socket local p/ banco na mesma máquina).
escrever_servico() {
    cat > "/etc/systemd/system/$SERVICO.service" <<EOF
[Unit]
Description=Simplifica Compras - agente de preços (modo $1; só conexões de saída)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USUARIO
Group=$USUARIO
WorkingDirectory=$DESTINO
Environment=HOME=$DESTINO
Environment=POWERSHELL_TELEMETRY_OPTOUT=1
Environment=POWERSHELL_UPDATECHECK=Off
ExecStart=$PWSH -NoProfile -NonInteractive -File $DESTINO/agente.ps1
Restart=always
RestartSec=30
UMask=0077
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
ProtectSystem=strict
ReadWritePaths=$DESTINO
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
RestrictSUIDSGID=yes
RestrictRealtime=yes
RestrictNamespaces=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

echo
ciano '=== Simplifica Compras - instalação do agente (Linux) ==='
echo 'O agente leva os preços da loja para o Simplifica Compras. Só faz conexões de SAÍDA:'
echo 'nenhuma porta é aberta neste servidor e nada é gravado no sistema da loja.'
echo

# ---------------------------------------------------------------- pré-requisitos
if [ "$(id -u)" -ne 0 ]; then vermelho 'Rode como administrador:  sudo bash instalar.sh'; exit 1; fi
if [ ! -d /run/systemd/system ]; then vermelho 'Este servidor não usa systemd; o agente precisa dele para rodar como serviço.'; exit 1; fi
for f in agente.ps1 desinstalar.sh; do
    [ -f "$ORIGEM/$f" ] || { vermelho "Arquivo $f não encontrado em $ORIGEM."; exit 1; }
done

PWSH="$(command -v pwsh || true)"
if [ -z "$PWSH" ]; then
    . /etc/os-release 2>/dev/null || true
    amarelo 'O PowerShell 7 (Microsoft, gratuito) não está instalado. O agente precisa dele.'
    if [ "${ID:-}" = ubuntu ] || [ "${ID:-}" = debian ]; then
        if [ "$(perguntar 'Instalar agora, do repositório oficial da Microsoft? (s/n)' s)" != s ]; then
            vermelho 'Instalação cancelada.'; exit 1
        fi
        apt-get update -qq && apt-get install -y -qq wget ca-certificates >/dev/null \
            && wget -q "https://packages.microsoft.com/config/$ID/$VERSION_ID/packages-microsoft-prod.deb" -O /tmp/ms-prod.deb \
            && dpkg -i /tmp/ms-prod.deb >/dev/null && rm -f /tmp/ms-prod.deb \
            && apt-get update -qq && apt-get install -y -qq powershell >/dev/null
        PWSH="$(command -v pwsh || true)"
        [ -n "$PWSH" ] || { vermelho 'Não foi possível instalar o PowerShell 7. Veja: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux'; exit 1; }
        verde "PowerShell 7 instalado: $("$PWSH" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
    else
        vermelho 'Instale o PowerShell 7 conforme a distribuição e rode de novo:'
        vermelho '  https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux'
        exit 1
    fi
fi

# ---------------------------------------------------------------- instalação existente
declare -A ANT=()
if [ -f "$DESTINO/config.json" ]; then
    while IFS=$'\t' read -r k v; do [ -n "$k" ] && ANT["$k"]="$v"; done < <(
        ARQ="$DESTINO/config.json" "$PWSH" -NoProfile -NonInteractive -Command '
            function F($o, $p) { foreach ($x in $o.PSObject.Properties) {
                $n = if ($p) { "$p.$($x.Name)" } else { $x.Name }
                if ($x.Value -is [pscustomobject]) { F $x.Value $n } else { "$n`t$($x.Value)" } } }
            F (Get-Content $env:ARQ -Raw | ConvertFrom-Json) ""' 2>/dev/null)
    ciano "Já existe uma instalação em $DESTINO (modo ${ANT[modo]:-arquivo})."
    echo '  1 = ATUALIZAR só o programa (mantém a configuração; para a TI instalar uma versão nova)'
    echo '  2 = RECONFIGURAR (refaz as perguntas; Enter mantém cada valor atual)'
    if [ "$(perguntar 'Opção' 1)" = 1 ]; then
        systemctl stop "$SERVICO" 2>/dev/null || true
        install -o "$USUARIO" -g "$USUARIO" -m 640 "$ORIGEM/agente.ps1" "$DESTINO/agente.ps1"
        install -o root -g root -m 755 "$ORIGEM/desinstalar.sh" "$DESTINO/desinstalar.sh"
        escrever_servico "${ANT[modo]:-arquivo}"
        INICIO="$(date '+%Y-%m-%d %H:%M:%S')"
        systemctl enable "$SERVICO" >/dev/null 2>&1
        systemctl start "$SERVICO"
        verde "Programa atualizado ($(grep -m1 -o "versaoAgente = '[^']*'" "$DESTINO/agente.ps1" | cut -d"'" -f2)); serviço reiniciado."
        esperar_resultado "$INICIO"
        exit 0
    fi
fi

# ---------------------------------------------------------------- perguntas
echo
echo 'De onde vêm os preços da loja?'
echo '  1 = arquivo PRICETAB.TXT (gerado pelo sistema da loja para os terminais de consulta)'
echo '  2 = API da RPInfo (RP Services) na rede da loja'
echo '  3 = banco de dados do ERP (VIEW vw_simplifica_precos, por ODBC)'
case "${ANT[modo]:-}" in rpinfo) S=2 ;; banco) S=3 ;; arquivo) S=1 ;; *) S=3 ;; esac
case "$(perguntar 'Opção' "$S")" in 1) MODO=arquivo ;; 2) MODO=rpinfo ;; 3) MODO=banco ;; *) vermelho 'Opção inválida.'; exit 1 ;; esac

export SC_MODO="$MODO"
export SC_URL="$(perguntar 'Endereço do servidor Simplifica Compras' "${ANT[url]:-$URL_PADRAO}")"

case "$MODO" in
arquivo)
    export SC_PASTA="$(perguntar 'Pasta onde o sistema da loja grava o arquivo' "${ANT[pasta]:-/srv/pricetab}")"
    export SC_ARQUIVO="$(perguntar 'Nome do arquivo' "${ANT[arquivo]:-PRICETAB.TXT}")"
    ;;
rpinfo)
    export SC_API_URL="$(perguntar 'Endereço da API da RPInfo na rede da loja' "${ANT[rpinfo.url]:-http://127.0.0.1:9000}")"
    export SC_API_USUARIO="$(perguntar 'Usuário da API' "${ANT[rpinfo.usuario]:-simplifica}")"
    export SC_API_CNPJ="$(perguntar 'CNPJ da loja (só números)' "${ANT[rpinfo.cnpj]:-}")"
    export SC_INTERVALO="$(perguntar 'Consultar a API a cada quantos minutos' "${ANT[rpinfo.intervaloMinutos]:-5}")"
    export SC_HORARIO="$(perguntar 'Horário da coleta completa diária (HH:mm)' "${ANT[rpinfo.horarioCompleta]:-12:00}")"
    ;;
banco)
    mapfile -t DRIVERS < <(odbcinst -q -d 2>/dev/null | tr -d '[]' | sort -u)
    if [ "${#DRIVERS[@]}" -eq 0 ]; then
        vermelho 'Nenhum driver ODBC encontrado (ou o unixODBC não está instalado).'
        vermelho 'Instale o unixODBC e o driver ODBC OFICIAL do banco do ERP e rode de novo. Exemplos (Ubuntu/Debian):'
        vermelho '  PostgreSQL: apt install unixodbc odbc-postgresql'
        vermelho '  SQL Server: pacote msodbcsql18 (repositório da Microsoft)'
        vermelho '  MySQL:      MySQL Connector/ODBC (dev.mysql.com)'
        exit 1
    fi
    echo 'Drivers ODBC instalados neste servidor:'
    for i in "${!DRIVERS[@]}"; do echo "  $((i + 1)). ${DRIVERS[$i]}"; done
    ANTCON="${ANT[banco.conexao]:-}"
    DRV_ANT="$(parte "$ANTCON" Driver)"; S=1
    for i in "${!DRIVERS[@]}"; do [ "${DRIVERS[$i]}" = "$DRV_ANT" ] && S=$((i + 1)); done
    N="$(perguntar 'Número do driver do banco do ERP' "$S")"
    [[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le "${#DRIVERS[@]}" ] || { vermelho "Número inválido: $N"; exit 1; }
    DRIVER="${DRIVERS[$((N - 1))]}"
    case "$DRIVER" in *MySQL*) PP=3306 ;; *"SQL Server"*) PP=1433 ;; *PostgreSQL*) PP=5432 ;; *) PP='' ;; esac
    SRV_ANT="$(parte "$ANTCON" Server)"; PORTA_ANT="$(parte "$ANTCON" Port)"
    if [[ "$SRV_ANT" == *,* ]]; then PORTA_ANT="${SRV_ANT##*,}"; SRV_ANT="${SRV_ANT%,*}"; fi
    SERVIDOR="$(perguntar 'Endereço do servidor do banco do ERP (na rede da loja)' "${SRV_ANT:-127.0.0.1}")"
    PORTA="$(perguntar 'Porta do banco' "${PORTA_ANT:-$PP}")"
    BANCO="$(perguntar 'Nome do banco (database) onde está a VIEW' "$(parte "$ANTCON" Database || true)")"
    case "$DRIVER" in
        *"SQL Server"*)
            CERT=s; [ -n "$ANTCON" ] && [ "$(parte "$ANTCON" TrustServerCertificate)" != yes ] && CERT=n
            CERT="$(perguntar 'O SQL Server usa certificado próprio/autoassinado (o comum em rede interna)? (s/n)' "$CERT")"
            SC_CONEXAO="Driver={$DRIVER};Server=$SERVIDOR,$PORTA;Database=$BANCO;"
            [ "$CERT" = s ] && SC_CONEXAO+='TrustServerCertificate=yes;' ;;
        *MySQL*) SC_CONEXAO="Driver={$DRIVER};Server=$SERVIDOR;Port=$PORTA;Database=$BANCO;CHARSET=utf8mb4;" ;;
        *)       SC_CONEXAO="Driver={$DRIVER};Server=$SERVIDOR;Port=$PORTA;Database=$BANCO;" ;;
    esac
    export SC_CONEXAO
    export SC_BANCO_USUARIO="$(perguntar 'Usuário do banco (só SELECT na VIEW)' "${ANT[banco.usuario]:-simplifica_leitura}")"
    export SC_VIEW="$(perguntar 'Nome da VIEW' "${ANT[banco.view]:-vw_simplifica_precos}")"
    export SC_INTERVALO="$(perguntar 'Ler a VIEW a cada quantos minutos' "${ANT[banco.intervaloMinutos]:-5}")"
    export SC_HORARIO="$(perguntar 'Horário da leitura completa diária (HH:mm)' "${ANT[banco.horarioCompleta]:-12:00}")"
    ;;
esac
[[ "${SC_INTERVALO:-5}" =~ ^[0-9]+([.,][0-9]+)?$ ]] || { vermelho "Intervalo inválido: $SC_INTERVALO"; exit 1; }
[[ "${SC_HORARIO:-12:00}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || { vermelho "Horário inválido (use HH:mm, ex.: 12:00): $SC_HORARIO"; exit 1; }

SC_CHAVE="$(perguntar_segredo 'Chave da loja (fornecida pela Simplifica Compras)' "${ANT[chave]:-}")" || exit 1
export SC_CHAVE
case "$MODO" in
    rpinfo) SC_SENHA="$(perguntar_segredo 'Senha da API da RPInfo' "${ANT[rpinfo.senha]:-}")" || exit 1 ;;
    banco)  SC_SENHA="$(perguntar_segredo 'Senha do usuário do banco' "${ANT[banco.senha]:-}")" || exit 1 ;;
esac
export SC_SENHA="${SC_SENHA:-}"

# ---------------------------------------------------------------- usuário, pasta e config.json
if ! id "$USUARIO" >/dev/null 2>&1; then
    useradd --system --home-dir "$DESTINO" --no-create-home --shell /usr/sbin/nologin \
        --comment 'Simplifica Compras - agente' "$USUARIO"
fi
install -d -o "$USUARIO" -g "$USUARIO" -m 750 "$DESTINO"
install -o "$USUARIO" -g "$USUARIO" -m 640 "$ORIGEM/agente.ps1" "$DESTINO/agente.ps1"
install -o root -g root -m 755 "$ORIGEM/desinstalar.sh" "$DESTINO/desinstalar.sh"

# A configuração nova é gravada à parte e só substitui a atual se o teste passar: reconfigurar com
# um dado errado não derruba o agente que já está rodando.
export SC_ARQ="$DESTINO/config.novo.json"
( umask 077; "$PWSH" -NoProfile -NonInteractive -Command '
    $c = [ordered]@{ modo = $env:SC_MODO; url = $env:SC_URL.TrimEnd("/"); chave = $env:SC_CHAVE; intervaloSinalMinutos = 1; auditoria = $true }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    switch ($env:SC_MODO) {
        "arquivo" { $c.pasta = $env:SC_PASTA; $c.arquivo = $env:SC_ARQUIVO }
        "rpinfo"  { $c.rpinfo = [ordered]@{ url = $env:SC_API_URL; usuario = $env:SC_API_USUARIO; senha = $env:SC_SENHA; cnpj = $env:SC_API_CNPJ
                        tamanhoPagina = 100; intervaloMinutos = [double]::Parse($env:SC_INTERVALO.Replace(",", "."), $inv); folgaMinutos = 10; horarioCompleta = $env:SC_HORARIO } }
        "banco"   { $c.banco = [ordered]@{ conexao = $env:SC_CONEXAO; usuario = $env:SC_BANCO_USUARIO; senha = $env:SC_SENHA; view = $env:SC_VIEW
                        intervaloMinutos = [double]::Parse($env:SC_INTERVALO.Replace(",", "."), $inv); folgaMinutos = 10; horarioCompleta = $env:SC_HORARIO } }
    }
    [IO.File]::WriteAllText($env:SC_ARQ, ($c | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))' ) \
    || { vermelho 'Falha ao gravar o config.json.'; exit 1; }
unset SC_CHAVE SC_SENHA
chown "$USUARIO:$USUARIO" "$SC_ARQ"; chmod 600 "$SC_ARQ"

if [ "$MODO" = arquivo ] && ! runuser -u "$USUARIO" -- test -r "$SC_PASTA/$SC_ARQUIVO" 2>/dev/null; then
    amarelo "Atenção: o usuário $USUARIO não consegue ler $SC_PASTA/$SC_ARQUIVO (ou ele ainda não existe)."
    amarelo "Se o arquivo já existe, libere a leitura, por exemplo:  setfacl -m u:$USUARIO:rx $SC_PASTA && setfacl -m u:$USUARIO:r $SC_PASTA/$SC_ARQUIVO"
fi

# ---------------------------------------------------------------- teste (como o usuário do serviço)
echo
echo 'Testando as conexões...'
TESTE="$(cd "$DESTINO" && runuser -u "$USUARIO" -- env HOME="$DESTINO" POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
         "$PWSH" -NoProfile -NonInteractive -File "$DESTINO/agente.ps1" -Config "$SC_ARQ" -TestarConexao 2>&1)"
printf '%s\n' "$TESTE" | while IFS= read -r l; do
    [ -z "${l// }" ] && continue
    l="${l:20}"
    if printf '%s' "$l" | grep -q FALHOU; then vermelho "  $l"; else echo "  $l"; fi
done
if printf '%s' "$TESTE" | grep -q FALHOU || ! printf '%s' "$TESTE" | grep -qE 'OK\.$'; then
    unlink "$SC_ARQ"
    echo
    if [ -f "$DESTINO/config.json" ]; then
        vermelho 'O teste falhou (veja acima). NADA foi mudado: o agente segue com a configuração anterior.'
    else
        vermelho 'O teste falhou (veja acima). O serviço NÃO foi registrado.'
    fi
    vermelho 'Confira os dados e rode de novo (sudo bash instalar.sh).'
    exit 1
fi
mv -f "$SC_ARQ" "$DESTINO/config.json"
verde "Configuração gravada em $DESTINO/config.json (legível só pelo usuário $USUARIO)."

# ---------------------------------------------------------------- serviço systemd
escrever_servico "$MODO"
INICIO="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl enable "$SERVICO" >/dev/null 2>&1 && systemctl restart "$SERVICO" \
    || { vermelho "Falha ao iniciar o serviço. Veja: journalctl -u $SERVICO"; exit 1; }
verde "Serviço $SERVICO registrado e iniciado (inicia junto com o servidor; se cair, reinicia em 30 s)."
esperar_resultado "$INICIO"
