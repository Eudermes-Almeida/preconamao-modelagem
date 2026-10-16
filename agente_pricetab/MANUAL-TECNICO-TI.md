# Simplifica Compras — Manual técnico do agente

**Para a equipe de TI e de segurança da informação do supermercado.** Agente versão 2.5 · outubro de 2026.

O **agente** é o programa que leva os preços da loja para o Simplifica Compras, o aplicativo de
consulta de preços usado pelos clientes dentro do supermercado. Ele roda num computador ou servidor
da rede da loja, **só lê** os preços e **só faz conexões de saída** (HTTPS). Nada é gravado no
sistema da loja e nenhuma porta é aberta.

Este manual reúne tudo o que a TI precisa: como escolher a integração, instalar, operar, atualizar,
revogar e remover. Os detalhes de cada caso estão nos documentos complementares (seção 12).

---

## 1. Como funciona

1. **Fonte de preços do ERP**, na rede da loja: o arquivo `PRICETAB.TXT`, a API do ERP ou uma VIEW
   no banco de dados.
2. **Agente Simplifica Compras** (Windows ou Linux), num computador da rede da loja, com conta sem
   privilégios: lê a fonte **pela rede interna**.
3. **HTTPS, porta 443, só de saída**, para um único endereço.
4. **Servidor Simplifica Compras** (nuvem): confere a chave da loja, aplica as travas de segurança e
   publica os preços.
5. **Aplicativo** no celular do cliente, dentro da loja.

- O agente lê a fonte de preços, monta um pacote (só código, descrição, preço, oferta vigente,
  unidade e seção) e envia por HTTPS para **um único endereço**.
- O servidor confere a chave da loja, aplica as **travas de segurança** e publica os preços no
  aplicativo, sempre separados por loja.
- O servidor **nunca** acessa a loja: as respostas ao agente são só sinais fixos ("envie de novo",
  "faça uma leitura completa"). O agente não executa nada que venha de fora.

## 2. Escolha da integração

As três formas leem a mesma informação; a TI escolhe a que segue a política da empresa. Lojas
diferentes da mesma rede podem usar formas diferentes.

| Integração | De onde lê | O que a TI prepara | Quando usar |
|---|---|---|---|
| **1. Arquivo PRICETAB** | o `PRICETAB.TXT` que o ERP já gera para os terminais de consulta (padrão Gertec) | nada além do arquivo; o agente precisa conseguir **ler** a pasta | implantação mais rápida |
| **2. API do ERP** (RPInfo) | a API REST do ERP, **dentro da rede da loja** | um usuário da API **só de leitura** | o ERP tem API homologada |
| **3. VIEW no banco** | a VIEW `vw_simplifica_precos` no banco do ERP, por **ODBC** | a VIEW e um usuário com **SELECT só nela** | o DBA prefere controle total do que é lido |
| **4. Proposta da TI** | SFTP, exportação agendada, fila, webhook, API em nuvem do ERP... | a combinar | a empresa já tem um padrão: a Simplifica Compras analisa e desenvolve o conector |

**Quanto demora para o preço mudar no aplicativo:** no arquivo PRICETAB, cerca de **5 segundos**
depois que o arquivo é regravado. Na API e na VIEW, até o intervalo da leitura incremental
(**5 minutos** por padrão, configurável) — com a coluna `data_alteracao` a VIEW lê só o que mudou.

## 3. Requisitos

**Computador ou servidor do agente** (um por loja), ligado no horário de funcionamento:

| | Windows | Linux |
|---|---|---|
| Sistema | Windows 10/11 ou Windows Server 2016 ou mais novo | Linux com systemd (testado: Ubuntu Server 22.04) |
| Linguagem | PowerShell 5.1 (já vem no Windows) | PowerShell 7 (o instalador instala no Ubuntu/Debian) |
| VIEW (banco) | driver ODBC oficial do banco, **64 bits** | `unixODBC` + driver ODBC oficial |
| Memória | ~350 MB numa loja de 27 mil códigos de barras | idem |

**Rede:** só **saída HTTPS (porta 443)** para o endereço do servidor Simplifica Compras (um único
domínio, informado na implantação). Nenhuma regra de entrada, VPN ou acesso remoto. Na API e na
VIEW, acesso à API/banco pela rede interna.

**VIEW:** testada em laboratório com **MySQL 8, SQL Server 2022 e PostgreSQL 16**. Outros bancos com
driver ODBC oficial (Firebird, Oracle...) seguem o mesmo contrato e são homologados na implantação.

## 4. Instalação (cerca de 5 minutos)

### 4.1 Windows

A Simplifica Compras entrega uma pasta por integração (pendrive ou pacote `.zip`):

