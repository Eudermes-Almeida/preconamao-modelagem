# Agente Simplifica Compras — versão 2.5 (16/10/2026)

## O que mudou
- **Versão informada ao servidor:** o agente passa a informar a própria versão em cada envio. O
  painel da Simplifica Compras mostra qual versão roda em cada loja e avisa quando há uma mais nova.
- **Atualizar sem refazer as perguntas (Windows):** com o agente já instalado, os instaladores
  (`instalar.cmd`, `instalar-rpinfo.cmd`, `instalar-banco.cmd`) oferecem
  **1 = ATUALIZAR só o programa** — mantém a configuração (chave, senha e demais respostas),
  copia o programa novo para a pasta instalada e reinicia o agente. No Linux isso já existia
  (`sudo bash instalar.sh`, opção 1).
- **Desinstalar apaga tudo (Windows):** `desinstalar*.cmd` pede confirmação e apaga a tarefa e a
  pasta do agente, inclusive o `config.json` com a chave da loja e a senha, como no Linux.
- **Mensagem clara quando a chave é desativada:** se a Simplifica Compras desativar a chave da loja
  no painel, o log mostra "Chave da loja desativada no painel" (antes: erro genérico 401).

## Precisa reconfigurar?
Não. Use a opção **1 = ATUALIZAR**: a configuração atual continua valendo.

## Segurança
Nada muda no que sai da loja nem nas permissões. Continua sem portas abertas, só conexões de saída
(HTTPS 443) e sem atualização automática.

## Compatibilidade
O servidor continua aceitando as versões anteriores; a 2.5 só acrescenta a informação da versão.
