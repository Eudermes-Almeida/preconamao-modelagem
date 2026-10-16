# Simplifica Compras — Agente da integração via VIEW (banco de dados)

**Guia para a equipe de TI do supermercado.**

O agente lê os preços do ERP **dentro da rede da loja** e os envia ao Simplifica Compras, o
aplicativo de consulta de preços usado pelos clientes. Ele lê só uma VIEW, com um usuário que só
tem SELECT nela. Nada é gravado no ERP e nenhuma porta é aberta.

---

## 1. Como funciona

```
 Banco do ERP (rede da loja)                Computador do agente               Simplifica Compras
 ┌──────────────────────────┐   ODBC     ┌──────────────────────────┐  HTTPS   ┌──────────────────┐
 │ VIEW vw_simplifica_precos │ ────────▶ │ agente.ps1 (modo banco)  │ ───────▶ │ servidor (nuvem) │
 │ usuário: só SELECT        │  leitura  │ foto local, fila, log    │  saída   │                  │
 └──────────────────────────┘            └──────────────────────────┘  443     └──────────────────┘
```

- **Leitura completa:** ao ligar o agente e uma vez por dia, no horário combinado.
- **Leitura incremental:** a cada 5 minutos (configurável), só das linhas com `data_alteracao`
  recente. Sem essa coluna, o agente lê a VIEW inteira e compara com a última leitura (envia só o
  que mudou). O agente descobre sozinho quais colunas a VIEW tem; não há nada a configurar.
  A leitura incremental segue o **relógio do banco** (a maior `data_alteracao` já lida), então o
  fuso horário do servidor do banco (ex.: UTC) e o do computador do agente podem ser diferentes.
- **Testado em laboratório** com MySQL 8, SQL Server 2022 e PostgreSQL 16 (27 mil códigos de
  barras, acentos, ofertas, produto fora de linha e de volta).
- **Envio:** pacotes JSON compactados, por HTTPS, **só de saída**, para um único endereço.

## 2. O que a TI prepara

**a) A VIEW `vw_simplifica_precos`** no banco do ERP: uma linha por código de barras.

| Coluna | Obrigatória | Conteúdo |
|---|---|---|
| `codigo_barras` | sim | EAN (produto com vários códigos = várias linhas) |
| `descricao` | sim | descrição do produto |
| `preco` | sim | preço de venda normal (o que o caixa cobra) |
| `preco_promocional` | não | preço de oferta (usado só se menor que `preco`) |
| `promocao_ate` | não | último dia da oferta (vencida é ignorada) |
| `unidade` | não | `KG` (balança) ou `UN` |
| `secao` | não | seção/departamento |
| `codigo_interno` | recomendada | código do produto no ERP (agrupa os EANs do produto); sem ela, cada EAN é tratado como um produto |
| `ativo` | não | `N` = fora de linha; sem ela, todos ativos (produto fora de linha = tirar da VIEW) |
| `data_alteracao` | recomendada | última alteração de preço/cadastro (permite a leitura incremental) |

Só as três primeiras são obrigatórias: uma VIEW com `codigo_barras`, `descricao` e `preco` já
funciona. As demais podem ser incluídas a qualquer momento, sem reinstalar o agente.

**Não inclua** custo, margem, estoque, fornecedor, dados fiscais ou de clientes. Exemplo completo
de VIEW em `CONTRATO_VIEW.md`.

**b) Um usuário de banco só com SELECT na VIEW**, de preferência restrito ao IP do computador do
agente. Exemplo (MySQL):

```sql
CREATE USER 'simplifica_leitura'@'<ip do agente>' IDENTIFIED BY '<senha forte>';
GRANT SELECT ON <banco>.vw_simplifica_precos TO 'simplifica_leitura'@'<ip do agente>';
```

**c) Um computador Windows na rede da loja** (Windows 10/11 ou Server 2016+, PowerShell 5.1),
ligado no horário de funcionamento, com:
- o **driver ODBC oficial** do banco do ERP, **64 bits** (MySQL Connector/ODBC, ODBC Driver for
  SQL Server, psqlODBC, Firebird ODBC, Oracle ODBC);
- acesso ao banco pela rede interna;
- **saída HTTPS (porta 443)** para o endereço do servidor Simplifica Compras. Nenhuma regra de
  entrada é necessária.

**Ou um servidor Linux** (com systemd): o mesmo agente roda como serviço, com o instalador
`instalar.sh`. Veja **`LEIA-ME-TI-LINUX.md`**.

## 3. Instalação (cerca de 5 minutos)

1. Copie a pasta `agente_banco` para o computador do agente (ex.: `C:\SimplificaCompras\agente_banco`).
2. Botão direito em **`instalar-banco.cmd`** → **Executar como administrador**.
3. Responda as perguntas:

| Pergunta | Exemplo |
|---|---|
| Número do driver | o número do driver do seu banco, na lista que aparece |
| Servidor, porta e nome do banco | `10.0.0.5`, `3306`, `erp` |
| Servidor Simplifica Compras | informado pela Simplifica Compras |
| Usuário e nome da VIEW | `simplifica_leitura`, `vw_simplifica_precos` |
| Intervalo de leitura e horário da completa | `5` e `12:00` |
| Chave da loja e senha do banco | colar com o **botão direito** do mouse |

