-- =============================================================================================
-- 041 — Pré-lista por voz: MARCAS faladas e termo da ração de cães
-- =============================================================================================
-- 1) Marca falada sozinha ("coca-cola", "omo", "nescau") não dizia qual é o item: a pré-lista não
--    tem marcas. Aqui a marca vira um jeito de falar o item (pre_lista_fala com marca = true):
--    "coca-cola 2 litros" -> Refrigerante, e o app guarda a marca no lembrete ("Coca Cola - 2 L").
--    Só marcas que apontam para UM item (Ypê, Sadia, Nestlé fazem de tudo: ficam de fora).
--    Fala em minúsculas e sem acento; hífen vira espaço ("coca cola"), apóstrofo some ("hellmanns").
-- 2) "RACAO CAO": no PRICETAB de 16 posições a ração de cachorro vem "RACAO CAO PEDIGR" e nenhum
--    termo de Ração para cães casava (eram "RACAO CAES", "RACAO PARA CAES"...); "RACAO DOG" pega
--    "RACAO DOG CHOW". Depois do termo, os produtos de ração são religados ao item.
-- =============================================================================================

ALTER TABLE pre_lista_fala ADD COLUMN IF NOT EXISTS marca BOOLEAN NOT NULL DEFAULT false;

-- Falas do 040 que já eram marca.
UPDATE pre_lista_fala SET marca = true WHERE fala IN ('bombril', 'havaianas', 'band aid', 'bandaid');

CREATE TEMP TABLE marca_seed (item VARCHAR(60), fala VARCHAR(60)) ON COMMIT DROP;

