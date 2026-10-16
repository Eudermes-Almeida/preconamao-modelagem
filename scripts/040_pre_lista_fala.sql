-- =============================================================================================
-- 040 — Pré-lista por voz: palavras FALADAS de cada item
-- =============================================================================================
-- O cliente fala "refri", "pasta de dente", "ração de cachorro"; o app precisa achar o item da
-- pré-lista (Refrigerante, Creme dental, Ração para cães). Os termos (pre_lista_termo) não servem
-- para isso: são o começo da descrição do PRICETAB ("SABONETE LIQUIDO"), não o jeito de falar.
-- O app já casa a fala com o NOME do item e com os termos; aqui entra só o que nenhum dos dois
-- cobre (sinônimos, regionalismos, gírias). Plural não precisa: o app tira o "s" dos dois lados.
-- Fala em minúsculas e sem acento (é como o app compara). Uma fala aponta para um único item.
-- O catálogo (GET /pre-lista) devolve as falas de cada item.
-- =============================================================================================

CREATE TABLE IF NOT EXISTS pre_lista_fala (
    id       SERIAL PRIMARY KEY,
    item_id  INTEGER NOT NULL REFERENCES pre_lista_item (id),
    fala     VARCHAR(60) NOT NULL UNIQUE
);

ALTER TABLE pre_lista_fala ENABLE ROW LEVEL SECURITY;

CREATE TEMP TABLE fala_seed (item VARCHAR(60), fala VARCHAR(60)) ON COMMIT DROP;

INSERT INTO fala_seed (item, fala) VALUES
  -- Mercearia
  ('Café', 'cafe em po'),
  ('Café', 'po de cafe'),
  ('Feijão carioca', 'feijao carioquinha'),
  ('Farinha de mandioca torrada', 'farinha de mesa'),
  ('Macarrão espaguete', 'espaguete'),
  ('Milho em conserva', 'lata de milho'),
  ('Filtro de café', 'coador de papel'),
  -- Frios e laticínios
  ('Queijo mussarela', 'mucarela'),
  ('Queijo mussarela', 'mozarela'),
  ('Queijo mussarela', 'queijo mucarela'),
  ('Bacon', 'toucinho'),
  -- Açougue
  ('Peito de frango', 'file de frango'),
  ('Frango inteiro / passarinho', 'galinha'),
  ('Outros cortes bovinos', 'carne de boi'),
  ('Outros cortes bovinos', 'picanha'),
  ('Outros cortes bovinos', 'patinho'),
  ('Outros cortes bovinos', 'musculo'),
  ('Outros cortes bovinos', 'cupim'),
  ('Outros cortes bovinos', 'maminha'),
  ('Outros cortes bovinos', 'fraldinha'),
  ('Outros cortes bovinos', 'costela de boi'),
  ('Outros cortes suínos', 'carne de porco'),
  ('Outros cortes suínos', 'bisteca'),
  -- Padaria
  ('Pão francês', 'pao de sal'),
  ('Pão francês', 'paozinho'),
  ('Pão francês', 'cacetinho'),
  ('Pão de forma', 'pao de sanduiche'),
  ('Outros biscoitos', 'bolacha'),
  ('Biscoito recheado', 'bolacha recheada'),
  ('Biscoito água e sal', 'bolacha agua e sal'),
  ('Biscoito água e sal', 'cream cracker'),
  ('Biscoito maisena', 'bolacha maisena'),
  ('Biscoito de polvilho', 'bolacha de polvilho'),
  -- Hortifrúti
  ('Mamão', 'papaia'),
  ('Mandioca', 'aipim'),
  ('Mandioca', 'macaxeira'),
  -- Congelados
  ('Batata palito congelada', 'batata frita'),
  ('Batata palito congelada', 'batata congelada'),
  ('Sorvete', 'picole'),
  -- Bebidas
  ('Refrigerante', 'refri'),
  ('Refrigerante', 'guarana'),
  ('Água mineral', 'agua'),
  ('Água mineral', 'agua sem gas'),
  ('Água mineral', 'agua com gas'),
  ('Água mineral', 'galao de agua'),
  ('Refresco', 'suco em po'),
  ('Chá mate', 'mate'),
  ('Cerveja', 'breja'),
  ('Cachaça', 'pinga'),
  -- Higiene
  ('Shampoo', 'xampu'),
  ('Creme dental', 'pasta de dente'),
  ('Creme dental', 'pasta dental'),
  ('Creme dental', 'creme de dente'),
  ('Escova dental', 'escova de dente'),
  ('Enxaguante bucal', 'antisseptico bucal'),
  ('Papel higiênico', 'papel de banheiro'),
  ('Aparelho de barbear', 'gilete'),
  ('Aparelho de barbear', 'barbeador'),
  ('Aparelho de barbear', 'lamina de barbear'),
  ('Lenço umedecido infantil', 'lencinho umedecido'),
  -- Limpeza
  ('Sabão em pó', 'sabao de roupa'),
  ('Esponja de lavar louças', 'bucha'),
  ('Esponja de lavar louças', 'esponja de louca'),
  ('Esponja de lavar louças', 'esponja de cozinha'),
  ('Esponja de aço', 'palha de aco'),
  ('Esponja de aço', 'bombril'),
  ('Água sanitária', 'candida'),
  ('Água sanitária', 'cloro'),
  ('Limpador multiuso', 'multi uso'),
  ('Saco para lixo', 'saquinho de lixo'),
  ('Purificador de ar', 'aromatizador'),
  ('Inseticida aerossol', 'veneno de inseto'),
  -- Pet
  ('Ração para cães', 'racao de cachorro'),
  ('Ração para cães', 'racao para cachorro'),
  ('Ração para cães', 'racao de cao'),
  ('Ração para cães', 'racao canina'),
  ('Ração para gatos', 'racao de gato'),
  ('Ração para gatos', 'racao felina'),
  ('Areia sanitária', 'areia de gato'),
  -- Drogaria
  ('Curativo adesivo', 'band aid'),
  ('Curativo adesivo', 'bandaid'),
  ('Álcool em gel', 'alcool'),
  ('Protetor solar', 'filtro solar'),
  -- Bazar
  ('Pilhas alcalinas tamanho AA', 'pilha pequena'),
  ('Pilhas alcalinas tamanho AAA', 'pilha palito'),
  ('Chinelo de borracha', 'havaianas'),
  ('Descartáveis (copo, prato, talher)', 'copo de plastico'),
  ('Descartáveis (copo, prato, talher)', 'prato descartavel'),
  -- Doces
  ('Balas, drops e chicletes', 'chiclete'),
  ('Salgadinho', 'chips');

-- Nome de item escrito errado aqui não pode virar fala perdida em silêncio.
DO $$
DECLARE
    faltando TEXT;
BEGIN
    SELECT string_agg(DISTINCT s.item, ', ') INTO faltando
      FROM fala_seed s
     WHERE NOT EXISTS (SELECT 1 FROM pre_lista_item i WHERE i.nome = s.item);
    IF faltando IS NOT NULL THEN
        RAISE EXCEPTION 'Itens da pré-lista não encontrados: %', faltando;
    END IF;
END $$;

INSERT INTO pre_lista_fala (item_id, fala)
SELECT i.id, s.fala
  FROM fala_seed s
  JOIN pre_lista_item i ON i.nome = s.item
ON CONFLICT (fala) DO UPDATE SET item_id = EXCLUDED.item_id;
