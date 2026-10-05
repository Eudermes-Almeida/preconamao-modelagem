-- PRICETAB real (PRICE2.TXT, rede de 4 lojas, analisado em 2026-10-05). Diferenças em relação ao
-- arquivo simulado e o que muda no banco:
--   * códigos de até 14 dígitos (22 no arquivo)                    -> codigo_barras VARCHAR(14);
--   * descrições muito abreviadas (IOG, QJ MUSS, CR DENT)           -> dicionário de abreviações e
--     descricao_expandida, calculada em toda carga (a original continua em descricao, como veio);
--   * ~50% das linhas são códigos auxiliares do mesmo produto        -> grupo_codigo (a busca por
--     voz mostra cada produto uma vez só);
--   * produtos de balança com código interno 0000000CCCCCD (D = dígito verificador)
--                                                                     -> vendido_por_kg e
--     codigo_balanca (CCCCC, o que a etiqueta da balança traz — HIPÓTESE até ver uma etiqueta
--     desta rede).
-- A busca por voz passa a usar descricao_busca (expandida, minúscula e sem acento) com índice
-- de trigramas: com ~6 mil produtos, a consulta sem índice já passava de 70 ms.

-- ---------------------------------------------------------------------------------------------
-- Produtos
-- ---------------------------------------------------------------------------------------------
ALTER TABLE produtos ALTER COLUMN codigo_barras TYPE VARCHAR(14);
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS descricao_expandida VARCHAR(120);
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS descricao_busca VARCHAR(120);
-- Código interno do produto de balança, como vem na etiqueta (sem zeros à esquerda e sem o
-- dígito verificador do PRICETAB). NULL nos demais.
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS codigo_balanca VARCHAR(8);
-- Códigos com a mesma descrição e o mesmo preço = o mesmo produto (código auxiliar do ERP):
-- todos apontam para o menor código do grupo.
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS grupo_codigo VARCHAR(14);

CREATE INDEX IF NOT EXISTS produtos_descricao_busca_trgm_idx ON produtos USING gin (descricao_busca gin_trgm_ops);
CREATE INDEX IF NOT EXISTS produtos_codigo_balanca_idx ON produtos (codigo_balanca) WHERE codigo_balanca IS NOT NULL;

-- ---------------------------------------------------------------------------------------------
-- Dicionário de abreviações (fonte: tools/dicionario_abreviacoes.csv; INSERTs gerados por
-- tools/dicionario_seed.py). "^" no começo do termo = só vale como primeira palavra.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS abreviacao (
    id        SERIAL PRIMARY KEY,
    termo     VARCHAR(60) NOT NULL UNIQUE,
    expansao  VARCHAR(80) NOT NULL
);
ALTER TABLE abreviacao ENABLE ROW LEVEL SECURITY;

