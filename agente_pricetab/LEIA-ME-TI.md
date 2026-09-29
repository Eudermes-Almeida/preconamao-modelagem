# Agente Simplifica Compras: informações para o TI da loja

## O que é
Um script PowerShell (`agente.ps1`, texto legível) que mantém os preços do aplicativo Simplifica
Compras iguais aos do busca-preço da loja. Ele observa o arquivo **PRICETAB.TXT** (o mesmo que
alimenta os terminais Gertec) e, quando o arquivo muda, envia uma cópia para o servidor do aplicativo.

## O que ele FAZ
- **Lê** um único arquivo: o PRICETAB.TXT, na pasta configurada.
- Envia o arquivo por **HTTPS** (conexão de saída, porta 443) para
  `https://preconamao-backend.onrender.com`, identificado por uma chave exclusiva da loja.
- A cada 5 minutos envia um "sinal de vida" (uma requisição pequena) para o servidor saber que a
  loja está conectada. Sem esse sinal, o aplicativo deixa de mostrar preços e pede ao cliente que
  consulte o terminal da loja: um preço desatualizado nunca é exibido.
- Grava um log diário em `logs\` (guardado por 30 dias).

## O que ele NÃO faz
- Não altera, move nem apaga nenhum arquivo da loja.
- Não acessa o sistema de automação comercial, o banco de dados ou a rede interna.
- Não abre nenhuma porta de entrada: ninguém de fora acessa esta máquina por meio dele.
- Não se atualiza sozinho. Versões novas são instaladas pelo TI, quando quiser.

## Instalação (cerca de 5 minutos)
1. Copie a pasta `agente_pricetab` para a máquina onde o PRICETAB.TXT é gerado.
2. Clique com o botão direito em **instalar.cmd** > **Executar como administrador**.
   (Como administrador, o agente inicia junto com o Windows, sem ninguém logado. Sem
   administrador, ele inicia quando o usuário atual entra no Windows.)
3. Informe a **chave da loja** (fornecida pela Simplifica Compras) e a **pasta do PRICETAB**.
4. O instalador testa a conexão, registra a tarefa agendada **SimplificaCompras-AgentePricetab**
   e mostra o resultado do primeiro envio.

Depois de formatar a máquina, basta repetir os passos acima.

## Remoção
Duplo clique em **desinstalar.cmd**: a tarefa agendada é parada e apagada. A pasta pode ser apagada
em seguida.

## Requisitos
- Windows 8 / Server 2012 ou mais novo (PowerShell 5.1, já incluído no Windows).
- Acesso à internet por HTTPS (porta 443) para `preconamao-backend.onrender.com`.
- Se a política da empresa bloquear scripts PowerShell, fale conosco: existe a opção de um
  executável (.exe).

## Arquivos
| Arquivo | Para quê |
|---|---|
| `agente.ps1` | O agente (texto; pode ser lido e auditado) |
| `instalar.cmd` / `instalar.ps1` | Instalação |
| `desinstalar.cmd` / `desinstalar.ps1` | Remoção |
| `config.json` | Criado na instalação: endereço da API, chave da loja, pasta do PRICETAB |
| `estado.json` | Controle interno (hash do último arquivo enviado) |
| `logs\agente-AAAA-MM-DD.log` | Registro de envios e falhas |
