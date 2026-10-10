#!/usr/bin/env bash
# Remove o agente Simplifica Compras deste servidor Linux:   sudo bash desinstalar.sh
# Para e remove o serviço "simplifica-agente", APAGA a pasta /opt/simplifica-compras/agente (inclusive
# o config.json com a chave da loja e a senha) e remove o usuário de serviço "simplifica".
# Não mexe no sistema da loja nem no PowerShell 7 / drivers ODBC (podem ser usados por outros programas).

set -uo pipefail
DESTINO=/opt/simplifica-compras/agente
SERVICO=simplifica-agente
USUARIO=simplifica

if [ "$(id -u)" -ne 0 ]; then echo 'Rode como administrador:  sudo bash desinstalar.sh'; exit 1; fi
echo 'Isto remove o agente Simplifica Compras deste servidor (serviço, pasta com a configuração e usuário).'
read -r -p 'Confirma? (s/n) [n]: ' r || true
[ "${r:-n}" = s ] || { echo 'Nada foi removido.'; exit 0; }

systemctl disable --now "$SERVICO" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/$SERVICO.service"
systemctl daemon-reload
rm -rf "$DESTINO"
rmdir /opt/simplifica-compras 2>/dev/null || true
id "$USUARIO" >/dev/null 2>&1 && userdel "$USUARIO" 2>/dev/null
echo 'Agente removido (a chave da loja e a senha foram apagadas deste servidor).'
echo 'Para instalar em outro computador, peça à Simplifica Compras a liberação do agente da loja.'
