-- Produtos pesáveis (balança: hortifrúti, açougue, padaria). A etiqueta da balança não está no
-- PRICETAB: o código de barras é gerado na pesagem, no padrão EAN-13 de uso interno
--   2 CCCC 00 VVVVV D  (ex.: 2298400004652 = produto 2984, total R$ 4,65, dígito 2)
-- levantado das etiquetas reais do Supermercados ABC (2026-09-29). O back decodifica a etiqueta
-- (ver EtiquetaBalanca.java) e busca o produto pelo código interno de 4 dígitos, que é o que
-- fica gravado em produtos.codigo_barras. preco_centavos desses produtos = preço do QUILO.
--
-- O código interno de 4 dígitos é a hipótese mais provável (o campo da etiqueta sempre termina
-- em 00); confirmar com o PRICETAB real. Se for outro, basta ajustar ETIQUETA_BALANCA_* no back.

ALTER TABLE produtos ADD COLUMN IF NOT EXISTS vendido_por_kg BOOLEAN NOT NULL DEFAULT false;

-- Item novo da pré-lista (id fixo 167, depois dos 166 da planilha; ver ITENS_ADICIONAIS em
-- tools/pre_lista_seed.py): nenhum item existente atendia repolho.
INSERT INTO pre_lista_item (id, categoria_id, nome, ordem) VALUES (167, 5, 'Repolho', 18)
    ON CONFLICT (id) DO NOTHING;
INSERT INTO pre_lista_termo (item_id, termo) VALUES (167, 'REPOLHO')
    ON CONFLICT (termo) DO NOTHING;

-- Os 3 produtos das etiquetas reais (descrição por extenso: a da etiqueta vem abreviada, ex.
-- "TOMATE ITAL Kg", e a busca por voz precisa do nome completo). layout_id pelo categorizador:
-- REPOLHO -> 9 (Hortifrúti 1, verduras), TOMATE -> 19 (Hortifrúti 2, legumes).
INSERT INTO produtos (codigo_barras, descricao, preco_centavos, layout_id, vendido_por_kg) VALUES
    ('2984', 'REPOLHO ROXO PARTIDO KG', 990, 9, true),
    ('2651', 'REPOLHO VERDE PARTIDO KG', 199, 9, true),
    ('2070', 'TOMATE ITALIANO KG', 1199, 19, true)
ON CONFLICT (codigo_barras) DO UPDATE SET
    descricao = EXCLUDED.descricao, preco_centavos = EXCLUDED.preco_centavos,
    layout_id = EXCLUDED.layout_id, vendido_por_kg = EXCLUDED.vendido_por_kg;

SELECT vincular_produtos_pre_lista();
