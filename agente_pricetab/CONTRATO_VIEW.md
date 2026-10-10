# Simplifica Compras — Conector de banco de dados: contrato da VIEW

Para a equipe de TI do supermercado. Este documento descreve **o único objeto** que o
Simplifica Compras lê no banco de dados do ERP.

## Como funciona

1. A TI cria no banco do ERP a VIEW **`vw_simplifica_precos`**, com as colunas abaixo.
2. A TI cria um usuário de banco **só com permissão de SELECT nessa VIEW** (nenhuma tabela,
   nenhuma escrita).
3. O agente do Simplifica Compras, instalado num computador da rede da loja, lê a VIEW por
   **ODBC**, com o driver oficial do fabricante do banco (MySQL, SQL Server, PostgreSQL, Firebird,
   Oracle...), e envia os dados por **HTTPS, só de saída**, para o servidor do Simplifica
   Compras. Nenhuma porta é aberta na loja e nada é gravado no ERP.

## Colunas (uma linha por código de barras)

| Coluna | Tipo sugerido | Obrigatória | Conteúdo |
|---|---|---|---|
| `codigo_barras` | texto (até 14) | sim | EAN/código de barras. Produto com vários códigos = várias linhas. |
| `descricao` | texto (até 120) | sim | Descrição do produto (a mais completa disponível). |
| `preco` | decimal(12,2) | sim | Preço de venda normal, o que o caixa cobra fora de promoção. |
| `preco_promocional` | decimal(12,2) | não | Preço de oferta. Só é usado se for menor que `preco`. |
| `promocao_ate` | data | não | Último dia da oferta. Oferta vencida é ignorada. |
| `unidade` | texto (2) | não | `KG` = vendido na balança; `UN` = unidade. |
| `secao` | texto (até 60) | não | Seção/departamento do ERP (ajuda a posicionar o produto no mapa da loja). |
| `codigo_interno` | texto | recomendada | Código do produto no ERP. Agrupa os códigos de barras do mesmo produto. Sem ela, cada código de barras é tratado como um produto. |
| `ativo` | `S`/`N` ou 1/0 | não | `N` = produto fora de linha (sai do aplicativo). Sem a coluna = todos ativos. |
| `data_alteracao` | data e hora | recomendada | Última alteração de preço, oferta ou cadastro. Permite ler **só o que mudou** a cada poucos minutos. Deve mudar em todas as linhas (códigos) do produto. |

**Mínimo:** uma VIEW só com `codigo_barras`, `descricao` e `preco` já funciona. O agente confere
as colunas da VIEW ao iniciar e a cada leitura completa: as opcionais que existirem são usadas, as
que faltarem têm o comportamento descrito na tabela, e colunas novas passam a valer sem reinstalar.
Sem `data_alteracao`, cada leitura é da VIEW inteira, comparada com a anterior (só o que mudou é
enviado). Faltando uma obrigatória, o agente para e informa qual no log e no teste de conexão.

**Não incluir:** custo, margem, estoque, fornecedor, dados fiscais ou de clientes. O agente
pede só as colunas acima (as que a VIEW tiver) e mais nenhuma: outra coluna que esteja na VIEW é
ignorada e nunca sai da loja.

## Exemplo (MySQL)

```sql
CREATE VIEW vw_simplifica_precos AS
SELECT e.ean            AS codigo_barras,
       p.descricao      AS descricao,
       pr.preco_venda   AS preco,
       CASE WHEN pr.dt_fim_oferta >= CURDATE() THEN pr.preco_oferta END  AS preco_promocional,
       CASE WHEN pr.dt_fim_oferta >= CURDATE() THEN pr.dt_fim_oferta END AS promocao_ate,
       p.unidade_venda  AS unidade,
       s.nome           AS secao,
       p.id_produto     AS codigo_interno,
       p.ativo          AS ativo,
       GREATEST(p.dt_alteracao, pr.dt_alteracao) AS data_alteracao
  FROM produto_ean e
  JOIN produto p  ON p.id_produto = e.id_produto
  JOIN preco   pr ON pr.id_produto = p.id_produto
  JOIN secao   s  ON s.id_secao = p.id_secao;

CREATE USER 'simplifica_leitura'@'<ip do computador do agente>' IDENTIFIED BY '<senha forte>';
GRANT SELECT ON <banco>.vw_simplifica_precos TO 'simplifica_leitura'@'<ip do computador do agente>';
```

(Os nomes das tabelas são do exemplo: cada ERP tem os seus. Só o nome da VIEW e das colunas é fixo.)

## Frequência e volume

- Leitura completa ao ligar o agente e uma vez por dia (horário combinado com a TI).
- Leitura incremental a cada 5 minutos (configurável), só das linhas com `data_alteracao` recente.
- Uma loja de 16 mil itens gera uma leitura completa de poucos segundos.
