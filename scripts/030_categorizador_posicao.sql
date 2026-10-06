-- =============================================================================================
-- 030 — Categorizador: a PRIMEIRA palavra manda (DES em 2026-10-06; produção junto com o 027)
-- Reexecutável.
--
-- Antes, entre várias regras que casavam, vencia a de menor "ordem" (fixa), não importava onde a
-- palavra estava: "BOLO CREMOSO INTEGRAL BANANA" ia para Hortifrúti por causa de BANANA, e
-- "MACARRAO ... LASANHA BANANA" também. Agora, dentro de cada camada (FRASE antes de PALAVRA),
-- vence a regra cujo termo aparece PRIMEIRO na descrição; empatadas na posição, vence a frase mais
-- longa ("^DOCE LEITE" antes de "^DOCE "); a "ordem" só desempata o resto.
--
-- Regras novas: palavras que abrem descrição e não tinham regra (BOLO, SOPA, CALDO...) e frases
-- para os casos em que a primeira palavra engana (BATATA PALHA não é Hortifrúti; AMACIANTE CARNE
-- não é Limpeza; BEBIDA LACTEA com WHEY não é Farmácia).
--
-- FRASE com "^" na frente (como nos dicionários) só vale no COMEÇO da descrição: "^DOCE LEITE"
-- pega "DOCE LEITE NOPONTO", mas não "IOGURTE ... DOCE LEITE". As frases antigas, sem "^", seguem
-- valendo em qualquer ponto e vencendo qualquer palavra (INFANTIL, FARINHA, VINAGRE...).
-- =============================================================================================

CREATE OR REPLACE FUNCTION categorizar(p_descricao TEXT) RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    WITH t AS (
        SELECT texto, regexp_split_to_array(texto, '[^A-Z0-9]+') AS palavras
          FROM (SELECT upper(unaccent(p_descricao)) AS texto) n
    )
    SELECT x.layout_id FROM (
        SELECT r.layout_id, 0 AS camada, position(ltrim(r.termo, '^') IN t.texto) AS pos, r.termo, r.ordem
          FROM categorizador_regra r, t
         WHERE r.tipo = 'FRASE'
           AND CASE WHEN left(r.termo, 1) = '^' THEN left(t.texto, length(r.termo) - 1) = substr(r.termo, 2)
                    ELSE position(r.termo IN t.texto) > 0 END
        UNION ALL
        SELECT r.layout_id, 1 AS camada, array_position(t.palavras, r.termo) AS pos, r.termo, r.ordem
          FROM categorizador_regra r, t
         WHERE r.tipo = 'PALAVRA' AND r.termo = ANY (t.palavras)
    ) x
    ORDER BY x.camada, x.pos, length(x.termo) DESC, x.ordem
    LIMIT 1
$$;

-- Setores (layout_posicao): 1 PADARIA, 3 FARMÁCIA/DROGARIA, 5 MERCEARIA 1, 6 FRIOS E LATICÍNIOS 1,
-- 7 HIGIENE E BELEZA 1, 8 BAZAR 1, 11 CONGELADOS E RESFRIADOS 1, 29 BOMBONIERE, 30 ECOLOGIA, 31 PESCADOS.
-- (DES: a 1ª versão deste script gravou as frases sem "^"; troca pelas ancoradas.)
DELETE FROM categorizador_regra WHERE tipo = 'FRASE' AND termo IN
    ('BATATA PALHA', 'BATATA CROQUES', 'BATATA PRINGLES', 'BATATA CONGELAD', 'BATATA PALITO', 'BATATA ONDULADA',
     'BATATA BEM BRASIL', 'BATATA MCCAIN', 'AMACIANTE CARNE', 'AMACIANTE DE CARNE', 'BEBIDA LACTEA', 'DOCE LEITE',
     'PRE TREINO', 'SALGADINHO COXINHA', 'SALGADINHO ESFIRRA', 'SALGADINHO FOLHADO');
DELETE FROM categorizador_regra WHERE tipo = 'PALAVRA' AND termo = 'DOCE';

