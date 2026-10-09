-- DES (multi-loja): herda o 026a (aplicado em produção em 09/10/2026, antes do 027).
-- Quando o multi-loja for para a produção, o 027 leva as regras do 026a para o dicionário PRICE2
-- sozinho (todas as linhas de abreviacao viram PRICE2), e a expansão do 027 já descarta palavra
-- com expansão vazia (o "^HF"). Este script põe no banco do DES (onde o 027 rodou antes do 026a)
-- as regras do dicionário e do categorizador. A regra de balança do 026a fica de fora (ver abaixo).
-- Respeita o 030: não recoloca as palavras/frases que ele tirou por serem ambíguas.
-- Idempotente.

-- Balança: o 026a marcava como kg os frios e carnes de código interno sem unidade. NÃO vem para
-- cá: no multi-loja o interno sem unidade mostra "Preço de balança (por kg ou unidade): confira na
-- etiqueta" (regra decidida no DES, mais cuidadosa) e esta é a que vale quando o 027 for à produção.
-- Volta a de 3 argumentos do 027, caso a 1ª versão deste script a tenha trocado.
CREATE OR REPLACE FUNCTION eh_vendido_por_kg(p_codigo TEXT, p_descricao TEXT, p_unidade TEXT DEFAULT NULL) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN p_unidade = 'KG' THEN true
             WHEN p_unidade = 'UN' THEN false
             ELSE eh_codigo_interno(p_codigo) AND p_descricao ~* '(^|\s)kg(\s|$)'
           END
$$;

INSERT INTO abreviacao (termo, expansao, dicionario_id)
SELECT v.termo, v.expansao, (SELECT id FROM dicionario WHERE nome = 'PRICE2') FROM (VALUES
    -- calçados: aqui SAND é sandália
    ('SAND HAVAI', 'SANDALIA HAVAIANAS'), ('SAND HAVIA', 'SANDALIA HAVAIANAS'), ('SAND HAVI', 'SANDALIA HAVAIANAS'),
    ('SAND IPANEMA', 'SANDALIA IPANEMA'), ('SAND CARTAGO', 'SANDALIA CARTAGO'), ('SAND RIDER', 'SANDALIA RIDER'),
    ('SAND GRENDENE', 'SANDALIA GRENDENE'), ('SAND MORMAII', 'SANDALIA MORMAII'), ('SAND GRENDHA', 'SANDALIA GRENDHA'),
    ('SAND ZAXYNINA', 'SANDALIA ZAXY NINA'), ('HAVAI', 'HAVAIANAS'),
    ('MAMAO HAVAI', 'MAMAO HAVAI'), -- mamão havaí não é a marca de sandália
    -- material escolar: ESC = escolar
    ('CANETA ESC', 'CANETA ESCOLAR'), ('MOCHILA ESC', 'MOCHILA ESCOLAR'), ('ESTOJO ESC', 'ESTOJO ESCOLAR'),
    ('LAPIS ESC', 'LAPIS ESCOLAR'), ('LAPIS COR ESC', 'LAPIS DE COR ESCOLAR'), ('APONTADOR ESC', 'APONTADOR ESCOLAR'),
    ('LAPISEIRA ESC', 'LAPISEIRA ESCOLAR'), ('COLA ESC', 'COLA ESCOLAR'), ('PASTA ESC', 'PASTA ESCOLAR'),
    ('BORRACHA ESC', 'BORRACHA ESCOLAR'), ('CORRETIVO ESC', 'CORRETIVO ESCOLAR'), ('REGUA ESC', 'REGUA ESCOLAR'),
    ('GRAFITE ESC', 'GRAFITE ESCOLAR'), ('TESOURA ESC', 'TESOURA ESCOLAR'), ('ETIQUETA ESC', 'ETIQUETA ESCOLAR'),
    -- descartáveis: DESC = descartável
    ('FRALDA DESC', 'FRALDA DESCARTAVEL'), ('COPO DESC', 'COPO DESCARTAVEL'), ('PRATO DESC', 'PRATO DESCARTAVEL'),
    ('POTE DESC', 'POTE DESCARTAVEL'), ('COLHER DESC', 'COLHER DESCARTAVEL'), ('GARFO DESC', 'GARFO DESCARTAVEL'),
    ('FACA DESC', 'FACA DESCARTAVEL'), ('TALHER DESC', 'TALHER DESCARTAVEL'),
    -- cabelo e beleza
    ('CREME PENT', 'CREME PARA PENTEAR'), ('CREME TRAT', 'CREME DE TRATAMENTO'), ('OLEO CAP', 'OLEO CAPILAR'),
    ('BANHO CRE', 'BANHO DE CREME'), ('SHAMP', 'SHAMPOO'), ('CONDIC', 'CONDICIONADOR'), ('ANTISSEPT', 'ANTISSEPTICO'),
    ('GILLET', 'GILLETTE'),
    -- outros cortes frequentes
    ('SALGAD', 'SALGADINHO'), ('PORC', 'PORCELANA'), ('UMED', 'UMEDECIDA'),
    -- prefixo de seção: HF (hortifrúti) sai da descrição
    ('^HF', '')
) AS v(termo, expansao)
WHERE NOT EXISTS (SELECT 1 FROM abreviacao a
                   WHERE a.dicionario_id = (SELECT id FROM dicionario WHERE nome = 'PRICE2')
                     AND a.termo = v.termo AND a.condicao IS NULL);

