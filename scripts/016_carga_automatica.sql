-- Carga automática do PRICETAB: o agente da loja (agente_pricetab/) envia o arquivo para a API
-- (POST /cargas/pricetab), que guarda a carga e aplica a diferença com aplicar_carga_pricetab().
-- Proteções (ver o plano de 2026-09-29): produto que some do arquivo é INATIVADO, não apagado;
-- carga que inativaria mais de 20% dos produtos fica RETIDA; cada carga é tudo ou nada (uma
-- transação); a loja manda "sinal de vida" e, sem ele, o app esconde o preço.

-- ---------------------------------------------------------------------------------------------
-- Produtos
-- ---------------------------------------------------------------------------------------------
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS ativo BOOLEAN NOT NULL DEFAULT true;
-- Localização corrigida à mão: a carga não recalcula (antes, toda carga sobrescrevia).
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS layout_manual BOOLEAN NOT NULL DEFAULT false;
-- Última vez que preço, descrição ou situação do produto mudou por uma carga.
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now();

-- ---------------------------------------------------------------------------------------------
-- Categorizador no banco (fonte: tools/categorizador.py, INSERTs gerados por
-- tools/categorizador_seed.py). Mesma regra do Python: primeiro FRASE contida na descrição,
-- depois PALAVRA inteira; dentro de cada camada vence a menor ordem.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categorizador_regra (
    id        SERIAL PRIMARY KEY,
    tipo      VARCHAR(7)  NOT NULL CHECK (tipo IN ('FRASE', 'PALAVRA')),
    ordem     INTEGER     NOT NULL,
    termo     VARCHAR(60) NOT NULL,
    layout_id BIGINT      NOT NULL REFERENCES layout_posicao(id),
    UNIQUE (tipo, termo)
);