TRUNCATE abreviacao;
INSERT INTO abreviacao (termo, expansao) VALUES
  ('^C BOV', 'CARNE BOVINA'),
  ('^C SUI', 'CARNE SUINA'),
  ('^C', 'CARNE'),
  ('C CRACKER', 'CREAM CRACKER'),
  ('CR DENT', 'CREME DENTAL'),
  ('CR LEITE', 'CREME DE LEITE'),
  ('CR PENT', 'CREME PARA PENTEAR'),
  ('CR TRAT', 'CREME DE TRATAMENTO'),
  ('CR BARB', 'CREME DE BARBEAR'),
  ('CR AVELA', 'CREME DE AVELA'),
  ('CR CEB', 'CREME E CEBOLA'),
  ('CR CE', 'CREME E CEBOLA'),
  ('LEITE COND', 'LEITE CONDENSADO'),
  ('SH COND', 'SHAMPOO E CONDICIONADOR'),
  ('GELO SAB', 'GELO SABOR'),
  ('S SAB', 'SEM SABOR'),
  ('S LIVRE', 'SEMPRE LIVRE'),
  ('^ESC', 'ESCOVA'),
  ('CARACU ESC', 'CARACU ESCURA'),
  ('CAST PARA', 'CASTANHA DO PARA'),
  ('CAST MEDIO', 'CASTANHO MEDIO'),
  ('CAST MED', 'CASTANHO MEDIO'),
  ('CAST ESC', 'CASTANHO ESCURO'),
  ('CAST CLAR', 'CASTANHO CLARO'),
  ('HOMEM CAST', 'HOMEM CASTANHO'),
  ('FABER CAST', 'FABER CASTELL'),
  ('CAC CAST', 'CACAU E CASTANHA'),
  ('CAST NOZ', 'CASTANHA E NOZES'),
  ('^MAC', 'MACARRAO'),
  ('^SALG', 'SALGADINHO'),
  ('^LIMP', 'LIMPADOR'),
  ('LIMP PERF', 'LIMPADOR PERFUMADO'),
  ('LIMP CREM', 'LIMPADOR CREMOSO'),
  ('^EXT TOM', 'EXTRATO DE TOMATE'),
  ('M TOM', 'MOLHO DE TOMATE'),
  ('^AP', 'APARELHO'),
  ('BARB GOIAB', 'BARBECUE GOIABA'),
  ('^BR', 'BARRA'),
  ('BEB PROT', 'BEBIDA PROTEICA'),
  ('BAR PROT', 'BARRA DE PROTEINA'),
  ('WAFER PROT', 'WAFER PROTEICO'),
  ('LOCAO HIDRAT', 'LOCAO HIDRATANTE'),
  ('LEITE FERM', 'LEITE FERMENTADO'),
  ('LEITE LV', 'LEITE LONGA VIDA'),
  ('ACUCAR REF', 'ACUCAR REFINADO'),
  ('FAR LAC', 'FARINHA LACTEA'),
  ('FR VERM', 'FRUTAS VERMELHAS'),
  ('FRUT VERM', 'FRUTAS VERMELHAS'),
  ('AGUA MIN', 'AGUA MINERAL'),
  ('RACAO CAO', 'RACAO PARA CAES'),
  ('COQUETEL ALC', 'COQUETEL ALCOOLICO'),
  ('VIN NAC', 'VINHO NACIONAL'),
  ('ESPUM NAC', 'ESPUMANTE NACIONAL'),
  ('CUID TOT', 'CUIDADO TOTAL'),
  ('REP TOT', 'REPARACAO TOTAL'),
  ('FEIJAO CAR', 'FEIJAO CARIOCA'),
  ('CAB SAUVIG', 'CABERNET SAUVIGNON'),
  ('CAB SAU', 'CABERNET SAUVIGNON'),
  ('ACHOC PO', 'ACHOCOLATADO EM PO'),
  ('LEITE PO', 'LEITE EM PO'),
  ('MIST BOLO', 'MISTURA PARA BOLO'),
  ('PAPEL HIG', 'PAPEL HIGIENICO'),
  ('COPO DESC', 'COPO DESCARTAVEL'),
  ('COLHER DESC', 'COLHER DESCARTAVEL'),
  ('GARFO DESC', 'GARFO DESCARTAVEL'),
  ('PRATO DESC', 'PRATO DESCARTAVEL'),
  ('POTE DESC', 'POTE DESCARTAVEL'),
  ('C', 'COM'),
  ('S', 'SEM'),
  ('CR', 'CREME'),
  ('COND', 'CONDICIONADOR'),
  ('SAB', 'SABONETE'),
  ('ESC', 'ESCURO'),
  ('CAST', 'CASTANHA'),
  ('MAC', 'MACIA'),
  ('SALG', 'SALGADO'),
  ('LIMP', 'LIMPEZA'),
  ('EXT', 'EXTRA'),
  ('PROT', 'PROTECAO'),
  ('HIDRAT', 'HIDRATACAO'),
  ('AC', 'ACUCAR'),
  ('CHOC', 'CHOCOLATE'),
  ('BISC', 'BISCOITO'),
  ('IOG', 'IOGURTE'),
  ('REFRIG', 'REFRIGERANTE'),
  ('CERV', 'CERVEJA'),
  ('QJ', 'QUEIJO'),
  ('DENT', 'DENTAL'),
  ('SH', 'SHAMPOO'),
  ('DESOD', 'DESODORANTE'),
  ('BEB', 'BEBIDA'),
  ('AERO', 'AEROSSOL'),
  ('STA', 'SANTA'),
  ('STO', 'SANTO'),
  ('FGO', 'FRANGO'),
  ('INTG', 'INTEGRAL'),
  ('INTEG', 'INTEGRAL'),
  ('CONG', 'CONGELADO'),
  ('VIN', 'VINHO'),
  ('TEMP', 'TEMPERADO'),
  ('BCO', 'BRANCO'),
  ('BCA', 'BRANCA'),
  ('ORIG', 'ORIGINAL'),
  ('LIQ', 'LIQUIDO'),
  ('TINT', 'TINTURA'),
  ('SAND', 'SANDUICHE'),
  ('SAND HAV', 'SANDALIA HAVAIANAS'),
  ('HAV', 'HAVAIANAS'),
  ('SCH', 'SACHE'),
  ('LAR', 'LARANJA'),
  ('LAV', 'LAVANDA'),
  ('RECH', 'RECHEADO'),
  ('PTO', 'PRETO'),
  ('LT', 'LATA'),
  ('LN', 'LONG NECK'),
  ('GFA', 'GARRAFA'),
  ('BD', 'BANDEJA'),
  ('BDJ', 'BANDEJA'),
  ('TP', 'TETRA PAK'),
  ('PT', 'POTE'),
  ('PC', 'PECA'),
  ('VD', 'VIDRO'),
  ('CX', 'CAIXA'),
  ('PCT', 'PACOTE'),
  ('BOV', 'BOVINA'),
  ('SUI', 'SUINA'),
  ('VERM', 'VERMELHO'),
  ('AMEND', 'AMENDOIM'),
  ('ABS', 'ABSORVENTE'),
  ('NAT', 'NATURAL'),
  ('REQ', 'REQUEIJAO'),
  ('LING', 'LINGUICA'),
  ('CALAB', 'CALABRESA'),
  ('PIM', 'PIMENTA'),
  ('ENERG', 'ENERGETICO'),
  ('CREM', 'CREMOSO'),
  ('CONDIM', 'CONDIMENTO'),
  ('PERF', 'PERFUME'),
  ('ESM', 'ESMALTE'),
  ('FRD', 'FRALDA'),
  ('SORV', 'SORVETE'),
  ('AMAC', 'AMACIANTE'),
  ('FAT', 'FATIADO'),
  ('INST', 'INSTANTANEO'),
  ('MARACJ', 'MARACUJA'),
  ('MARACUJ', 'MARACUJA'),
  ('GUA', 'GUARANA'),
  ('BARB', 'BARBEAR'),
  ('TRAT', 'TRATAMENTO'),
  ('GELAT', 'GELATINA'),
  ('DESC', 'DESCONTO'),
  ('NAC', 'NACIONAL'),
  ('FERM', 'FERMENTO'),
  ('PAD', 'PADARIA'),
  ('VDE', 'VERDE'),
  ('CIG', 'CIGARRO'),
  ('DESINF', 'DESINFETANTE'),
  ('CHIL', 'CHILENO'),
  ('CONC', 'CONCENTRADO'),
  ('PRES', 'PRESUNTO'),
  ('FAR', 'FARINHA'),
  ('TTO', 'TINTO'),
  ('HAMB', 'HAMBURGUER'),
  ('FEM', 'FEMININO'),
  ('MASC', 'MASCULINO'),
  ('SANIT', 'SANITARIA'),
  ('BOMB', 'BOMBOM'),
  ('CHIC', 'CHICLETE'),
  ('TOT', 'TOTAL'),
  ('CUID', 'CUIDADO'),
  ('INF', 'INFANTIL'),
  ('REF', 'REFIL'),
  ('AZ', 'AZUL'),
  ('VIT', 'VITAMINA'),
  ('GAL', 'GALINHA'),
  ('PENT', 'PENTEAR'),
  ('EMP', 'EMPANADO'),
  ('PLAST', 'PLASTICO'),
  ('POLV', 'POLVILHO'),
  ('ESPJ', 'ESPONJA'),
  ('MUSS', 'MUSSARELA'),
  ('MANT', 'MANTEIGA'),
  ('MAND', 'MANDIOCA'),
  ('FRUT', 'FRUTAS'),
  ('FR', 'FRUTAS'),
  ('HIG', 'HIGIENICO'),
  ('ANIV', 'ANIVERSARIO'),
  ('CEB', 'CEBOLA'),
  ('BAUN', 'BAUNILHA'),
  ('TGO', 'TRIGO'),
  ('ACHOC', 'ACHOCOLATADO'),
  ('CONF', 'CONFEITADO'),
  ('LAC', 'LACTOSE'),
  ('PESG', 'PESSEGO'),
  ('DETERG', 'DETERGENTE'),
  ('ISOT', 'ISOTONICO'),
  ('MIST', 'MISTURA'),
  ('SOBRM', 'SOBREMESA'),
  ('BAN', 'BANANA'),
  ('MAM', 'MAMAO'),
  ('MOR', 'MORANGO'),
  ('ABCX', 'ABACAXI'),
  ('TANGR', 'TANGERINA'),
  ('TANG', 'TANGERINA'),
  ('REFRESCO TANG', 'REFRESCO TANG'),
  ('GOI', 'GOIABA'),
  ('GOIAB', 'GOIABA'),
  ('GOIA', 'GOIABA'),
  ('CERJ', 'CEREJA'),
  ('FRAMB', 'FRAMBOESA'),
  ('LIM', 'LIMAO'),
  ('HORT', 'HORTELA'),
  ('EUCAL', 'EUCALIPTO'),
  ('CEN', 'CENOURA'),
  ('CROC', 'CROCANTE'),
  ('SORT', 'SORTIDO'),
  ('CAPPUC', 'CAPPUCCINO'),
  ('CAD', 'CADERNO'),
  ('ALC', 'ALCALINA'),
  ('PAST', 'PASTILHA'),
  ('MARG', 'MARGARINA'),
  ('MORTAD', 'MORTADELA'),
  ('MED', 'MEDIO'),
  ('GTS', 'GRATIS'),
  ('PREM', 'PREMIUM'),
  ('PIP', 'PIPOCA'),
  ('PRESERV', 'PRESERVATIVO'),
  ('SVE', 'SUAVE'),
  ('SUV', 'SUAVE'),
  ('RSVD', 'RESERVADO'),
  ('ADOC', 'ADOCANTE'),
  ('AMANT', 'AMANTEIGADO'),
  ('INV', 'INVISIBLE'),
  ('ENXAG', 'ENXAGUANTE'),
  ('DESN', 'DESNATADO'),
  ('DESNAT', 'DESNATADO'),
  ('PANETT', 'PANETONE'),
  ('ALIM', 'ALIMENTOS'),
  ('REG', 'REGULAR'),
  ('RAL', 'RALADO'),
  ('EV', 'EXTRA VIRGEM'),
  ('CAIP', 'CAIPIRA'),
  ('PIC', 'PICANTE'),
  ('MULT', 'MULTI'),
  ('ALUM', 'ALUMINIO'),
  ('ARG', 'ARGENTINO'),
  ('FD', 'FOLHA DUPLA'),
  ('ADT', 'ADULTO'),
  ('AD', 'ADULTO'),
  ('SARD', 'SARDINHA'),
  ('NAPOL', 'NAPOLITANO'),
  ('TROP', 'TROPICAL'),
  ('PURIFIC', 'PURIFICADOR'),
  ('MOSC', 'MOSCATEL'),
  ('CHURRASQ', 'CHURRASCO'),
  ('CHURR', 'CHURRASCO'),
  ('FLOC', 'FLOCOS'),
  ('ALG', 'ALGODAO'),
  ('ALVEJ', 'ALVEJANTE'),
  ('DEF', 'DEFUMADO'),
  ('DEFUM', 'DEFUMADO'),
  ('INSET', 'INSETICIDA'),
  ('TRAD', 'TRADICIONAL'),
  ('NEUT', 'NEUTRO'),
  ('INT', 'INTEIRO'),
  ('COB', 'COBERTURA'),
  ('COBERT', 'COBERTURA'),
  ('CARAM', 'CARAMELO'),
  ('CARAML', 'CARAMELO'),
  ('APRES', 'APRESUNTADO'),
  ('CHARD', 'CHARDONNAY'),
  ('ESPUM', 'ESPUMANTE'),
  ('SABORIZ', 'SABORIZADA'),
  ('ODORIZ', 'ODORIZADOR'),
  ('DESENTUP', 'DESENTUPIDOR'),
  ('APONT', 'APONTADOR'),
  ('CONJ', 'CONJUNTO'),
  ('MAMAD', 'MAMADEIRA'),
  ('SUPLEM', 'SUPLEMENTO'),
  ('COMP', 'COMPOSTO'),
  ('BRINQ', 'BRINQUEDO'),
  ('SENSTV', 'SENSITIVE'),
  ('ACU', 'ACUCAR'),
  ('^TEMP', 'TEMPERO'),
  ('M USO', 'MULTIUSO'),
  ('CHOC PO', 'CHOCOLATE EM PO'),
  ('ESPAG', 'ESPAGUETE'),
  ('LARJ', 'LARANJA'),
  ('SEMIDESN', 'SEMIDESNATADO'),
  ('AMEIX', 'AMEIXA'),
  ('SAUVIG', 'SAUVIGNON'),
  ('MAQ', 'MAQUINA'),
  ('SOLUV', 'SOLUVEL'),
  ('CLAR', 'CLARO'),
  ('FORT', 'FORTE'),
  ('FT', 'FOLHA TRIPLA'),
  ('FS', 'FOLHA SIMPLES'),
  ('MARAC', 'MARACUJA'),
  ('SABAO PO', 'SABAO EM PO'),
  ('SABAO BR', 'SABAO EM BARRA'),
  ('MOLHO TOM', 'MOLHO DE TOMATE'),
  ('^EXT PROPOLIS', 'EXTRATO DE PROPOLIS'),
  ('CHOCOTT', 'CHOCOTTONE'),
  ('ROSQ', 'ROSQUINHA'),
  ('RAPAD', 'RAPADURA'),
  ('BICARB', 'BICARBONATO'),
  ('REPEL', 'REPELENTE'),
  ('LACT', 'LACTOSE');

