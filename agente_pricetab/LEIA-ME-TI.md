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
- Guarda a chave da loja **cifrada pelo Windows** (DPAPI, escopo da máquina) no `config.json`: só
  este computador consegue lê-la, e ela nunca aparece no log.

## O que ele NÃO faz
- Não altera, move nem apaga nenhum arquivo da loja.
- Não acessa o sistema de automação comercial, o banco de dados ou a rede interna.
- Não abre nenhuma porta de entrada: ninguém de fora acessa esta máquina por meio dele.
- Não se atualiza sozinho. Versões novas são instaladas pelo TI, quando quiser.

## Instalação (cerca de 5 minutos)
1. Copie a pasta `agente_pricetab` para a máquina onde o PRICETAB.TXT é gerado.
2. Clique com o botão direito em **instalar.cmd** > **Executar como administrador**.
   (Como administrador, o agente inicia junto com o Windows, sem ninguém logado, na conta
   **LOCAL SERVICE** do Windows: sem privilégios de administrador, sem senha e sem criar usuário.
   Ela só ganha permissão de gravar na pasta do agente e de ler a pasta do PRICETAB. Sem
   administrador, ele inicia quando o usuário atual entra no Windows.)
   **PRICETAB numa pasta de rede** (`\\servidor\...`): a LOCAL SERVICE não lê pasta de rede. Copie
   o arquivo para uma pasta local ou instale com `instalar.cmd -ContaSystem` (a tarefa roda como
   SYSTEM; libere a pasta de rede para a conta do computador).
3. Informe a **chave da loja** (fornecida pela Simplifica Compras) e a **pasta do PRICETAB**.
4. O instalador testa a conexão, registra a tarefa agendada **SimplificaCompras-AgentePricetab**
   e mostra o resultado do primeiro envio.

Depois de formatar a máquina, basta repetir os passos acima.

## Versão nova
Não há atualização automática: cada versão nova é entregue pela Simplifica Compras num pacote
`agente-simplifica-<versão>.zip`, com `NOVIDADES-<versão>.md` (o que mudou e se precisa
reconfigurar) e `SHA256.txt` (resumo de cada arquivo). A TI revisa e instala quando decidir.

1. Confira o pacote: `Get-FileHash agente-simplifica-<versão>.zip` tem de dar o mesmo SHA-256
   informado pela Simplifica Compras por outro canal (ex.: no corpo do e-mail).
2. Descompacte e, na pasta do agente da loja, clique com o botão direito em **`instalar.cmd`** →
   "Executar como administrador".
3. Escolha `1` (**ATUALIZAR só o programa**): o instalador copia o programa novo para a pasta
   instalada, mantém a configuração (chave, senha e demais respostas) e reinicia o agente. No fim
   aparece "Agente <versão> ... iniciado" e "Atualização concluída".
4. A Simplifica Compras confere no painel que a loja passou para a versão nova.

## Remoção
Clique com o botão direito em **desinstalar.cmd** → "Executar como administrador" e confirme com
`s`: a tarefa agendada é parada e apagada, e a pasta do agente também é apagada, inclusive o
`config.json` com a chave da loja e os logs.

## Revogar o acesso
A Simplifica Compras desativa a chave da loja no painel e, a partir daí, o servidor recusa tudo o
que o agente enviar (o log mostra "Chave da loja desativada no painel"). Para voltar, ou se a chave
vazar, uma chave nova é gerada no painel e entregue à TI, que reconfigura o agente; a antiga deixa
de valer.

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
| `proteger.ps1` | Cifra a chave da loja pelo Windows (usado pelo instalador) |
| `config.json` | Criado na instalação: endereço da API, chave da loja (cifrada), pasta do PRICETAB |
| `estado.json` | Controle interno (hash do último arquivo enviado) |
| `logs\agente-AAAA-MM-DD.log` | Registro de envios e falhas |