INSERT INTO marca_seed (item, fala) VALUES
  -- Mercearia
  ('Arroz', 'tio joao'),
  ('Açúcar refinado', 'uniao'),
  ('Café', 'pilao'),
  ('Café', 'tres coracoes'),
  ('Café', 'cafe do ponto'),
  ('Óleo de soja', 'liza'),
  ('Óleo de soja', 'soya'),
  ('Azeite de oliva', 'gallo'),
  ('Azeite de oliva', 'andorinha'),
  ('Molho de tomate', 'pomarola'),
  ('Molho de tomate', 'tarantella'),
  ('Extrato de tomate', 'elefante'),
  ('Maionese', 'hellmanns'),
  ('Maionese', 'helmans'),
  ('Molho de pimenta', 'tabasco'),
  ('Tempero', 'sazon'),
  ('Achocolatado', 'nescau'),
  ('Achocolatado', 'toddy'),
  ('Achocolatado', 'ovomaltine'),
  ('Cereal matinal', 'sucrilhos'),
  ('Adoçante líquido', 'zero cal'),
  ('Adoçante líquido', 'adocyl'),
  -- Frios e laticínios
  ('Margarina', 'qualy'),
  ('Margarina', 'doriana'),
  ('Margarina', 'becel'),
  ('Requeijão cremoso', 'catupiry'),
  ('Leite condensado', 'leite moca'),
  ('Leite condensado', 'moca'),
  ('Leite em pó', 'ninho'),
  ('Leite em pó', 'leite ninho'),
  ('Leite em pó', 'molico'),
  ('Leite em pó', 'leite molico'),
  ('Leite fermentado', 'yakult'),
  ('Petit suisse', 'danoninho'),
  -- Padaria e doces
  ('Pão de forma', 'pullman'),
  ('Pão de forma', 'wickbold'),
  ('Pão de forma', 'plus vita'),
  ('Bolinho', 'ana maria'),
  ('Biscoito recheado', 'oreo'),
  ('Biscoito recheado', 'passatempo'),
  ('Biscoito recheado', 'trakinas'),
  ('Biscoito recheado', 'bono'),
  ('Biscoito recheado', 'negresco'),
  ('Bombom', 'sonho de valsa'),
  ('Bombom', 'ouro branco'),
  ('Bombom', 'serenata de amor'),
  ('Salgadinho', 'doritos'),
  ('Salgadinho', 'ruffles'),
  ('Salgadinho', 'cheetos'),
  ('Salgadinho', 'fandangos'),
  ('Salgadinho', 'pringles'),
  ('Salgadinho', 'elma chips'),
  ('Sorvete', 'kibon'),
  -- Bebidas
  ('Refrigerante', 'coca cola'),
  ('Refrigerante', 'coca'),
  ('Refrigerante', 'pepsi'),
  ('Refrigerante', 'fanta'),
  ('Refrigerante', 'sprite'),
  ('Refrigerante', 'guarana antarctica'),
  ('Refrigerante', 'kuat'),
  ('Refrigerante', 'sukita'),
  ('Refrigerante', 'dolly'),
  ('Suco', 'del valle'),
  ('Refresco', 'tang'),
  ('Refresco', 'clight'),
  ('Energético', 'red bull'),
  ('Energético', 'monster'),
  ('Isotônico', 'gatorade'),
  ('Isotônico', 'powerade'),
  ('Cerveja', 'skol'),
  ('Cerveja', 'brahma'),
  ('Cerveja', 'antarctica'),
  ('Cerveja', 'heineken'),
  ('Cerveja', 'budweiser'),
  ('Cerveja', 'itaipava'),
  ('Cerveja', 'amstel'),
  ('Cerveja', 'stella artois'),
  ('Cerveja', 'devassa'),
  ('Cerveja', 'spaten'),
  ('Cerveja', 'eisenbahn'),
  ('Cerveja', 'corona'),
  ('Vodka', 'smirnoff'),
  ('Vodka', 'absolut'),
  ('Whisky', 'johnnie walker'),
  ('Whisky', 'red label'),
  ('Whisky', 'black label'),
  ('Whisky', 'jack daniels'),
  ('Whisky', 'old parr'),
  ('Cachaça', 'ypioca'),
  ('Cachaça', 'velho barreiro'),
  ('Gin', 'tanqueray'),
  ('Rum', 'bacardi'),
  ('Espumante', 'chandon'),
  -- Higiene
  ('Creme dental', 'colgate'),
  ('Creme dental', 'sorriso'),
  ('Creme dental', 'close up'),
  ('Creme dental', 'sensodyne'),
  ('Enxaguante bucal', 'listerine'),
  ('Enxaguante bucal', 'plax'),
  ('Sabonete barra', 'lux'),
  ('Desodorante', 'rexona'),
  ('Desodorante', 'axe'),
  ('Desodorante', 'old spice'),
  ('Shampoo', 'seda'),
  ('Shampoo', 'pantene'),
  ('Shampoo', 'elseve'),
  ('Papel higiênico', 'neve'),
  ('Fralda descartável', 'pampers'),
  ('Fralda descartável', 'huggies'),
  ('Absorvente feminino', 'always'),
  ('Absorvente feminino', 'intimus'),
  ('Absorvente feminino', 'sempre livre'),
  ('Aparelho de barbear', 'prestobarba'),
  ('Protetor solar', 'sundown'),
  -- Limpeza
  ('Sabão em pó', 'omo'),
  ('Sabão em pó', 'brilhante'),
  ('Sabão em pó', 'tixan'),
  ('Sabão em pó', 'ariel'),
  ('Sabão em pó', 'surf'),
  ('Amaciante', 'comfort'),
  ('Amaciante', 'downy'),
  ('Amaciante', 'mon bijou'),
  ('Detergente', 'limpol'),
  ('Água sanitária', 'qboa'),
  ('Água sanitária', 'q boa'),
  ('Desinfetante', 'pinho sol'),
  ('Limpador multiuso', 'veja'),
  ('Esponja de aço', 'assolan'),
  ('Esponja de lavar louças', 'scotch brite'),
  ('Alvejante', 'vanish'),
  ('Desentupidor', 'diabo verde'),
  ('Inseticida aerossol', 'sbp'),
  ('Inseticida aerossol', 'raid'),
  ('Inseticida aerossol', 'baygon'),
  ('Purificador de ar', 'glade'),
  ('Purificador de ar', 'bom ar'),
  ('Repelente', 'repelex'),
  -- Pet
  ('Ração para cães', 'pedigree'),
  ('Ração para cães', 'pedigri'),
  ('Ração para cães', 'dog chow'),
  ('Ração para gatos', 'whiskas'),
  ('Ração para gatos', 'friskies'),
  ('Ração para gatos', 'cat chow');

-- Nome de item escrito errado aqui não pode virar marca perdida em silêncio.
DO $$
DECLARE
    faltando TEXT;
BEGIN
    SELECT string_agg(DISTINCT s.item, ', ') INTO faltando
      FROM marca_seed s
     WHERE NOT EXISTS (SELECT 1 FROM pre_lista_item i WHERE i.nome = s.item);
    IF faltando IS NOT NULL THEN
        RAISE EXCEPTION 'Itens da pré-lista não encontrados: %', faltando;
    END IF;
END $$;

INSERT INTO pre_lista_fala (item_id, fala, marca)
SELECT i.id, s.fala, true
  FROM marca_seed s
  JOIN pre_lista_item i ON i.nome = s.item
ON CONFLICT (fala) DO UPDATE SET item_id = EXCLUDED.item_id, marca = true;

-- 2) Ração de cachorro no PRICETAB de 16 posições.
INSERT INTO pre_lista_termo (item_id, termo)
SELECT i.id, t.termo
  FROM pre_lista_item i
 CROSS JOIN (VALUES ('RACAO CAO'), ('RACAO DOG')) AS t (termo)
 WHERE i.nome = 'Ração para cães'
ON CONFLICT (termo) DO NOTHING;

SELECT vincular_produtos_pre_lista(ARRAY(
    SELECT id FROM produtos
     WHERE upper(unaccent(coalesce(descricao_expandida, descricao))) LIKE 'RACAO %')) AS produtos_religados;
