# Simplifica Compras — Agente para servidor Linux

**Guia para a equipe de TI do supermercado.**

O agente leva os preços da loja para o Simplifica Compras, o aplicativo de consulta de preços usado
pelos clientes. Ele roda como **serviço do systemd** num servidor Linux da rede da loja, só lê os
preços e só faz conexões **de saída**. Nada é gravado no sistema da loja e nenhuma porta é aberta.

É o mesmo agente da versão Windows (PowerShell), com os três modos:

| Modo | De onde vêm os preços |
|---|---|
| **arquivo** | o `PRICETAB.TXT` gerado pelo sistema da loja para os terminais de consulta |
| **rpinfo** | a API da RPInfo (RP Services) na rede da loja |
| **banco** | a VIEW `vw_simplifica_precos` no banco do ERP, por ODBC (ver `LEIA-ME-TI-BANCO.md` e `CONTRATO_VIEW.md`) |

---

## 1. Requisitos do servidor

- **Linux com systemd** em que o PowerShell 7 rode (Ubuntu, Debian, Rocky/Alma/RHEL...).
  **Testado em laboratório: Ubuntu Server 22.04** (horário de Brasília, pt_BR.UTF-8). As outras
  distribuições ainda não foram testadas.
- **PowerShell 7** (Microsoft, gratuito). No Ubuntu e no Debian o instalador oferece instalar do
  repositório oficial da Microsoft; nas outras distribuições, instale antes conforme
  <https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux>.
- **Modo banco:** `unixODBC` + o **driver ODBC oficial** do banco do ERP. Testados:

  | Banco | Driver (nome que aparece no instalador) | Como instalar (Ubuntu/Debian) |
  |---|---|---|
  | PostgreSQL | `PostgreSQL Unicode` | `apt install unixodbc odbc-postgresql` |
  | SQL Server | `ODBC Driver 18 for SQL Server` | pacote `msodbcsql18` (repositório da Microsoft, o mesmo do PowerShell) |
  | MySQL | `MySQL ODBC 8.0 Unicode Driver` | MySQL Connector/ODBC (dev.mysql.com) |

- **Saída HTTPS (porta 443)** para o endereço do servidor Simplifica Compras. Nenhuma regra de
  entrada é necessária. Modo banco/rpinfo: acesso ao banco/API pela rede interna.
- Recursos: memória de ~350 MB numa loja de 27 mil códigos de barras (o agente guarda a última
  leitura para mandar só o que mudou); CPU só durante as leituras (completa de 27 mil em ~15 s).

## 2. Instalação (cerca de 5 minutos)

1. Copie a pasta `agente_linux` para o servidor (pendrive, `scp`...), por exemplo em `/root/agente_linux`.
2. Rode, como administrador:

   ```
   cd /root/agente_linux
   sudo bash instalar.sh
   ```

3. Responda as perguntas (Enter aceita a sugestão entre colchetes):

| Pergunta | Exemplo |
|---|---|
| De onde vêm os preços | `1` arquivo, `2` API RPInfo, `3` banco |
| Servidor Simplifica Compras | informado pela Simplifica Compras |
| **arquivo:** pasta e nome do arquivo | `/srv/pricetab`, `PRICETAB.TXT` |
| **rpinfo:** endereço da API, usuário, CNPJ | `http://10.0.0.8:9000`, `simplifica`, `11222333000181` |
| **banco:** driver, servidor, porta, banco | número na lista, `10.0.0.5`, `5432`, `erp` |
| **banco (SQL Server):** certificado próprio/autoassinado | `s` (o comum na rede interna) |
| **banco:** usuário e nome da VIEW | `simplifica_leitura`, `vw_simplifica_precos` |
| Intervalo de leitura e horário da completa | `5` e `12:00` |
| Chave da loja e senha (do banco ou da API) | digitadas/coladas **sem aparecer na tela** |

4. O instalador:
   - cria o usuário de serviço **`simplifica`** (sem login, sem senha, sem sudo);
   - instala em **`/opt/simplifica-compras/agente`** (pasta `750`, `config.json` **`600`**:
     só o usuário `simplifica` lê a chave e a senha);
   - **testa as conexões como o usuário do serviço antes de registrar qualquer coisa** (se falhar,
     nada é mudado);
   - registra e inicia o serviço **`simplifica-agente`** (inicia junto com o servidor; se cair, o
     systemd reinicia em 30 s) e mostra o resultado da primeira leitura.

**Modo arquivo:** o usuário `simplifica` precisa conseguir LER o arquivo. Se o instalador avisar
que não consegue, libere a leitura, por exemplo:
`setfacl -m u:simplifica:rx /srv/pricetab && setfacl -m u:simplifica:r /srv/pricetab/PRICETAB.TXT`.