-- Expande as abreviações de uma descrição, palavra por palavra (palavra = trecho entre espaços).
-- "C/" e "S/" grudados na palavra seguinte ("C/GAS", "S/AC") viram COM / SEM antes. Em cada
-- posição tenta o termo mais longo primeiro (até 3 palavras); o resultado de uma regra não é
-- expandido de novo. Palavra sem regra fica como veio (inclusive "500ml", "kg").
CREATE OR REPLACE FUNCTION expandir_descricao(p_descricao TEXT) RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_palavras  TEXT[] := '{}';
    v_saida     TEXT[] := '{}';
    v_palavra   TEXT;
    v_chave     TEXT;
    v_expansao  TEXT;
    v_total     INTEGER;
    v_i         INTEGER := 1;
    v_n         INTEGER;
    v_achou     BOOLEAN;
BEGIN
    IF p_descricao IS NULL OR btrim(p_descricao) = '' THEN
        RETURN p_descricao;
    END IF;
    FOREACH v_palavra IN ARRAY regexp_split_to_array(btrim(p_descricao), '\s+') LOOP
        IF v_palavra ~* '^[CS]/' THEN
            v_palavras := v_palavras || CASE WHEN upper(left(v_palavra, 1)) = 'C' THEN 'COM' ELSE 'SEM' END;
            IF length(v_palavra) > 2 THEN
                v_palavras := v_palavras || substr(v_palavra, 3);
            END IF;
        ELSE
            v_palavras := v_palavras || v_palavra;
        END IF;
    END LOOP;

    v_total := array_length(v_palavras, 1);
    WHILE v_i <= v_total LOOP
        v_achou := false;
        FOR v_n IN REVERSE least(3, v_total - v_i + 1)..1 LOOP
            v_chave := upper(array_to_string(v_palavras[v_i:v_i + v_n - 1], ' '));
            v_expansao := NULL;
            IF v_i = 1 THEN
                SELECT a.expansao INTO v_expansao FROM abreviacao a WHERE a.termo = '^' || v_chave;
            END IF;
            IF v_expansao IS NULL THEN
                SELECT a.expansao INTO v_expansao FROM abreviacao a WHERE a.termo = v_chave;
            END IF;
            IF v_expansao IS NOT NULL THEN
                v_saida := v_saida || v_expansao;
                v_i := v_i + v_n;
                v_achou := true;
                EXIT;
            END IF;
        END LOOP;
        IF NOT v_achou THEN
            v_saida := v_saida || v_palavras[v_i];
            v_i := v_i + 1;
        END IF;
    END LOOP;
    RETURN left(array_to_string(v_saida, ' '), 120);