| Integração | Pasta | Instalador |
|---|---|---|
| Arquivo PRICETAB | `agente_pricetab` | `instalar.cmd` |
| API RPInfo | `agente_rpinfo` | `instalar-rpinfo.cmd` |
| VIEW no banco | `agente_banco` | `instalar-banco.cmd` |

1. Copie a pasta para o computador do agente (ex.: `C:\SimplificaCompras\agente_banco`).
2. Botão direito no instalador → **Executar como administrador**.
3. Responda as perguntas (Enter aceita a sugestão). **Chave e senhas não aparecem na tela;** para
   colar, use o **botão direito** do mouse.

O instalador:

- **testa tudo antes de registrar qualquer coisa** (o arquivo, a API ou a VIEW, e o servidor
  Simplifica); se algo falhar, nada é mudado;
- grava a **chave da loja e a senha cifradas pelo Windows** (DPAPI, escopo da máquina): só este
  computador consegue lê-las;
- registra a tarefa agendada (`SimplificaCompras-AgentePricetab`, `-AgenteRPInfo` ou
  `-AgenteBanco`), que inicia junto com o Windows, sem ninguém logado, e é reiniciada pelo Windows
  se parar;
- a tarefa roda na conta **LOCAL SERVICE** do Windows ("SERVIÇO LOCAL" em português), **sem
  privilégios de administrador** (seção 5.2);
- mostra o resultado do primeiro envio ou da primeira leitura completa.

**PRICETAB numa pasta de rede** (`\\servidor\...`): a conta LOCAL SERVICE não lê pastas de rede.
Copie o arquivo para uma pasta local **ou** instale com `instalar.cmd -ContaSystem` (exceção: a
tarefa roda como SYSTEM; libere a pasta de rede para a conta do computador).

### 4.2 Linux

```
cd /root/agente_linux
sudo bash instalar.sh
```

O instalador pergunta a integração (1 arquivo, 2 API, 3 VIEW), cria o usuário de serviço
**`simplifica`** (sem login, sem senha, sem sudo), instala em `/opt/simplifica-compras/agente`,
testa as conexões **como o usuário do serviço** antes de registrar e inicia o serviço
**`simplifica-agente`** do systemd. Detalhes em `LEIA-ME-TI-LINUX.md`.

### 4.3 Homologação

Depois da instalação, a Simplifica Compras e a TI conferem preços **por amostragem** (aplicativo ×
terminal de consulta da loja) antes da liberação ao público.

## 5. Segurança

### 5.1 Rede

- **Nenhuma porta aberta, nenhum serviço em escuta.** Só saída HTTPS (TLS 1.2+, porta 443) para um
  único domínio: a regra de firewall pode ser restrita a ele.
- **Sem VPN e sem acesso remoto.** O servidor não executa nada na loja.
- **Sem atualização automática** e sem download de código: toda versão nova é entregue à TI, que
  revisa e decide quando instalar (seção 7).

### 5.2 Conta sem privilégios

| Sistema | Conta | Permissões |
|---|---|---|
| Windows (instalado como administrador) | **LOCAL SERVICE**, conta de serviço do próprio Windows: sem senha, sem criar usuário, nível **limitado** | grava só na pasta do agente; no PRICETAB, só **lê** a pasta do arquivo |
| Windows (instalado sem administrador) | o próprio usuário, nível limitado | inicia quando esse usuário entra no Windows |
| Linux | usuário **`simplifica`** (sem login, sem senha, sem sudo) | serviço confinado pelo systemd: sem nenhum privilégio (`CapabilityBoundingSet=` vazio, `NoNewPrivileges`), sistema de arquivos somente leitura exceto a própria pasta; `systemd-analyze security` = **2.9 OK** |

A exceção `-ContaSystem` (Windows) existe só para o PRICETAB em pasta de rede (seção 4.1).

### 5.3 Credenciais

- **Chave da loja:** exclusiva de cada loja, fornecida pela Simplifica Compras. O servidor guarda só
  o **resumo SHA-256** dela, nunca a chave.
- **Windows:** a chave e a senha da API/banco ficam no `config.json` **cifradas pelo Windows**
  (DPAPI, escopo da máquina). Copiado para outro computador, o arquivo não serve.
- **Linux:** o `config.json` fica legível **só pelo usuário `simplifica`** (permissão `600`); o agente
  avisa no log se a permissão for afrouxada.
- Chave e senha **nunca aparecem no log** nem na tela.
- **Um agente por loja:** o primeiro computador que se conecta com a chave fica registrado; outro
  computador com a mesma chave é recusado até a liberação (troca de computador, seção 8).