## 3. Versão nova e reconfiguração

Rode `sudo bash instalar.sh` de novo (da pasta com a versão nova). Com o agente já instalado ele
oferece:

- **1 = atualizar só o programa:** troca o `agente.ps1`, mantém a configuração e reinicia o serviço;
- **2 = reconfigurar:** refaz as perguntas; Enter mantém cada valor atual (inclusive chave e senha).
  A configuração nova só substitui a atual **se o teste passar**: um dado errado não derruba o
  agente que já está rodando.

Não há atualização automática: toda versão nova é entregue à TI e instalada por ela.

## 4. Segurança

- **Somente leitura e só o necessário:** no modo banco, só as colunas do contrato da VIEW; no modo
  rpinfo, só código, descrição, preços, oferta vigente, departamento, balança e ativo. Custo,
  margem, estoque, fornecedor, dados fiscais e de clientes nunca saem da loja.
- **Sem portas abertas:** o agente não escuta conexões e não aceita comandos de fora. As respostas
  do servidor são só sinais fixos ("envie de novo", "faça uma leitura completa").
- **Credenciais:** no Linux não existe a proteção DPAPI do Windows; a chave da loja e a senha ficam
  no `config.json`, **legível só pelo usuário `simplifica`** (o agente avisa no log se a permissão
  for afrouxada). Nunca aparecem no log.
- **Serviço confinado pelo systemd:** sem nenhum privilégio de administrador
  (`CapabilityBoundingSet=` vazio, `NoNewPrivileges`), sistema de arquivos somente leitura exceto a
  própria pasta (`ProtectSystem=strict`), `/home` só leitura, sem dispositivos, só rede IP.
  `systemd-analyze security simplifica-agente` = **2.9 OK**.
- **Auditoria:** cópia legível de cada pacote enviado em `auditoria/` (guardada 30 dias).
- **Travas no servidor:** pacote que tiraria mais de 20% dos produtos ou derrubaria o preço de muitos
  produtos de uma vez fica retido para conferência.
- **Um agente por loja:** outro servidor com a mesma chave é recusado até a liberação.

**Aviso no journal ao iniciar (normal):** o PowerShell grava no log do sistema, como *warning*
(`ScriptBlock_Compile_Detail`), o texto de scripts que usam criptografia, compactação ou Base64 — o
agente usa as três (resumo SHA-256 da foto, gzip dos pacotes, proteção do Windows). É o mesmo
registro do evento 4104 do Windows. Contém só o código do `agente.ps1` (o mesmo da pasta), **nunca
a chave ou a senha**, e só aparece na partida.

## 5. Operação

| Comando / pasta | O quê |
|---|---|
| `systemctl status simplifica-agente` | situação do serviço |
| `journalctl -u simplifica-agente -f` | acompanhar ao vivo |
| `sudo systemctl restart simplifica-agente` | reiniciar (faz uma leitura completa) |
| `/opt/simplifica-compras/agente/logs/` | o que o agente fez (leituras, envios, falhas), 30 dias |
| `/opt/simplifica-compras/agente/auditoria/` | cópia de cada pacote enviado |
| `/opt/simplifica-compras/agente/fila/` | pacotes aguardando envio (internet fora: entregues ao voltar) |

Teste a qualquer momento, sem enviar preços:

```
cd /opt/simplifica-compras/agente
sudo runuser -u simplifica -- env HOME=$PWD pwsh -NoProfile -File agente.ps1 -TestarConexao
```

**Problemas comuns:**
- **"Data source name not found"** / driver ausente: instale o driver ODBC e confira o nome com
  `odbcinst -q -d`.
- **SQL Server "certificate verify failed"**: responda `s` na pergunta do certificado (reconfigurar).
- **"password authentication failed" / "Access denied"**: usuário ou senha do banco, ou falta o
  `GRANT SELECT` na VIEW.
- **"Outro agente já está registrado para esta loja"**: peça à Simplifica Compras a liberação
  (troca de servidor). Reinstalar no **mesmo** servidor e na mesma pasta não precisa de liberação.
- **"Connection refused" / "Name or service not known"** com o servidor Simplifica: regra de saída
  HTTPS 443 ou DNS. Os preços ficam na fila e são entregues quando a conexão voltar.

## 6. Remoção

```
sudo bash /opt/simplifica-compras/agente/desinstalar.sh
```

Para e remove o serviço, **apaga a pasta inteira** (inclusive o `config.json` com a chave e a senha,
os logs e a auditoria) e remove o usuário `simplifica`. Não remove o PowerShell 7 nem os drivers
ODBC (podem ser usados por outros programas). Depois, remova também o usuário de banco/API do
Simplifica no sistema da loja.