4. O instalador **testa a VIEW e o servidor antes de registrar qualquer coisa**. Se tudo der
   certo, ele registra a tarefa `SimplificaCompras-AgenteBanco` (inicia com o Windows, na conta
   **LOCAL SERVICE**, sem privilégios de administrador, e é reiniciada pelo Windows se parar) e
   mostra a primeira leitura completa.

## 4. Segurança

- **Somente leitura e só a VIEW:** o agente pede só as colunas do contrato (tabela acima) que a
  VIEW tiver; qualquer outra coluna da VIEW é ignorada e nunca sai da loja. Nada é gravado no ERP.
- **Sem portas abertas:** o agente não escuta conexões e não aceita comandos de fora. As respostas
  do servidor são só sinais fixos ("envie de novo", "faça uma leitura completa").
- **Sem atualização automática:** toda versão nova é entregue à TI e instalada por ela.
- **Conta sem privilégios:** instalado como administrador, o agente roda na conta **LOCAL SERVICE**
  do próprio Windows ("SERVIÇO LOCAL" em português): sem privilégios de administrador, sem senha e
  sem criar usuário. Ela só tem permissão de gravar na pasta do agente.
- **Credenciais cifradas:** a chave da loja e a senha do banco ficam no `config.json` cifradas pelo
  Windows (DPAPI, escopo da máquina). Só este computador consegue lê-las, e elas nunca aparecem no
  log.
- **Auditoria:** cópia legível de cada pacote enviado na pasta `auditoria` (guardada 30 dias).
- **Travas no servidor:** pacote que tiraria mais de 20% dos produtos ou derrubaria o preço de
  muitos produtos de uma vez fica retido para conferência.
- **Um agente por loja:** outro computador com a mesma chave é recusado até a liberação.
- **Revogar o acesso na hora:** a Simplifica Compras desativa a chave da loja no painel e, a partir
  daí, o servidor recusa tudo o que o agente enviar (o log mostra "Chave da loja desativada no
  painel"). Para voltar, ou se a chave vazar, uma chave nova é gerada no painel e entregue à TI,
  que reconfigura o agente; a antiga deixa de valer.

## 5. Operação

| Onde | O quê |
|---|---|
| `logs\agente-AAAA-MM-DD.log` | o que o agente fez (leituras, envios, falhas) |
| `auditoria\` | cópia de cada pacote enviado |
| `fila\` | pacotes aguardando envio (internet fora: entregues ao voltar) |
| `estado.json` | controle interno (última leitura e foto enviada) |

Teste a qualquer momento, sem enviar nada:

```
powershell -ExecutionPolicy Bypass -File agente.ps1 -TestarConexao
```

**Problemas comuns:**
- **"Access denied for user"**: usuário ou senha do banco, ou falta o GRANT SELECT na VIEW.
- **"Data source name not found"**: o driver ODBC de 64 bits não está instalado.
- **"A VIEW ... não tem a(s) coluna(s) obrigatória(s)"**: a VIEW precisa de `codigo_barras`,
  `descricao` e `preco` com esses nomes (use `AS` na VIEW).
- **"Outro agente já está registrado para esta loja"**: peça à Simplifica Compras a liberação
  (troca de computador).

## 6. Versão nova

Não há atualização automática: cada versão nova é entregue pela Simplifica Compras num pacote
`agente-simplifica-<versão>.zip`, com `NOVIDADES-<versão>.md` (o que mudou e se precisa
reconfigurar) e `SHA256.txt` (resumo de cada arquivo). A TI revisa e instala quando decidir.

1. Confira o pacote: `Get-FileHash agente-simplifica-<versão>.zip` tem de dar o mesmo SHA-256
   informado pela Simplifica Compras por outro canal (ex.: no corpo do e-mail).
2. Descompacte e, na pasta do agente da loja, clique com o botão direito em **`instalar-banco.cmd`** →
   "Executar como administrador".
3. Escolha `1` (**ATUALIZAR só o programa**): o instalador copia o programa novo para a pasta
   instalada, mantém a configuração (chave, senha e demais respostas) e reinicia o agente. No fim
   aparece "Agente <versão> ... iniciado" e "Atualização concluída".
4. A Simplifica Compras confere no painel que a loja passou para a versão nova.

## 7. Remoção

Clique com o botão direito em **`desinstalar-banco.cmd`** → "Executar como administrador" e
confirme com `s`. Ele para o agente, apaga a tarefa e **apaga a pasta do agente**, inclusive o
`config.json` com a chave da loja e a senha do banco, a fila, a auditoria e os logs (como o
`desinstalar.sh` do Linux). Pode ser executado da própria pasta ou de outra cópia (ex.: o pendrive):
ele apaga a pasta onde o agente foi instalado. Depois, remova também o usuário de banco
`simplifica_leitura`.