WITH novas(tipo, termo, layout_id, n) AS (VALUES
    ('FRASE', 'BEBIDA LACTEA', 6, 1), ('FRASE', 'BEBIDA ICE', 12, 2), ('FRASE', 'BEBIDA MISTA', 12, 3),
    ('FRASE', 'BEBIDA KEEPCOOLE', 12, 4), ('FRASE', 'BEBIDA HIDRATANT', 4, 5), ('FRASE', 'BEBIDA VITAMINIC', 4, 6),
    ('FRASE', 'BEBIDA ADES', 4, 7), ('FRASE', 'MISTURA BOLO', 5, 8), ('FRASE', 'TIRA MANCHA', 13, 9),
    ('FRASE', 'BARRA PROTEICA', 33, 10), ('FRASE', 'BARRA CEREAL', 29, 11), ('FRASE', 'TOALHA UMEDECIDA', 28, 12),
    ('FRASE', 'OLEO MOTOR', 18, 13), ('FRASE', 'CERA AUTO', 18, 14), ('FRASE', 'FRALDA DESCARTAVEL', 7, 15),
    -- bebidas
    ('PALAVRA', 'GIN', 12, 101), ('PALAVRA', 'LICOR', 12, 102), ('PALAVRA', 'ESPUMANTE', 12, 103),
    ('PALAVRA', 'CONHAQUE', 12, 104), ('PALAVRA', 'RUM', 12, 105), ('PALAVRA', 'COQUETEL', 12, 106),
    ('PALAVRA', 'SAKE', 12, 107), ('PALAVRA', 'TEQUILA', 12, 108), ('PALAVRA', 'SIDRA', 12, 109),
    ('PALAVRA', 'APERITIVO', 12, 110), ('PALAVRA', 'GATORADE', 4, 111), ('PALAVRA', 'ISOTONICO', 4, 112),
    -- higiene e beleza
    ('PALAVRA', 'SHAMPOO', 7, 120), ('PALAVRA', 'CONDICIONADOR', 7, 121), ('PALAVRA', 'ESMALTE', 7, 122),
    ('PALAVRA', 'TINTURA', 7, 123), ('PALAVRA', 'BARBEADOR', 7, 124), ('PALAVRA', 'ANTISSEPTICO', 7, 125),
    ('PALAVRA', 'ELASTICO', 7, 126),
    -- infantil
    ('PALAVRA', 'BONECA', 28, 130), ('PALAVRA', 'BONECO', 28, 131), ('PALAVRA', 'MAMADEIRA', 28, 132),
    ('PALAVRA', 'CHUPETA', 28, 133),
    -- bazar 2: calçados, vestuário, papelaria, ferramentas
    ('PALAVRA', 'SANDALIA', 18, 140), ('PALAVRA', 'CHINELO', 18, 141), ('PALAVRA', 'MEIA', 18, 142),
    ('PALAVRA', 'JOELHEIRA', 18, 143), ('PALAVRA', 'CUECA', 18, 144), ('PALAVRA', 'CALCINHA', 18, 145),
    ('PALAVRA', 'PIJAMA', 18, 146), ('PALAVRA', 'ROUPAO', 18, 147), ('PALAVRA', 'CAMISETA', 18, 148),
    ('PALAVRA', 'LIVRO', 18, 150), ('PALAVRA', 'CADERNO', 18, 151), ('PALAVRA', 'CANETA', 18, 152),
    ('PALAVRA', 'LAPIS', 18, 153), ('PALAVRA', 'LAPISEIRA', 18, 154), ('PALAVRA', 'APONTADOR', 18, 155),
    ('PALAVRA', 'BORRACHA', 18, 156), ('PALAVRA', 'GRAFITE', 18, 157), ('PALAVRA', 'ESTOJO', 18, 158),
    ('PALAVRA', 'MOCHILA', 18, 159), ('PALAVRA', 'TESOURA', 18, 160), ('PALAVRA', 'REGUA', 18, 161),
    ('PALAVRA', 'CORRETIVO', 18, 162), ('PALAVRA', 'CALCULADORA', 18, 163), ('PALAVRA', 'ETIQUETA', 18, 164),
    ('PALAVRA', 'ESCOLAR', 18, 165), ('PALAVRA', 'FITILHO', 18, 166), ('PALAVRA', 'ALICATE', 18, 167),
    ('PALAVRA', 'ABRACADEIRA', 18, 168), ('PALAVRA', 'PINCEL', 18, 169),
    -- bazar 1: casa e cozinha
    ('PALAVRA', 'POTE', 8, 180), ('PALAVRA', 'GARRAFA', 8, 181), ('PALAVRA', 'TOALHA', 8, 182),
    ('PALAVRA', 'COPO', 8, 183), ('PALAVRA', 'CANECA', 8, 184), ('PALAVRA', 'VELA', 8, 185),
    ('PALAVRA', 'PRATO', 8, 186), ('PALAVRA', 'FORMA', 8, 187), ('PALAVRA', 'JARRA', 8, 188),
    ('PALAVRA', 'TIGELA', 8, 189), ('PALAVRA', 'LIXEIRA', 8, 190), ('PALAVRA', 'TACA', 8, 191),
    ('PALAVRA', 'ASSADEIRA', 8, 192), ('PALAVRA', 'FACA', 8, 193), ('PALAVRA', 'ESPATULA', 8, 194),
    ('PALAVRA', 'CESTO', 8, 195), ('PALAVRA', 'FRIGIDEIRA', 8, 196), ('PALAVRA', 'BANDEJA', 8, 197),
    ('PALAVRA', 'COLHER', 8, 198), ('PALAVRA', 'GARFO', 8, 199), ('PALAVRA', 'MARMITA', 8, 200),
    ('PALAVRA', 'TAPETE', 8, 201), ('PALAVRA', 'RELOGIO', 8, 202), ('PALAVRA', 'BALDE', 8, 203),
    ('PALAVRA', 'ESCORREDOR', 8, 204), ('PALAVRA', 'PENEIRA', 8, 205), ('PALAVRA', 'BACIA', 8, 206),
    ('PALAVRA', 'ENFEITE', 8, 207), ('PALAVRA', 'SQUEEZE', 8, 208), ('PALAVRA', 'AZEITEIRO', 8, 209),
    ('PALAVRA', 'ABRIDOR', 8, 210), ('PALAVRA', 'CABIDE', 8, 211), ('PALAVRA', 'ESPELHO', 8, 212),
    ('PALAVRA', 'NATAL', 8, 213), ('PALAVRA', 'BALAO', 8, 214), ('PALAVRA', 'SACOLA', 8, 215),
    ('PALAVRA', 'CUSCUZEIRO', 8, 216), ('PALAVRA', 'AFIADOR', 8, 217), ('PALAVRA', 'AVENTAL', 8, 218),
    ('PALAVRA', 'FILTRO', 8, 219), ('PALAVRA', 'PORCELANA', 8, 220),
    -- mercearia, bomboniere, bem-estar
    ('PALAVRA', 'DOCE', 5, 230), ('PALAVRA', 'CALDO', 5, 231), ('PALAVRA', 'AMENDOIM', 5, 232),
    ('PALAVRA', 'AZEITONA', 5, 233), ('PALAVRA', 'GELEIA', 5, 234), ('PALAVRA', 'CATCHUP', 5, 235),
    ('PALAVRA', 'KETCHUP', 5, 236), ('PALAVRA', 'POLVILHO', 5, 237), ('PALAVRA', 'PIPOCA', 5, 238),
    ('PALAVRA', 'FAROFA', 5, 239), ('PALAVRA', 'FERMENTO', 5, 240), ('PALAVRA', 'GRANOLA', 5, 241),
    ('PALAVRA', 'CAPPUCCINO', 5, 242), ('PALAVRA', 'PANETTONE', 5, 243), ('PALAVRA', 'BOLINHO', 5, 244),
    ('PALAVRA', 'CORANTE', 5, 245), ('PALAVRA', 'SALGADINHO', 5, 246),
    ('PALAVRA', 'CHICLETE', 29, 250), ('PALAVRA', 'MARSHMALLOW', 29, 251), ('PALAVRA', 'CIGARRO', 29, 252),
    ('PALAVRA', 'SUPLEMENTO', 33, 255), ('PALAVRA', 'PROTEICA', 33, 256), ('PALAVRA', 'WHEY', 33, 257),
    -- limpeza, pet, congelados
    ('PALAVRA', 'MULTIUSO', 13, 260), ('PALAVRA', 'VASSOURA', 13, 261), ('PALAVRA', 'RODO', 13, 262),
    ('PALAVRA', 'PRENDEDOR', 13, 263), ('PALAVRA', 'AROMATIZANTE', 13, 264), ('PALAVRA', 'ODORIZADOR', 13, 265),
    ('PALAVRA', 'DIFUSOR', 13, 266), ('PALAVRA', 'DESENTUPIDOR', 13, 267), ('PALAVRA', 'LIMPADOR', 13, 268),
    ('PALAVRA', 'CAO', 10, 270), ('PALAVRA', 'GATO', 10, 271), ('PALAVRA', 'OSSO', 10, 272),
    ('PALAVRA', 'BEBEDOURO', 10, 273), ('PALAVRA', 'COMEDOURO', 10, 274), ('PALAVRA', 'PETISCO', 10, 275),
    ('PALAVRA', 'GELO', 11, 280)
)
INSERT INTO categorizador_regra (tipo, ordem, termo, layout_id)
SELECT n.tipo, (SELECT coalesce(max(ordem), 0) FROM categorizador_regra r WHERE r.tipo = n.tipo) + n.n,
       n.termo, n.layout_id
  FROM novas n
 WHERE NOT EXISTS (SELECT 1 FROM categorizador_regra r WHERE r.tipo = n.tipo AND r.termo = n.termo)
   AND NOT (n.tipo = 'PALAVRA' AND n.termo IN ('DOCE', 'POTE', 'GARRAFA', 'COQUETEL', 'HAMBURGUER'))
   AND NOT (n.tipo = 'FRASE' AND n.termo IN ('BEBIDA LACTEA', 'DOCE LEITE'));

-- Produtos já cadastrados: recalcula como no fim do 027.
UPDATE produtos SET codigo_balanca = codigo_balanca_de(codigo_barras, loja_id),
                    vendido_por_kg = eh_vendido_por_kg(codigo_barras, descricao, unidade);
SELECT reprocessar_descricoes(id) FROM loja;
SELECT agrupar_produtos(id) FROM loja;