INSERT INTO categorizador_regra (tipo, ordem, termo, layout_id)
SELECT v.tipo, (SELECT coalesce(max(ordem), 0) FROM categorizador_regra) + v.n, v.termo, v.layout_id
  FROM (VALUES
    -- frases: a primeira palavra sozinha levaria ao setor errado
    (1,  'FRASE',   '^BATATA PALHA',        5),
    (2,  'FRASE',   '^BATATA CROQUES',      5),
    (3,  'FRASE',   '^BATATA PRINGLES',     5),
    (4,  'FRASE',   '^BATATA CONGELAD',    11),
    (5,  'FRASE',   '^BATATA PALITO',      11),
    (6,  'FRASE',   '^BATATA ONDULADA',    11),
    (7,  'FRASE',   '^BATATA BEM BRASIL',  11),
    (8,  'FRASE',   '^BATATA MCCAIN',      11),
    (9,  'FRASE',   '^AMACIANTE CARNE',     5),
    (10, 'FRASE',   '^AMACIANTE DE CARNE',  5),
    (11, 'FRASE',   '^BEBIDA LACTEA',       6),
    (12, 'FRASE',   '^DOCE LEITE',          5),
    (14, 'FRASE',   '^PRE TREINO',          3),
    (15, 'FRASE',   '^SALGADINHO COXINHA',  1),
    (16, 'FRASE',   '^SALGADINHO ESFIRRA',  1),
    (17, 'FRASE',   '^SALGADINHO FOLHADO',  1),
    (18, 'FRASE',   '^BOLINHO DE TILAPIA', 31),
    (19, 'FRASE',   '^PRATO VASO',         30),
    (60, 'FRASE',   '^POTE PLANTA',        30),
    -- palavras que abrem descrição e não tinham regra
    (20, 'PALAVRA', 'BOLO',                1),
    (21, 'PALAVRA', 'BRIOCHE',             1),
    (22, 'PALAVRA', 'BOLINHO',             5),
    (23, 'PALAVRA', 'LANCHINHO',           5),
    (24, 'PALAVRA', 'BOLACHA',             5),
    (25, 'PALAVRA', 'SALGADINHO',          5),
    (26, 'PALAVRA', 'CHIPS',               5),
    (27, 'PALAVRA', 'SOPA',                5),
    (28, 'PALAVRA', 'CALDO',               5),
    (29, 'PALAVRA', 'CONDIMENTO',          5),
    (30, 'PALAVRA', 'MISTURA',             5),
    (31, 'PALAVRA', 'CAPPUCCINO',          5),
    (32, 'PALAVRA', 'SHAKE',               6),
    (33, 'PALAVRA', 'SOBREMESA',           6),
    (34, 'PALAVRA', 'PAMONHA',            11),
    (35, 'PALAVRA', 'EMPANADA',           11),
    (36, 'PALAVRA', 'TORTA',              11),
    (37, 'PALAVRA', 'ACAIZINHO',          11),
    (38, 'PALAVRA', 'FORMA',               8),
    (39, 'PALAVRA', 'PADARIA',             1),
    (40, 'PALAVRA', 'ESMALTE',             7),
    -- utensílios: sem regra, caíam pelo que vinha depois ("GARFO SOBREMESA", "COPO SHAKE")
    (41, 'PALAVRA', 'GARFO',               8),
    (42, 'PALAVRA', 'COLHER',              8),
    (43, 'PALAVRA', 'TACA',                8),
    (44, 'PALAVRA', 'JOGO',                8),
    (45, 'PALAVRA', 'CONJUNTO',            8),
    (46, 'PALAVRA', 'COPO',                8),
    (47, 'PALAVRA', 'GARRAFA',             8),
    (48, 'PALAVRA', 'PORTA',               8),
    (49, 'PALAVRA', 'POTE',                8),
    (50, 'PALAVRA', 'PRATO',               8),
    (51, 'PALAVRA', 'DECORADOR',           8),
    (52, 'PALAVRA', 'ESPATULA',            8),
    (53, 'PALAVRA', 'TOPO',                8),
    (54, 'FRASE',   '^DOCE ',             29)
  ) v(n, tipo, termo, layout_id)
ON CONFLICT (tipo, termo) DO UPDATE SET layout_id = EXCLUDED.layout_id;

-- Recalcula o setor de todos os produtos (os de setor manual ficam como estão).
SELECT id, reprocessar_descricoes(id) FROM loja ORDER BY id;