TRUNCATE categorizador_regra;
INSERT INTO categorizador_regra (tipo, ordem, termo, layout_id) VALUES
  ('FRASE', 1, 'DOCE DE LEITE', 5),
  ('FRASE', 2, 'ZERO LACTOSE', 6),
  ('FRASE', 3, 'PAO DE QUEIJO FRESCO', 1),
  ('FRASE', 4, 'PAO DE QUEIJO', 11),
  ('FRASE', 5, 'PAES DE QUEIJO', 11),
  ('FRASE', 6, 'BOLO DE CHOCOLATE', 1),
  ('FRASE', 7, 'BISCOITO AGUA E SAL', 5),
  ('FRASE', 8, 'MOLHO DE TOMATE', 5),
  ('FRASE', 9, 'EXTRATO DE TOMATE', 5),
  ('FRASE', 10, 'OLEO DE SOJA', 5),
  ('FRASE', 11, 'VINAGRE', 5),
  ('FRASE', 12, 'FARINHA', 25),
  ('FRASE', 13, 'SAL REFINADO', 25),
  ('FRASE', 14, 'PEITO DE PERU', 6),
  ('FRASE', 15, 'POSTA DE CACAO', 31),
  ('FRASE', 16, 'NUGGETS', 11),
  ('FRASE', 17, 'COUVE', 9),
  ('FRASE', 18, 'AGUA SANITARIA', 23),
  ('FRASE', 19, 'AREIA SANITARIA', 10),
  ('FRASE', 20, 'SHAMPOO PET', 10),
  ('FRASE', 21, 'RACAO PARA GATOS', 20),
  ('FRASE', 22, 'ALCOOL EM GEL', 3),
  ('FRASE', 23, 'INFANTIL', 28),
  ('FRASE', 24, 'ASSADURAS', 28),
  ('PALAVRA', 1, 'BOMBOM', 29),
  ('PALAVRA', 2, 'BALA', 29),
  ('PALAVRA', 3, 'BALAS', 29),
  ('PALAVRA', 4, 'PIRULITO', 29),
  ('PALAVRA', 5, 'PIRULITOS', 29),
  ('PALAVRA', 6, 'CHOCOLATE', 29),
  ('PALAVRA', 7, 'LINGUICA', 2),
  ('PALAVRA', 8, 'LINGUICAS', 2),
  ('PALAVRA', 9, 'ALCATRA', 2),
  ('PALAVRA', 10, 'BOVINO', 2),
  ('PALAVRA', 11, 'PORCO', 2),
  ('PALAVRA', 12, 'FRANGO', 2),
  ('PALAVRA', 13, 'BOI', 2),
  ('PALAVRA', 14, 'SUINO', 2),
  ('PALAVRA', 15, 'CARNE', 2),
  ('PALAVRA', 16, 'TILAPIA', 31),
  ('PALAVRA', 17, 'CAMARAO', 31),
  ('PALAVRA', 18, 'PESCADO', 31),
  ('PALAVRA', 19, 'PESCADOS', 31),
  ('PALAVRA', 20, 'LULA', 31),
  ('PALAVRA', 21, 'PEIXE', 31),
  ('PALAVRA', 22, 'WHISKY', 12),
  ('PALAVRA', 23, 'UISQUE', 12),
  ('PALAVRA', 24, 'VODKA', 12),
  ('PALAVRA', 25, 'CACHACA', 12),
  ('PALAVRA', 26, 'DESTILADO', 12),
  ('PALAVRA', 27, 'DESTILADOS', 12),
  ('PALAVRA', 28, 'VINHO', 12),
  ('PALAVRA', 29, 'VINHOS', 12),
  ('PALAVRA', 30, 'CERVEJA', 22),
  ('PALAVRA', 31, 'CERVEJAS', 22),
  ('PALAVRA', 32, 'ENERGETICO', 4),
  ('PALAVRA', 33, 'ENERGETICOS', 4),
  ('PALAVRA', 34, 'AGUA', 4),
  ('PALAVRA', 35, 'CHA', 4),
  ('PALAVRA', 36, 'REFRIGERANTE', 14),
  ('PALAVRA', 37, 'COCA', 14),
  ('PALAVRA', 38, 'GUARANA', 14),
  ('PALAVRA', 39, 'REFRESCO', 24),
  ('PALAVRA', 40, 'TANG', 24),
  ('PALAVRA', 41, 'SUCO', 24),
  ('PALAVRA', 42, 'SUCOS', 24),
  ('PALAVRA', 43, 'ADOCANTE', 33),
  ('PALAVRA', 44, 'ADOANTE', 33),
  ('PALAVRA', 45, 'LIGHT', 33),
  ('PALAVRA', 46, 'LIGTH', 33),
  ('PALAVRA', 47, 'POLPA', 11),
  ('PALAVRA', 48, 'LASANHA', 11),
  ('PALAVRA', 49, 'SALCHICHA', 11),
  ('PALAVRA', 50, 'SALSICHA', 11),
  ('PALAVRA', 51, 'PIZZA', 11),
  ('PALAVRA', 52, 'DEFUMADO', 11),
  ('PALAVRA', 53, 'DEFUMADA', 11),
  ('PALAVRA', 54, 'CONGELADO', 11),
  ('PALAVRA', 55, 'CONGELADA', 11),
  ('PALAVRA', 56, 'SORVETE', 21),
  ('PALAVRA', 57, 'SORVETES', 21),
  ('PALAVRA', 58, 'DORALGINA', 3),
  ('PALAVRA', 59, 'REDOXON', 3),
  ('PALAVRA', 60, 'VITAMINA', 3),
  ('PALAVRA', 61, 'COMPRIMIDO', 3),
  ('PALAVRA', 62, 'DERMOCOSMETICO', 3),
  ('PALAVRA', 63, 'PROTETOR', 3),
  ('PALAVRA', 64, 'WHEY', 3),
  ('PALAVRA', 65, 'NUTRICAO', 3),
  ('PALAVRA', 66, 'MEDICAMENTO', 3),
  ('PALAVRA', 67, 'FARMACIA', 3),
  ('PALAVRA', 68, 'DROGARIA', 3),
  ('PALAVRA', 69, 'PARACETAMOL', 3),
  ('PALAVRA', 70, 'DIPIRONA', 3),
  ('PALAVRA', 71, 'CURATIVO', 3),
  ('PALAVRA', 72, 'REQUEIJAO', 6),
  ('PALAVRA', 73, 'EMBUTIDO', 6),
  ('PALAVRA', 74, 'LACTOSE', 6),
  ('PALAVRA', 75, 'PRESUNTO', 6),
  ('PALAVRA', 76, 'SALAME', 6),
  ('PALAVRA', 77, 'MUSSARELA', 16),
  ('PALAVRA', 78, 'MARGARINA', 16),
  ('PALAVRA', 79, 'MANTEIGA', 16),
  ('PALAVRA', 80, 'QUEIJO', 16),
  ('PALAVRA', 81, 'IOGURTE', 26),
  ('PALAVRA', 82, 'LACTEO', 26),
  ('PALAVRA', 83, 'LEITE', 26),
  ('PALAVRA', 84, 'PAMPERS', 7),
  ('PALAVRA', 85, 'FRALDA', 7),
  ('PALAVRA', 86, 'LISTERINE', 7),
  ('PALAVRA', 87, 'BUCAL', 7),
  ('PALAVRA', 88, 'DENTAL', 7),
  ('PALAVRA', 89, 'SABONACEO', 7),
  ('PALAVRA', 90, 'SABONETE', 7),
  ('PALAVRA', 91, 'MAQUIAGEM', 7),
  ('PALAVRA', 92, 'ABSORVENTE', 7),
  ('PALAVRA', 93, 'ELSEVE', 17),
  ('PALAVRA', 94, 'SHAMPOO', 17),
  ('PALAVRA', 95, 'CONDICIONADOR', 17),
  ('PALAVRA', 96, 'DESODORANTE', 17),
  ('PALAVRA', 97, 'BARBEAR', 17),
  ('PALAVRA', 98, 'HIGIENICO', 27),
  ('PALAVRA', 99, 'NEVE', 27),
  ('PALAVRA', 100, 'LENCO', 27),
  ('PALAVRA', 101, 'HIDRATANTE', 27),
  ('PALAVRA', 102, 'ALFACE', 9),
  ('PALAVRA', 103, 'ORGANICO', 9),
  ('PALAVRA', 104, 'VERDURA', 9),
  ('PALAVRA', 105, 'OVOS', 9),
  ('PALAVRA', 106, 'OVO', 9),
  ('PALAVRA', 107, 'REPOLHO', 9),
  ('PALAVRA', 108, 'CENOURA', 19),
  ('PALAVRA', 109, 'TOMATE', 19),
  ('PALAVRA', 110, 'LEGUME', 19),
  ('PALAVRA', 111, 'FRUTA', 19),
  ('PALAVRA', 112, 'BANANA', 19),
  ('PALAVRA', 113, 'MACA', 19),
  ('PALAVRA', 114, 'LARANJA', 19),
  ('PALAVRA', 115, 'LIMAO', 19),
  ('PALAVRA', 116, 'MAMAO', 19),
  ('PALAVRA', 117, 'MELANCIA', 19),
  ('PALAVRA', 118, 'BATATA', 19),
  ('PALAVRA', 119, 'CEBOLA', 19),
  ('PALAVRA', 120, 'ALHO', 19),
  ('PALAVRA', 121, 'CHUCHU', 19),
  ('PALAVRA', 122, 'ABOBRINHA', 19),
  ('PALAVRA', 123, 'RAID', 13),
  ('PALAVRA', 124, 'GLADE', 13),
  ('PALAVRA', 125, 'INSETICIDA', 13),
  ('PALAVRA', 126, 'PURIFICADOR', 13),
  ('PALAVRA', 127, 'FOGAO', 13),
  ('PALAVRA', 128, 'LAVANDERIA', 23),
  ('PALAVRA', 129, 'AMACIANTE', 23),
  ('PALAVRA', 130, 'VEJA', 23),
  ('PALAVRA', 131, 'LIMPADOR', 23),
  ('PALAVRA', 132, 'DETERGENTE', 23),
  ('PALAVRA', 133, 'SABAO', 23),
  ('PALAVRA', 134, 'SANITARIA', 23),
  ('PALAVRA', 135, 'ALCOOL', 23),
  ('PALAVRA', 136, 'DESINFETANTE', 23),
  ('PALAVRA', 137, 'ESPONJA', 23),
  ('PALAVRA', 138, 'LIXO', 23),
  ('PALAVRA', 139, 'PANO', 23),
  ('PALAVRA', 140, 'MOSTARDA', 5),
  ('PALAVRA', 141, 'MAIONESE', 5),
  ('PALAVRA', 142, 'AZEITE', 5),
  ('PALAVRA', 143, 'CONSERVA', 5),
  ('PALAVRA', 144, 'MILHO', 5),
  ('PALAVRA', 145, 'BISCOITO', 5),
  ('PALAVRA', 146, 'MOLHO', 5),
  ('PALAVRA', 147, 'TEMPERO', 5),
  ('PALAVRA', 148, 'KETCHUP', 5),
  ('PALAVRA', 149, 'SARDINHA', 5),
  ('PALAVRA', 150, 'ATUM', 5),
  ('PALAVRA', 151, 'GELATINA', 5),
  ('PALAVRA', 152, 'PUDIM', 5),
  ('PALAVRA', 153, 'CEREAL', 15),
  ('PALAVRA', 154, 'MATINAL', 15),
  ('PALAVRA', 155, 'CAFE', 15),
  ('PALAVRA', 156, 'AVEIA', 15),
  ('PALAVRA', 157, 'ESPAGUETE', 25),
  ('PALAVRA', 158, 'MACARRAO', 25),
  ('PALAVRA', 159, 'MASSA', 25),
  ('PALAVRA', 160, 'ARROZ', 25),
  ('PALAVRA', 161, 'FEIJAO', 25),
  ('PALAVRA', 162, 'ACUCAR', 25),
  ('PALAVRA', 163, 'FUBA', 25),
  ('PALAVRA', 164, 'WICKBOLD', 1),
  ('PALAVRA', 165, 'PAO', 1),
  ('PALAVRA', 166, 'PAES', 1),
  ('PALAVRA', 167, 'CONFEITARIA', 1),
  ('PALAVRA', 168, 'TORRADA', 1),
  ('PALAVRA', 169, 'MORDEDOR', 10),
  ('PALAVRA', 170, 'COLEIRA', 10),
  ('PALAVRA', 171, 'COMEDOURO', 10),
  ('PALAVRA', 172, 'PEDIGREE', 20),
  ('PALAVRA', 173, 'RACAO', 20),
  ('PALAVRA', 174, 'AUTOMOTIVO', 8),
  ('PALAVRA', 175, 'TILIBRA', 18),
  ('PALAVRA', 176, 'CADERNO', 18),
  ('PALAVRA', 177, 'PANELA', 18),
  ('PALAVRA', 178, 'COZINHA', 18),
  ('PALAVRA', 179, 'HAVAIANAS', 18),
  ('PALAVRA', 180, 'CHINELO', 18),
  ('PALAVRA', 181, 'CALCADO', 18),
  ('PALAVRA', 182, 'LUPO', 18),
  ('PALAVRA', 183, 'ROUPA', 18),
  ('PALAVRA', 184, 'LAMPADA', 18),
  ('PALAVRA', 185, 'PILHA', 18),
  ('PALAVRA', 186, 'FITA', 18),
  ('PALAVRA', 187, 'CANETA', 18),
  ('PALAVRA', 188, 'BRINQUEDO', 28),
  ('PALAVRA', 189, 'NUTRIPLAN', 30),
  ('PALAVRA', 190, 'PLANTEIRA', 30),
  ('PALAVRA', 191, 'PLANTA', 30),
  ('PALAVRA', 192, 'VASO', 30),
  ('PALAVRA', 193, 'KAIAK', 32),
  ('PALAVRA', 194, 'PERFUME', 32);