END;
$$;

-- Texto que a busca por voz compara (o app manda o falado em minúsculas e sem acento).
CREATE OR REPLACE FUNCTION descricao_para_busca(p_descricao TEXT) RETURNS TEXT
LANGUAGE sql STABLE AS $$
    SELECT lower(unaccent(p_descricao))
$$;

-- Produto de balança: código interno curto (arquivo simulado: "2984") ou, no PRICETAB real,
-- 0000000CCCCCD — 13 dígitos começando com 0000 e no máximo 7 significativos (8 = EAN-8
-- completado com zeros, produto comum) — com "kg" como palavra na descrição ("BANANA PRATA kg";
-- "MORANGO 1,002kg" é peso da embalagem, não preço do quilo).
CREATE OR REPLACE FUNCTION eh_codigo_interno(p_codigo TEXT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_codigo ~ '^0000[0-9]{9}$' AND length(ltrim(p_codigo, '0')) BETWEEN 2 AND 7
$$;

CREATE OR REPLACE FUNCTION eh_vendido_por_kg(p_codigo TEXT, p_descricao TEXT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_codigo ~ '^[0-9]{1,6}$'
        OR (eh_codigo_interno(p_codigo) AND p_descricao ~* '(^|\s)kg(\s|$)')
$$;

-- O que a etiqueta da balança traz no lugar do produto: o código interno sem o dígito verificador
-- (0000000040556 -> 4055). HIPÓTESE: confirmar com uma etiqueta real desta rede.
CREATE OR REPLACE FUNCTION codigo_balanca_de(p_codigo TEXT, p_descricao TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN eh_codigo_interno(p_codigo) AND eh_vendido_por_kg(p_codigo, p_descricao)
                THEN left(ltrim(p_codigo, '0'), length(ltrim(p_codigo, '0')) - 1) END
$$;

-- Recalcula o grupo de todos os produtos ativos (mesma descrição original e mesmo preço).
CREATE OR REPLACE FUNCTION agrupar_produtos() RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_alterados INTEGER;
BEGIN
    UPDATE produtos p SET grupo_codigo = g.grupo
      FROM (SELECT id, min(codigo_barras) OVER (PARTITION BY descricao, preco_centavos) AS grupo
              FROM produtos WHERE ativo) g
     WHERE g.id = p.id AND p.grupo_codigo IS DISTINCT FROM g.grupo;
    GET DIAGNOSTICS v_alterados = ROW_COUNT;
    UPDATE produtos SET grupo_codigo = NULL WHERE NOT ativo AND grupo_codigo IS NOT NULL;
    RETURN v_alterados;
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Pré-lista: compara com a descrição expandida ("IOG BATAVO" não começa com "IOGURTE").
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION vincular_produtos_pre_lista(p_ids BIGINT[] DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE produtos p
       SET pre_lista_item_id = (
            SELECT t.item_id
              FROM pre_lista_termo t
             WHERE upper(unaccent(coalesce(p.descricao_expandida, p.descricao))) = t.termo
                OR upper(unaccent(coalesce(p.descricao_expandida, p.descricao))) LIKE t.termo || ' %'
             ORDER BY length(t.termo) DESC
             LIMIT 1)
     WHERE p_ids IS NULL OR p.id = ANY (p_ids);
    RETURN (SELECT count(*) FROM produtos WHERE pre_lista_item_id IS NOT NULL);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Aplicação de uma carga (substitui a do 016). Novidades: descrição expandida recalculada para
-- TODOS os produtos do arquivo (dicionário novo vale na próxima carga), categorização e pré-lista
-- pela expandida, regra nova de balança e agrupamento dos códigos auxiliares.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION aplicar_carga_pricetab(p_itens JSONB, p_limite_inativacao NUMERIC DEFAULT 0.20)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
    v_itens          INTEGER;
    v_ativos         INTEGER;
    v_sumiriam       INTEGER;
    v_reativados     INTEGER;
    v_precos         INTEGER;
    v_inativados     INTEGER;
    v_ids_descricao  BIGINT[];
    v_ids_novos      BIGINT[];
    v_descricoes     INTEGER;
BEGIN
    DROP TABLE IF EXISTS carga_itens;
    -- Código repetido no arquivo: vale a última linha.
    CREATE TEMP TABLE carga_itens ON COMMIT DROP AS
        SELECT DISTINCT ON (x.codigo) x.codigo, x.descricao, x.preco, CAST(NULL AS TEXT) AS expandida
          FROM ROWS FROM (jsonb_to_recordset(p_itens) AS (codigo TEXT, descricao TEXT, preco INTEGER))
               WITH ORDINALITY AS x(codigo, descricao, preco, n)
         ORDER BY x.codigo, x.n DESC;

    SELECT count(*) INTO v_itens FROM carga_itens;
    SELECT count(*) INTO v_ativos FROM produtos WHERE ativo;
    SELECT count(*) INTO v_sumiriam
      FROM produtos p
     WHERE p.ativo AND NOT EXISTS (SELECT 1 FROM carga_itens c WHERE c.codigo = p.codigo_barras);

    IF v_itens = 0 OR (v_ativos > 0 AND v_sumiriam::NUMERIC / v_ativos > p_limite_inativacao) THEN
        RETURN jsonb_build_object('retida', true, 'itens', v_itens, 'ativos', v_ativos, 'sumiriam', v_sumiriam);
    END IF;

    -- Uma expansão por descrição distinta (~4 mil para ~6 mil linhas).
    UPDATE carga_itens c SET expandida = e.expandida
      FROM (SELECT d.descricao, expandir_descricao(d.descricao) AS expandida
              FROM (SELECT DISTINCT descricao FROM carga_itens) d) e
     WHERE e.descricao = c.descricao;

    UPDATE produtos p SET ativo = true, atualizado_em = now()
      FROM carga_itens c
     WHERE c.codigo = p.codigo_barras AND NOT p.ativo;
    GET DIAGNOSTICS v_reativados = ROW_COUNT;

    UPDATE produtos p SET preco_centavos = c.preco, atualizado_em = now()
      FROM carga_itens c
     WHERE c.codigo = p.codigo_barras AND p.preco_centavos <> c.preco;
    GET DIAGNOSTICS v_precos = ROW_COUNT;

    -- Descrição (ou a expansão dela) mudou: recategoriza, menos quando a localização foi
    -- corrigida à mão. Só a descrição original conta como "descrição alterada" no resumo.
    SELECT count(*) INTO v_descricoes
      FROM produtos p JOIN carga_itens c ON c.codigo = p.codigo_barras
     WHERE p.descricao <> c.descricao;

    WITH alterados AS (
        UPDATE produtos p
           SET descricao = c.descricao,
               descricao_expandida = c.expandida,
               descricao_busca = descricao_para_busca(c.expandida),
               vendido_por_kg = eh_vendido_por_kg(c.codigo, c.descricao),
               codigo_balanca = codigo_balanca_de(c.codigo, c.descricao),
               atualizado_em = CASE WHEN p.descricao <> c.descricao THEN now() ELSE p.atualizado_em END,
               layout_id = CASE WHEN p.layout_manual THEN p.layout_id ELSE categorizar(c.expandida) END
          FROM carga_itens c
         WHERE c.codigo = p.codigo_barras
           AND (p.descricao <> c.descricao OR p.descricao_expandida IS DISTINCT FROM c.expandida)
        RETURNING p.id)
    SELECT array_agg(id) INTO v_ids_descricao FROM alterados;

    WITH novos AS (
        INSERT INTO produtos (codigo_barras, descricao, descricao_expandida, descricao_busca, preco_centavos,
                              layout_id, vendido_por_kg, codigo_balanca, ativo, atualizado_em)
        SELECT c.codigo, c.descricao, c.expandida, descricao_para_busca(c.expandida), c.preco,
               categorizar(c.expandida), eh_vendido_por_kg(c.codigo, c.descricao),
               codigo_balanca_de(c.codigo, c.descricao), true, now()
          FROM carga_itens c
         WHERE NOT EXISTS (SELECT 1 FROM produtos p WHERE p.codigo_barras = c.codigo)
        RETURNING id)
    SELECT array_agg(id) INTO v_ids_novos FROM novos;

    UPDATE produtos p SET ativo = false, atualizado_em = now()
     WHERE p.ativo AND NOT EXISTS (SELECT 1 FROM carga_itens c WHERE c.codigo = p.codigo_barras);
    GET DIAGNOSTICS v_inativados = ROW_COUNT;

    IF v_ids_descricao IS NOT NULL OR v_ids_novos IS NOT NULL THEN
        PERFORM vincular_produtos_pre_lista(coalesce(v_ids_descricao, '{}') || coalesce(v_ids_novos, '{}'));
    END IF;

    PERFORM agrupar_produtos();

    RETURN jsonb_build_object(
        'retida', false,
        'itens', v_itens,
        'novos', coalesce(array_length(v_ids_novos, 1), 0),
        'precosAlterados', v_precos,
        'descricoesAlteradas', v_descricoes,
        'inativados', v_inativados,
        'reativados', v_reativados);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Produtos já cadastrados: expande, recalcula balança/grupo e revincula a pré-lista.
-- ---------------------------------------------------------------------------------------------
UPDATE produtos SET descricao_expandida = expandir_descricao(descricao);
UPDATE produtos SET descricao_busca = descricao_para_busca(descricao_expandida),
                    codigo_balanca = codigo_balanca_de(codigo_barras, descricao),
                    layout_id = CASE WHEN layout_manual THEN layout_id ELSE coalesce(categorizar(descricao_expandida), layout_id) END;
SELECT agrupar_produtos();
SELECT vincular_produtos_pre_lista();