### 5.4 Dados

- **Saem da loja só:** código e código de barras, descrição, preço, oferta **vigente** (de/por e
  validade), unidade (KG/UN), seção/departamento e se o produto está ativo.
- **Nunca saem:** custo, margem, estoque, fornecedor, dados fiscais, ofertas futuras e qualquer dado
  de clientes. Na VIEW, o agente pede só as colunas do contrato; outra coluna é ignorada.
- **Nada é gravado** no ERP, no banco ou na pasta do PRICETAB.
- O aplicativo **não tem cadastro**: nenhum dado pessoal do consumidor é coletado.

### 5.5 Auditoria e travas

- **Modo auditoria:** cópia legível de cada pacote enviado na pasta `auditoria` (API e VIEW), por 30
  dias. A TI vê exatamente o que saiu da loja.
- **Log local** diário (`logs`), por 30 dias; no painel da Simplifica Compras, o histórico de cargas
  de cada loja (tipo, horário, resultado).
- **Travas no servidor** contra falha de exportação ou erro de digitação: fica **retida para
  conferência** a carga que tiraria **mais de 20%** dos produtos do aplicativo, ou que derrubaria o
  preço em **50% ou mais** de **mais de 5%** dos produtos. Só é publicada com autorização expressa.
- **Código auditável:** o agente é um script legível (`agente.ps1`), sem binários.

## 6. Operação