CREATE OR REPLACE FUNCTION categorizar(p_descricao TEXT) RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    WITH t AS (
        SELECT texto, regexp_split_to_array(texto, '[^A-Z0-9]+') AS palavras
          FROM (SELECT upper(unaccent(p_descricao)) AS texto) n
    )
    SELECT x.layout_id FROM (
        SELECT r.layout_id, 0 AS camada, r.ordem
          FROM categorizador_regra r, t
         WHERE r.tipo = 'FRASE' AND position(r.termo IN t.texto) > 0
        UNION ALL
        SELECT r.layout_id, 1 AS camada, r.ordem
          FROM categorizador_regra r, t
         WHERE r.tipo = 'PALAVRA' AND r.termo = ANY (t.palavras)
    ) x
    ORDER BY x.camada, x.ordem
    LIMIT 1
$$;

-- ---------------------------------------------------------------------------------------------
-- Pré-lista: vínculo só dos produtos indicados (a carga passa os novos e os de descrição
-- alterada). Sem parâmetro, recalcula todos, como antes (as chamadas antigas continuam valendo).
-- ---------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS vincular_produtos_pre_lista();
CREATE OR REPLACE FUNCTION vincular_produtos_pre_lista(p_ids BIGINT[] DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE produtos p
       SET pre_lista_item_id = (
            SELECT t.item_id
              FROM pre_lista_termo t
             WHERE upper(unaccent(p.descricao)) = t.termo
                OR upper(unaccent(p.descricao)) LIKE t.termo || ' %'
             ORDER BY length(t.termo) DESC
             LIMIT 1)
     WHERE p_ids IS NULL OR p.id = ANY (p_ids);
    RETURN (SELECT count(*) FROM produtos WHERE pre_lista_item_id IS NOT NULL);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Lojas e cargas
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS loja (
    id                    SERIAL PRIMARY KEY,
    nome                  VARCHAR(80) NOT NULL,
    -- SHA-256 (hex) da chave que o agente manda no cabeçalho X-Chave-Loja; a chave em si só
    -- existe no config.json do agente.
    chave_hash            CHAR(64)    NOT NULL UNIQUE,
    -- Minutos sem sinal de vida até o app esconder os preços. NULL = proteção desligada.
    limite_sem_sinal_min  INTEGER,
    ultimo_sinal_em       TIMESTAMPTZ,
    -- Hash do PRICETAB que o agente diz ter / do último que foi aplicado no banco. Diferentes =
    -- o app não sabe se o preço está certo.
    hash_informado        CHAR(64),
    hash_aplicado         CHAR(64),
    -- Problema em andamento já avisado por e-mail (NULL = tudo certo) e quando foi o último aviso.
    alerta_ativo          VARCHAR(40),
    alerta_enviado_em     TIMESTAMPTZ
);

-- Proteção começa DESLIGADA: o 017 liga depois que o agente fizer a primeira carga (senão o app
-- esconderia todos os preços entre o deploy e a instalação do agente).
INSERT INTO loja (id, nome, chave_hash, limite_sem_sinal_min)
VALUES (1, 'Supermercados ABC - loja piloto', 'b3e79976ae17ea5db557e2c3a7a408adf206c83ed89db514439a95d82ccaa8b0', NULL)
ON CONFLICT (id) DO NOTHING;
SELECT setval(pg_get_serial_sequence('loja', 'id'), (SELECT max(id) FROM loja));

CREATE TABLE IF NOT EXISTS carga_pricetab (
    id                    BIGSERIAL PRIMARY KEY,
    loja_id               INTEGER     NOT NULL REFERENCES loja(id),
    recebida_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
    hash                  CHAR(64)    NOT NULL,
    tamanho_bytes         INTEGER     NOT NULL,
    -- Arquivo original (Latin-1, como veio). Só as 30 últimas cargas de cada loja guardam o
    -- arquivo; das mais antigas fica só o resumo (ver CargaPricetabService.limparArquivosAntigos).
    arquivo               BYTEA,
    situacao              VARCHAR(10) NOT NULL DEFAULT 'RECEBIDA'
                          CHECK (situacao IN ('RECEBIDA', 'CONCLUIDA', 'RETIDA', 'ERRO', 'IGNORADA')),
    processada_em         TIMESTAMPTZ,
    linhas_total          INTEGER,
    linhas_invalidas      INTEGER,
    novos                 INTEGER,
    precos_alterados      INTEGER,
    descricoes_alteradas  INTEGER,
    inativados            INTEGER,
    reativados            INTEGER,
    mensagem              TEXT
);
CREATE INDEX IF NOT EXISTS carga_pricetab_loja_hash_idx ON carga_pricetab (loja_id, hash);
CREATE INDEX IF NOT EXISTS carga_pricetab_situacao_idx ON carga_pricetab (situacao);

-- ---------------------------------------------------------------------------------------------
-- Aplicação de uma carga. p_itens = [{"codigo":..,"descricao":..,"preco":..}, ...] já validado
-- pela API. Tudo numa transação (a da chamada): ou a carga entra inteira, ou nada muda.
-- Devolve as contagens; {"retida": true, ...} quando não aplicou por segurança.
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
BEGIN
    DROP TABLE IF EXISTS carga_itens;
    -- Código repetido no arquivo: vale a última linha.
    CREATE TEMP TABLE carga_itens ON COMMIT DROP AS
        SELECT DISTINCT ON (x.codigo) x.codigo, x.descricao, x.preco
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

    UPDATE produtos p SET ativo = true, atualizado_em = now()
      FROM carga_itens c
     WHERE c.codigo = p.codigo_barras AND NOT p.ativo;
    GET DIAGNOSTICS v_reativados = ROW_COUNT;

    UPDATE produtos p SET preco_centavos = c.preco, atualizado_em = now()
      FROM carga_itens c
     WHERE c.codigo = p.codigo_barras AND p.preco_centavos <> c.preco;
    GET DIAGNOSTICS v_precos = ROW_COUNT;

    -- Descrição mudou: recategoriza (menos quando a localização foi corrigida à mão).
    WITH alterados AS (
        UPDATE produtos p
           SET descricao = c.descricao, atualizado_em = now(),
               layout_id = CASE WHEN p.layout_manual THEN p.layout_id ELSE categorizar(c.descricao) END
          FROM carga_itens c
         WHERE c.codigo = p.codigo_barras AND p.descricao <> c.descricao
        RETURNING p.id)
    SELECT array_agg(id) INTO v_ids_descricao FROM alterados;

    -- Código só com dígitos e até 6 caracteres = código interno de produto de balança
    -- (hipótese até chegar um PRICETAB real; ver 015_produtos_pesaveis.sql).
    WITH novos AS (
        INSERT INTO produtos (codigo_barras, descricao, preco_centavos, layout_id, vendido_por_kg, ativo, atualizado_em)
        SELECT c.codigo, c.descricao, c.preco, categorizar(c.descricao), c.codigo ~ '^[0-9]{1,6}$', true, now()
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

    RETURN jsonb_build_object(
        'retida', false,
        'itens', v_itens,
        'novos', coalesce(array_length(v_ids_novos, 1), 0),
        'precosAlterados', v_precos,
        'descricoesAlteradas', coalesce(array_length(v_ids_descricao, 1), 0),
        'inativados', v_inativados,
        'reativados', v_reativados);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- Supabase expõe o schema public numa API REST pública (chave "anon"): RLS ligado sem política
-- bloqueia essa API em todas as tabelas (a chave da loja e os arquivos das cargas, sobretudo).
-- O back conecta como "postgres" (BYPASSRLS) e não é afetado. Ver 006_rls_produtos.sql.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE loja                ENABLE ROW LEVEL SECURITY;
ALTER TABLE carga_pricetab      ENABLE ROW LEVEL SECURITY;
ALTER TABLE categorizador_regra ENABLE ROW LEVEL SECURITY;
ALTER TABLE categorias_tags     ENABLE ROW LEVEL SECURITY;
ALTER TABLE layout_posicao      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pre_lista_categoria ENABLE ROW LEVEL SECURITY;
ALTER TABLE pre_lista_item      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pre_lista_termo     ENABLE ROW LEVEL SECURITY;
