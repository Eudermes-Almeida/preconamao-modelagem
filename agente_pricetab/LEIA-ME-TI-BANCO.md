# Simplifica Compras — Agente do conector de banco de dados

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
   SYSTEM, e é reiniciada pelo Windows se parar) e mostra a primeira leitura completa.

## 4. Segurança

- **Somente leitura e só a VIEW:** o agente pede só as colunas do contrato (tabela acima) que a
  VIEW tiver; qualquer outra coluna da VIEW é ignorada e nunca sai da loja. Nada é gravado no ERP.
- **Sem portas abertas:** o agente não escuta conexões e não aceita comandos de fora. As respostas
  do servidor são só sinais fixos ("envie de novo", "faça uma leitura completa").
- **Sem atualização automática:** toda versão nova é entregue à TI e instalada por ela.
- **Credenciais cifradas:** a chave da loja e a senha do banco ficam no `config.json` cifradas pelo
  Windows (DPAPI, escopo da máquina). Só este computador consegue lê-las, e elas nunca aparecem no
  log.
- **Auditoria:** cópia legível de cada pacote enviado na pasta `auditoria` (guardada 30 dias).
- **Travas no servidor:** pacote que tiraria mais de 20% dos produtos ou derrubaria o preço de
  muitos produtos de uma vez fica retido para conferência.
- **Um agente por loja:** outro computador com a mesma chave é recusado até a liberação.

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

## 6. Remoção

Execute **`desinstalar-banco.cmd`**: ele para o agente e apaga a tarefa. A pasta (com o
`config.json`, os logs e a auditoria) fica; apague-a à mão se quiser. Depois, remova também o
usuário de banco `simplifica_leitura`.