| Onde (Windows: pasta do agente; Linux: `/opt/simplifica-compras/agente`) | O quê |
|---|---|
| `logs\agente-AAAA-MM-DD.log` | o que o agente fez: leituras, envios, falhas (30 dias) |
| `auditoria\` | cópia de cada pacote enviado (API e VIEW) |
| `fila\` | pacotes aguardando envio |
| `estado.json` | controle interno (última leitura e o que já foi enviado) |

**Frequências:**

| | Arquivo PRICETAB | API e VIEW |
|---|---|---|
| Sinal de vida | a cada 5 min | a cada 1 min |
| Leitura | quando o arquivo muda (envia o arquivo inteiro, só se mudou) | incremental a cada 5 min (configurável) + completa ao iniciar e uma vez por dia, no horário combinado |

**Internet ou servidor fora do ar:** os pacotes ficam na `fila` e são enviados na ordem quando a
conexão volta; as tentativas esperam 10 s, 30 s, 1, 2 e 5 min (com variação aleatória, para as lojas
não tentarem juntas). Sem sinal de vida pelo prazo combinado com a loja, o aplicativo deixa de
mostrar os preços e pede ao cliente que consulte o terminal: um preço desatualizado nunca é exibido.

**Testar a qualquer momento, sem enviar preços:**

```
Windows:  powershell -ExecutionPolicy Bypass -File agente.ps1 -TestarConexao
Linux:    sudo runuser -u simplifica -- env HOME=$PWD pwsh -NoProfile -File agente.ps1 -TestarConexao
```

**Problemas comuns:**

| Mensagem | Causa / solução |
|---|---|
| "HTTP 401: Chave da loja ausente ou inválida" | chave digitada errada ou trocada: reconfigure com a chave atual |
| "HTTP 401: Chave da loja desativada no painel" | a Simplifica Compras desativou a chave (seção 8) |
| "Outro agente já está registrado para esta loja" | o agente está em outro computador: peça a liberação (seção 8) |
| "Arquivo não encontrado" (PRICETAB) | pasta ou nome do arquivo; o agente espera o arquivo aparecer |
| "Access denied" / "password authentication failed" | usuário ou senha do banco/API, ou falta o `GRANT SELECT` na VIEW |
| "Data source name not found" | driver ODBC de 64 bits não instalado |
| "O nome remoto não pôde ser resolvido" / "Connection refused" | DNS ou regra de saída HTTPS 443; os preços ficam na fila |

## 7. Versão nova

Não há atualização automática. A Simplifica Compras entrega cada versão num pacote
`agente-simplifica-<versão>.zip`, com:

- `NOVIDADES-<versão>.md`: o que mudou, se precisa reconfigurar, o que muda na segurança;
- `SHA256.txt`: o resumo de cada arquivo;
- e o **SHA-256 do próprio zip**, enviado **por outro canal** (ex.: no corpo da mensagem).

1. Confira o pacote: `Get-FileHash agente-simplifica-<versão>.zip` (Windows) ou
   `sha256sum agente-simplifica-<versão>.zip` (Linux) tem de dar o SHA-256 informado. No Linux,
   depois de descompactar, `sha256sum -c SHA256.txt` confere cada arquivo.
2. Revise o código, se for política da empresa (o `agente.ps1` é texto).
3. Rode o instalador da versão nova como administrador e escolha **1 = ATUALIZAR só o programa**: o
   programa novo vai para a pasta instalada, a configuração (chave, senha, respostas) é mantida e o
   agente reinicia. No fim aparece "Agente <versão> ... iniciado".
4. A Simplifica Compras confere no painel que a loja passou para a versão nova; lojas com versão
   antiga aparecem destacadas para ela.

## 8. Revogar o acesso e trocar de computador

- **Revogar na hora:** a Simplifica Compras **desativa a chave da loja no painel**. A partir daí o
  servidor recusa tudo o que o agente enviar ("Chave da loja desativada no painel"). A loja continua
  no aplicativo com os últimos preços recebidos, até a proteção por falta de sinal agir.
- **Voltar, ou chave vazada:** a Simplifica Compras gera uma **chave nova** no painel e a entrega à
  TI. A antiga deixa de valer na hora. A TI roda o instalador, escolhe **2 = RECONFIGURAR** e cola a
  chave nova.
- **A TI também pode** remover o usuário da API/banco no ERP ou desinstalar o agente (seção 9).
- **Trocar o computador do agente:** a Simplifica Compras libera o registro no painel; instale no
  computador novo com a mesma chave e desinstale do antigo.

## 9. Remoção

| Sistema | Como | O que é apagado |
|---|---|---|
| Windows | botão direito em `desinstalar.cmd` (ou `desinstalar-rpinfo.cmd`, `desinstalar-banco.cmd`) → Executar como administrador → `s` | a tarefa e a **pasta inteira** do agente, inclusive o `config.json` com a chave e a senha, a fila, a auditoria e os logs |
| Linux | `sudo bash /opt/simplifica-compras/agente/desinstalar.sh` → `s` | o serviço, a **pasta inteira** e o usuário `simplifica` |

Os drivers ODBC e o PowerShell 7 ficam (podem servir a outros programas). Depois, remova também o
usuário da API/banco do Simplifica no ERP.

## 10. Divisão de responsabilidades

| Equipe de TI do supermercado | Simplifica Compras |
|---|---|
| Disponibilizar o computador ou servidor do agente | Fornecer, instalar junto e documentar o agente |
| Conceder o acesso só de leitura (arquivo, usuário da API ou `GRANT SELECT` na VIEW) | Monitorar as cargas e as travas de segurança |
| Liberar a saída HTTPS 443 para o domínio da plataforma | Prestar suporte na implantação e na operação |
| Aprovar a instalação e cada versão nova do agente | Entregar cada versão com novidades e SHA-256 |
| | Desativar ou trocar a chave da loja quando necessário |
| | Desenvolver conectores sob demanda (integração 4) |

## 11. Perguntas frequentes

**O agente grava algo no ERP?** Não. Todas as operações são de leitura.

**O agente precisa de administrador?** Só para instalar. No Windows ele roda na conta LOCAL SERVICE,
sem privilégios; no Linux, num usuário próprio confinado pelo systemd.

**Onde fica a senha do banco/API?** No `config.json` do computador do agente: cifrada pelo Windows
ou, no Linux, legível só pelo usuário do serviço. Nunca é enviada ao servidor.

**E se a internet cair?** Os pacotes ficam na fila e são enviados quando a conexão volta.

**Como revogar o acesso?** A chave da loja é desativada no painel de imediato (seção 8); a TI também
pode remover a credencial no ERP ou desinstalar o agente.

**Como o agente é atualizado?** Não há atualização automática. Cada versão é entregue à TI, que
confere o SHA-256, revisa e decide quando instalar (seção 7).

**Qual o consumo de rede?** Trafegam só os itens alterados, em JSON compactado (gzip); a leitura
completa diária é a única transferência integral.

**Há coleta de dados do consumidor?** Não. O aplicativo funciona sem cadastro e não pede nome,
e-mail, telefone ou senha.

## 12. Documentos complementares

| Documento | Conteúdo |
|---|---|
| `LEIA-ME-TI.md` | agente do arquivo PRICETAB (Windows), passo a passo |
| `LEIA-ME-TI-BANCO.md` | integração via VIEW (Windows): preparo, instalação e operação |
| `CONTRATO_VIEW.md` | colunas da VIEW `vw_simplifica_precos`, com exemplo |
| `LEIA-ME-TI-LINUX.md` | agente no Linux (as três integrações) |
| `NOVIDADES-<versão>.md` | o que mudou em cada versão |

*Frequências, horários, limites das travas e escopo dos dados são configuráveis conforme a política
de segurança de cada empresa. Em caso de divergência de preço, prevalece o preço cobrado no caixa.*
