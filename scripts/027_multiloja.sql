-- =============================================================================================
-- 027 — Multi-loja (regras de negócio decididas em 06/10/2026; documento
-- "Simplifica Compras - Regras de Negocio Multi-loja (DES).docx").
--
-- - Produto passa a ser da LOJA (loja_id + código canônico de 13 dígitos). A rede é só um
--   agrupamento comercial (ofertas, relatório, contrato), sem papel técnico.
-- - Cada loja aponta para um FORMATO (ficha de parâmetros da origem: PRICETAB de 40 ou de 16
--   posições, API) e para um DICIONÁRIO do catálogo; o dicionário tem camadas
--   loja > catálogo > comum (a mais específica vence). Siglas de seção (HF, PAD) são regras do
--   dicionário com layout_id: saem da descrição exibida e definem o setor.
-- - Configurações que eram do servidor passam para a loja: limite de inativação, layout da
--   etiqueta de balança, "liberar a próxima carga" (vale uma vez), proteção de preço.
-- - Arquivo recebido sai do banco (vai para o armazenamento; aqui fica só o caminho).
--
-- Reexecutável. NÃO cria as lojas do laboratório (ver 028, só DES). A loja 1 existente vira
-- PRICETAB de 40 posições com o dicionário PRICE2 (é a loja do PRICE2.TXT).
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Rede (agrupamento comercial)
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rede (
    id                    SERIAL PRIMARY KEY,
    nome                  VARCHAR(80) NOT NULL,
    slug                  VARCHAR(60) UNIQUE,
    -- Relatório consolidado do dono da rede (regra 6b); null = sem acesso de rede.
    chave_relatorio_hash  VARCHAR(64) UNIQUE
);
ALTER TABLE rede ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------------------------
-- Formato da origem (regra 8a): ficha de parâmetros lida por um leitor só.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS formato_origem (
    id          SERIAL PRIMARY KEY,
    nome        VARCHAR(60) NOT NULL UNIQUE,
    tipo        VARCHAR(10) NOT NULL CHECK (tipo IN ('PRICETAB', 'API')),
    -- PRICETAB: separador, tamanhoDescricao, descricaoCortada, emendarLinhas, codificacao,
    -- internoSemKgEhUnidade (sem "kg" na descrição, o produto interno é vendido por unidade;
    -- false = a origem não informa e o app avisa "preço de balança, confira na etiqueta").
    -- API: tamanhoPagina.
    parametros  JSONB NOT NULL DEFAULT '{}',
    observacao  TEXT
);
ALTER TABLE formato_origem ENABLE ROW LEVEL SECURITY;

INSERT INTO formato_origem (nome, tipo, parametros, observacao) VALUES
  ('PRICETAB 40 posições', 'PRICETAB',
   '{"separador": "|", "tamanhoDescricao": 40, "descricaoCortada": false, "emendarLinhas": true,
     "codificacao": "ISO-8859-1", "internoSemKgEhUnidade": true}',
   'CODIGO|DESCRICAO(40)|12,99| — PRICE2.TXT e PRICETABS.TXT. Preço em reais (ou centavos, arquivo simulado antigo).'),
  ('PRICETAB 16 posições', 'PRICETAB',
   '{"separador": "|", "tamanhoDescricao": 16, "descricaoCortada": true, "emendarLinhas": true,
     "codificacao": "ISO-8859-1", "internoSemKgEhUnidade": false}',
   'Descrição cortada em 16 posições (PRICETABF.TXT, PRICETABP.TXT): não agrupar por descrição, não expandir a última palavra.'),
  ('API simulada v1', 'API',
   '{"tamanhoPagina": 500}',
   'Laboratório: token + produtos em páginas (modelagem_dados_postgres/api_simulada).')
ON CONFLICT (nome) DO UPDATE SET tipo = EXCLUDED.tipo, parametros = EXCLUDED.parametros, observacao = EXCLUDED.observacao;

-- ---------------------------------------------------------------------------------------------
-- Dicionário em camadas (regras 8b, 9, 21)
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dicionario (
    id      SERIAL PRIMARY KEY,
    nome    VARCHAR(60) NOT NULL UNIQUE,
    camada  VARCHAR(10) NOT NULL CHECK (camada IN ('COMUM', 'CATALOGO', 'LOJA'))
);
ALTER TABLE dicionario ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS dicionario_um_comum ON dicionario ((camada)) WHERE camada = 'COMUM';

INSERT INTO dicionario (nome, camada) VALUES ('Comum', 'COMUM'), ('PRICE2', 'CATALOGO')
ON CONFLICT (nome) DO NOTHING;

-- As regras existentes (do PRICE2) passam para o dicionário PRICE2. A divisão em "comum" vem
-- depois, com aprovação (regra 9b).
ALTER TABLE abreviacao ADD COLUMN IF NOT EXISTS dicionario_id INTEGER REFERENCES dicionario(id);
-- Sigla de seção ("^HF" = hortifrúti): expansão vazia (sai da descrição) e o setor do mapa.
ALTER TABLE abreviacao ADD COLUMN IF NOT EXISTS layout_id BIGINT REFERENCES layout_posicao(id);
UPDATE abreviacao SET dicionario_id = (SELECT id FROM dicionario WHERE nome = 'PRICE2') WHERE dicionario_id IS NULL;
ALTER TABLE abreviacao ALTER COLUMN dicionario_id SET NOT NULL;
ALTER TABLE abreviacao ALTER COLUMN expansao DROP NOT NULL;
ALTER TABLE abreviacao DROP CONSTRAINT IF EXISTS abreviacao_termo_key;
-- Regra condicional (pedido do usuário, 06/10/2026): só vale quando a descrição TERMINA com 2
-- dígitos (o tamanho do calçado: "SAND HAV SLIM ... 37 38" = sandália). Null = vale sempre.
ALTER TABLE abreviacao ADD COLUMN IF NOT EXISTS condicao VARCHAR(20);
ALTER TABLE abreviacao DROP CONSTRAINT IF EXISTS abreviacao_condicao_check;
ALTER TABLE abreviacao ADD CONSTRAINT abreviacao_condicao_check CHECK (condicao IS NULL OR condicao IN ('FIM_NUMERO'));
DROP INDEX IF EXISTS abreviacao_dicionario_termo;
CREATE UNIQUE INDEX IF NOT EXISTS abreviacao_dicionario_termo_condicao ON abreviacao (dicionario_id, termo, coalesce(condicao, ''));

-- ---------------------------------------------------------------------------------------------
-- Loja: origem, catálogo e configurações que eram do servidor (regras 5, 11g, 20, 26)
-- ---------------------------------------------------------------------------------------------
ALTER TABLE loja ADD COLUMN IF NOT EXISTS rede_id INTEGER REFERENCES rede(id);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS tipo_origem VARCHAR(10) NOT NULL DEFAULT 'PRICETAB';
ALTER TABLE loja DROP CONSTRAINT IF EXISTS loja_tipo_origem_check;
ALTER TABLE loja ADD CONSTRAINT loja_tipo_origem_check CHECK (tipo_origem IN ('PRICETAB', 'API'));
ALTER TABLE loja ADD COLUMN IF NOT EXISTS formato_id INTEGER REFERENCES formato_origem(id);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS dicionario_id INTEGER REFERENCES dicionario(id);
-- Camada "loja" do dicionário (ajustes só desta loja); null = não tem.
ALTER TABLE loja ADD COLUMN IF NOT EXISTS dicionario_loja_id INTEGER REFERENCES dicionario(id);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS intervalo_coleta_min INTEGER;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS ativa BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS limite_inativacao NUMERIC(4,3) NOT NULL DEFAULT 0.20;
-- Regra 26b: vale para UMA carga; desliga sozinho depois de aplicada.
ALTER TABLE loja ADD COLUMN IF NOT EXISTS liberar_proxima_carga BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS liberada_por VARCHAR(60);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS liberada_em TIMESTAMPTZ;
-- Regra 11g: desde quando o arquivo da loja (hash_informado) difere do aplicado; null = iguais.
ALTER TABLE loja ADD COLUMN IF NOT EXISTS hash_divergente_desde TIMESTAMPTZ;
-- Regra 9d: dicionário mudou, recalcular descrições/setor/pré-lista desta loja.
ALTER TABLE loja ADD COLUMN IF NOT EXISTS reprocessar_dicionario BOOLEAN NOT NULL DEFAULT false;
-- Origem API: última coleta tentada (sucesso ou falha).
ALTER TABLE loja ADD COLUMN IF NOT EXISTS ultima_coleta_em TIMESTAMPTZ;
-- Etiqueta de balança (regras 5a e 20): posições a partir de 0 dentro do EAN-13.
ALTER TABLE loja ADD COLUMN IF NOT EXISTS etiqueta_prefixo VARCHAR(2) NOT NULL DEFAULT '2';
ALTER TABLE loja ADD COLUMN IF NOT EXISTS etiqueta_codigo_inicio INTEGER NOT NULL DEFAULT 1;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS etiqueta_codigo_tamanho INTEGER NOT NULL DEFAULT 6;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS etiqueta_valor_inicio INTEGER NOT NULL DEFAULT 7;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS etiqueta_valor_tamanho INTEGER NOT NULL DEFAULT 5;
-- O código interno do PRICETAB tem dígito verificador no fim (0000000040556 = 4055 + 6)?
ALTER TABLE loja ADD COLUMN IF NOT EXISTS etiqueta_interno_dv BOOLEAN NOT NULL DEFAULT true;

UPDATE loja SET formato_id = (SELECT id FROM formato_origem WHERE nome = 'PRICETAB 40 posições')
 WHERE formato_id IS NULL AND tipo_origem = 'PRICETAB';
-- Só lojas de PRICETAB: a loja de API usa a descrição da origem e não tem dicionário de catálogo
-- (regra 14) — sem esta condição, reexecutar o script devolveria o PRICE2 a ela.
UPDATE loja SET dicionario_id = (SELECT id FROM dicionario WHERE nome = 'PRICE2')
 WHERE dicionario_id IS NULL AND tipo_origem = 'PRICETAB';

-- ---------------------------------------------------------------------------------------------
-- Produtos por loja (regras 1, 17, 18, 19, 20, 4b)
-- ---------------------------------------------------------------------------------------------
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS loja_id INTEGER REFERENCES loja(id);
UPDATE produtos SET loja_id = 1 WHERE loja_id IS NULL;
ALTER TABLE produtos ALTER COLUMN loja_id SET NOT NULL;
-- Código como veio da origem (rastreio); codigo_barras passa a ser o canônico (13 dígitos).
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS codigo_origem VARCHAR(20);
-- Sem preço confiável por causa do dado: 'ZERO' (preço 0,00) ou 'CONFLITO' (código repetido com
-- preços diferentes). O app mostra "Consulte o preço no terminal de consulta da loja".
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS sem_preco VARCHAR(10);
-- Unidade informada pela origem (API): 'KG' / 'UN'; null = não informou.
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS unidade VARCHAR(2);
-- Seção informada pela origem (API, ou sigla do PRICETAB), só para conferência.
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS secao_origem VARCHAR(60);
-- Preço promocional da loja (vem da origem; o PRICETAB não traz).
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS promocao_centavos INTEGER;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS promocao_inicio DATE;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS promocao_fim DATE;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS atacado_centavos INTEGER;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS atacado_quantidade INTEGER;
-- "Leve 3, pague 2": só texto informativo, sem conta.
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS condicao VARCHAR(80);
ALTER TABLE produtos ALTER COLUMN descricao TYPE VARCHAR(120);

-- Código canônico (regra 17): sem os zeros da frente e completado até 13 dígitos; com 14 dígitos
-- sem zero na frente (código de caixa) fica como está.
CREATE OR REPLACE FUNCTION codigo_canonico(p_codigo TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN p_codigo IS NULL OR btrim(p_codigo) !~ '^[0-9]+$' THEN p_codigo
             WHEN length(ltrim(btrim(p_codigo), '0')) > 13 THEN ltrim(btrim(p_codigo), '0')
             ELSE lpad(ltrim(btrim(p_codigo), '0'), 13, '0')
           END
$$;

UPDATE produtos SET codigo_origem = codigo_barras WHERE codigo_origem IS NULL;
UPDATE produtos SET codigo_barras = codigo_canonico(codigo_barras) WHERE codigo_barras <> codigo_canonico(codigo_barras);

ALTER TABLE produtos DROP CONSTRAINT IF EXISTS uk_produtos_codigo_barras;
ALTER TABLE produtos DROP CONSTRAINT IF EXISTS ukdaeo2r0ngi2v5ejdny1pcus89;
ALTER TABLE produtos DROP CONSTRAINT IF EXISTS produtos_codigo_barras_key;
ALTER TABLE produtos DROP CONSTRAINT IF EXISTS produtos_loja_codigo_unico;
ALTER TABLE produtos ADD CONSTRAINT produtos_loja_codigo_unico UNIQUE (loja_id, codigo_barras);
CREATE INDEX IF NOT EXISTS produtos_loja_ativo_idx ON produtos (loja_id) WHERE ativo;
DROP INDEX IF EXISTS produtos_codigo_balanca_idx;
CREATE INDEX IF NOT EXISTS produtos_loja_codigo_balanca_idx ON produtos (loja_id, codigo_balanca) WHERE codigo_balanca IS NOT NULL;

-- ---------------------------------------------------------------------------------------------
-- Cargas: o arquivo sai do banco (regra 10); origem PRICETAB ou API; números das regras 18/19.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE carga_pricetab ADD COLUMN IF NOT EXISTS origem VARCHAR(10) NOT NULL DEFAULT 'PRICETAB';
ALTER TABLE carga_pricetab ADD COLUMN IF NOT EXISTS nome_arquivo VARCHAR(120);
-- Caminho no armazenamento (pasta local no DES, Supabase Storage privado em produção).
ALTER TABLE carga_pricetab ADD COLUMN IF NOT EXISTS caminho_arquivo VARCHAR(200);
ALTER TABLE carga_pricetab ADD COLUMN IF NOT EXISTS linhas_sem_preco INTEGER;
ALTER TABLE carga_pricetab ADD COLUMN IF NOT EXISTS codigos_repetidos INTEGER;
ALTER TABLE carga_pricetab ADD COLUMN IF NOT EXISTS conflitos_preco INTEGER;

-- ---------------------------------------------------------------------------------------------
-- Credencial da API da loja (regra 12b): o NOSSO servidor consulta a API do sistema da loja. A
-- senha/token fica cifrada (AES-GCM) pelo backend; a chave de cifra existe só na variável de
-- ambiente CREDENCIAIS_CHAVE do servidor — nunca no banco nem no git. Nunca aparece em log,
-- relatório ou resposta da API.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS credencial_api (
    loja_id          INTEGER PRIMARY KEY REFERENCES loja(id),
    url              VARCHAR(200) NOT NULL,
    usuario          VARCHAR(120) NOT NULL,
    segredo_cifrado  TEXT NOT NULL,
    atualizada_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE credencial_api ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------------------------
-- Campanhas de mídia (regra 4a): saem do código do app e vêm para o banco. A arte (paga pelo
-- fornecedor) aparece numa loja só se o produto existe ali, ativo e com preço acima de zero, e
-- mostra o preço DAQUELA loja. Alcance: TODAS as lojas, uma REDE ou LOJAS escolhidas
-- (campanha_loja). Validade de inicio a fim (fim null = sem fim). codigos = o produto exato da
-- arte em várias redes (vale o primeiro que a loja tiver). Cadastro por SQL por enquanto.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS campanha (
    id       SERIAL PRIMARY KEY,
    nome     VARCHAR(80) NOT NULL,
    arte     VARCHAR(160) NOT NULL,
    codigos  TEXT[] NOT NULL,
    inicio   DATE NOT NULL DEFAULT CURRENT_DATE,
    fim      DATE,
    alcance  VARCHAR(5) NOT NULL DEFAULT 'TODAS' CHECK (alcance IN ('TODAS', 'REDE', 'LOJAS')),
    rede_id  INTEGER REFERENCES rede(id),
    ativa    BOOLEAN NOT NULL DEFAULT true,
    ordem    INTEGER NOT NULL DEFAULT 0
);
ALTER TABLE campanha ENABLE ROW LEVEL SECURITY;
CREATE TABLE IF NOT EXISTS campanha_loja (
    campanha_id  INTEGER NOT NULL REFERENCES campanha(id) ON DELETE CASCADE,
    loja_id      INTEGER NOT NULL REFERENCES loja(id),
    PRIMARY KEY (campanha_id, loja_id)
);
ALTER TABLE campanha_loja ENABLE ROW LEVEL SECURITY;

-- As 21 artes que estavam no código do app (ofertas.service.ts), para todas as lojas.
INSERT INTO campanha (id, nome, arte, codigos, inicio, fim, alcance, rede_id, ordem) VALUES
  (1, 'oferta-7891095012596', 'assets/publicidade/oferta-7891095012596.png', '{7891095012596}', DATE '2026-10-01', NULL, 'TODAS', NULL, 1),
  (2, 'oferta-7891150027749', 'assets/publicidade/oferta-7891150027749.png', '{7891150027749}', DATE '2026-10-01', NULL, 'TODAS', NULL, 2),
  (3, 'oferta-7891150107533', 'assets/publicidade/oferta-7891150107533.png', '{7891150107533}', DATE '2026-10-01', NULL, 'TODAS', NULL, 3),
  (4, 'oferta-7894900011524', 'assets/publicidade/oferta-7894900011524.png', '{7894900011524,7894900530001,7896371000045,0000000402828}', DATE '2026-10-01', NULL, 'TODAS', NULL, 4),
  (5, 'oferta-7896004003901', 'assets/publicidade/oferta-7896004003901.png', '{7896004003901}', DATE '2026-10-01', NULL, 'TODAS', NULL, 5),
  (6, 'oferta-7896022204557', 'assets/publicidade/oferta-7896022204557.png', '{7896022204557,7896029022245}', DATE '2026-10-01', NULL, 'TODAS', NULL, 6),
  (7, 'oferta-7896022204571', 'assets/publicidade/oferta-7896022204571.png', '{7896022204571}', DATE '2026-10-01', NULL, 'TODAS', NULL, 7),
  (8, 'oferta-7896051111024', 'assets/publicidade/oferta-7896051111024.png', '{7896051111024}', DATE '2026-10-01', NULL, 'TODAS', NULL, 8),
  (9, 'oferta-7896051114024', 'assets/publicidade/oferta-7896051114024.png', '{7896051114024}', DATE '2026-10-01', NULL, 'TODAS', NULL, 9),
  (10, 'oferta-7898255671617', 'assets/publicidade/oferta-7898255671617.png', '{7898255671617,7891035210006,7891035210013,7891035210105,7891035210259}', DATE '2026-10-01', NULL, 'TODAS', NULL, 10),
  (11, 'oferta-0606529442514', 'assets/publicidade/oferta-0606529442514.png', '{0606529442514}', DATE '2026-10-01', NULL, 'TODAS', NULL, 11),
  (12, 'oferta-7500435154383', 'assets/publicidade/oferta-7500435154383.png', '{7500435154383}', DATE '2026-10-01', NULL, 'TODAS', NULL, 12),
  (13, 'oferta-7891150027800', 'assets/publicidade/oferta-7891150027800.png', '{7891150027800}', DATE '2026-10-01', NULL, 'TODAS', NULL, 13),
  (14, 'oferta-7891150044906', 'assets/publicidade/oferta-7891150044906.png', '{7891150044906}', DATE '2026-10-01', NULL, 'TODAS', NULL, 14),
  (15, 'oferta-7892840822408', 'assets/publicidade/oferta-7892840822408.png', '{7892840822408}', DATE '2026-10-01', NULL, 'TODAS', NULL, 15),
  (16, 'oferta-7894321811253', 'assets/publicidade/oferta-7894321811253.png', '{7894321811253}', DATE '2026-10-01', NULL, 'TODAS', NULL, 16),
  (17, 'oferta-7894900011715', 'assets/publicidade/oferta-7894900011715.png', '{7894900011715}', DATE '2026-10-01', NULL, 'TODAS', NULL, 17),
  (18, 'oferta-7896051145219', 'assets/publicidade/oferta-7896051145219.png', '{7896051145219}', DATE '2026-10-01', NULL, 'TODAS', NULL, 18),
  (19, 'oferta-7898347310486', 'assets/publicidade/oferta-7898347310486.png', '{7898347310486}', DATE '2026-10-01', NULL, 'TODAS', NULL, 19),
  (20, 'oferta-7899706187343', 'assets/publicidade/oferta-7899706187343.png', '{7899706187343}', DATE '2026-10-01', NULL, 'TODAS', NULL, 20),
  (21, 'oferta-9002490247379', 'assets/publicidade/oferta-9002490247379.png', '{9002490247379}', DATE '2026-10-01', NULL, 'TODAS', NULL, 21)
ON CONFLICT (id) DO NOTHING;
SELECT setval(pg_get_serial_sequence('campanha', 'id'), (SELECT max(id) FROM campanha));
UPDATE campanha SET codigos = ARRAY(SELECT codigo_canonico(c) FROM unnest(codigos) c) WHERE codigos <> ARRAY(SELECT codigo_canonico(c) FROM unnest(codigos) c);

-- ---------------------------------------------------------------------------------------------
-- Funções da carga, agora por loja
-- ---------------------------------------------------------------------------------------------

-- Dicionário efetivo da loja: as três camadas já resolvidas (loja > catálogo > comum), em JSON
-- termo -> expansão ('' = a regra apaga o termo: sigla de seção). Regra condicional entra com a
-- chave "termo#CONDICAO" (ex.: "^SAND#FIM_NUMERO"). Montado UMA vez por carga — com 27 mil
-- descrições, consultar as camadas palavra por palavra estourava o tempo da transação.
DROP FUNCTION IF EXISTS expansao_do_termo(INTEGER, TEXT);
CREATE OR REPLACE FUNCTION dicionario_da_loja(p_loja_id INTEGER) RETURNS JSONB
LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_object_agg(x.chave, x.expansao), '{}'::jsonb)
      FROM (SELECT DISTINCT ON (a.termo || coalesce('#' || a.condicao, ''))
                   a.termo || coalesce('#' || a.condicao, '') AS chave, coalesce(a.expansao, '') AS expansao
              FROM abreviacao a
              JOIN dicionario d ON d.id = a.dicionario_id
              JOIN loja l ON l.id = p_loja_id
             WHERE a.dicionario_id = l.dicionario_loja_id OR a.dicionario_id = l.dicionario_id OR d.camada = 'COMUM'
             ORDER BY a.termo || coalesce('#' || a.condicao, ''),
                      CASE WHEN a.dicionario_id = l.dicionario_loja_id THEN 1
                           WHEN a.dicionario_id = l.dicionario_id THEN 2 ELSE 3 END) x
$$;

-- Siglas de seção da loja (mesma precedência): termo -> layout_id.
CREATE OR REPLACE FUNCTION siglas_da_loja(p_loja_id INTEGER) RETURNS JSONB
LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_object_agg(x.termo, x.layout_id), '{}'::jsonb)
      FROM (SELECT DISTINCT ON (a.termo) a.termo, a.layout_id
              FROM abreviacao a
              JOIN dicionario d ON d.id = a.dicionario_id
              JOIN loja l ON l.id = p_loja_id
             WHERE a.layout_id IS NOT NULL
               AND (a.dicionario_id = l.dicionario_loja_id OR a.dicionario_id = l.dicionario_id OR d.camada = 'COMUM')
             ORDER BY a.termo, CASE WHEN a.dicionario_id = l.dicionario_loja_id THEN 1
                                    WHEN a.dicionario_id = l.dicionario_id THEN 2 ELSE 3 END) x
$$;

-- A loja recebe descrição cortada (PRICETAB de 16 posições)?
CREATE OR REPLACE FUNCTION loja_descricao_cortada(p_loja_id INTEGER) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT coalesce((f.parametros ->> 'descricaoCortada')::BOOLEAN, false)
      FROM loja l LEFT JOIN formato_origem f ON f.id = l.formato_id
     WHERE l.id = p_loja_id
$$;

-- Expande as abreviações de uma descrição, palavra por palavra, com o dicionário já montado.
-- "C/" e "S/" grudados viram COM / SEM antes. Em cada posição tenta o termo mais longo primeiro
-- (até 3 palavras). Regra que só vale na primeira palavra: termo com "^". Abreviação desconhecida
-- fica como veio (nunca rejeita — regra 9). Descrição cortada (p_cortada): a ÚLTIMA palavra de uma
-- descrição de 16+ posições não é expandida (pode estar pela metade — regra 22b). Descrição que
-- TERMINA com 2 dígitos ("... 37 38"): a regra condicional FIM_NUMERO do termo vem antes da comum.
CREATE OR REPLACE FUNCTION expandir_com_dicionario(p_descricao TEXT, p_dicionario JSONB, p_cortada BOOLEAN) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_palavras   TEXT[] := '{}';
    v_saida      TEXT[] := '{}';
    v_palavra    TEXT;
    v_chave      TEXT;
    v_expansao   TEXT;
    v_total      INTEGER;
    v_limite     INTEGER;
    v_i          INTEGER := 1;
    v_n          INTEGER;
    v_achou      BOOLEAN;
    v_fim_numero BOOLEAN;
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
    v_fim_numero := btrim(p_descricao) ~ '\s[0-9]{2}$';
    -- Palavras que podem ser expandidas (a última fica de fora na descrição cortada).
    v_limite := CASE WHEN p_cortada AND length(btrim(p_descricao)) >= 16 AND v_total > 1
                     THEN v_total - 1 ELSE v_total END;
    WHILE v_i <= v_total LOOP
        v_achou := false;
        IF v_i <= v_limite THEN
            FOR v_n IN REVERSE least(3, v_limite - v_i + 1)..1 LOOP
                v_chave := upper(array_to_string(v_palavras[v_i:v_i + v_n - 1], ' '));
                v_expansao := NULL;
                IF v_fim_numero AND v_i = 1 THEN
                    v_expansao := p_dicionario ->> ('^' || v_chave || '#FIM_NUMERO');
                END IF;
                IF v_expansao IS NULL AND v_fim_numero THEN
                    v_expansao := p_dicionario ->> (v_chave || '#FIM_NUMERO');
                END IF;
                IF v_expansao IS NULL AND v_i = 1 THEN
                    v_expansao := p_dicionario ->> ('^' || v_chave);
                END IF;
                IF v_expansao IS NULL THEN
                    v_expansao := p_dicionario ->> v_chave;
                END IF;
                IF v_expansao IS NOT NULL THEN
                    IF v_expansao <> '' THEN
                        v_saida := v_saida || v_expansao;
                    END IF;
                    v_i := v_i + v_n;
                    v_achou := true;
                    EXIT;
                END IF;
            END LOOP;
        END IF;
        IF NOT v_achou THEN
            v_saida := v_saida || v_palavras[v_i];
            v_i := v_i + 1;
        END IF;
    END LOOP;
    RETURN left(array_to_string(v_saida, ' '), 120);
END;
$$;

-- Atalho para conferir uma descrição só; as cargas montam o dicionário uma vez.
DROP FUNCTION IF EXISTS expandir_descricao(TEXT);
CREATE OR REPLACE FUNCTION expandir_descricao(p_descricao TEXT, p_loja_id INTEGER) RETURNS TEXT
LANGUAGE sql STABLE AS $$
    SELECT expandir_com_dicionario(p_descricao, dicionario_da_loja(p_loja_id), loja_descricao_cortada(p_loja_id))
$$;

-- Sigla de seção na PRIMEIRA palavra ("HF MORANGO" -> Hortifrúti), pelo dicionário da loja.
CREATE OR REPLACE FUNCTION layout_por_sigla(p_descricao TEXT, p_loja_id INTEGER) RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    SELECT a.layout_id
      FROM abreviacao a
      JOIN dicionario d ON d.id = a.dicionario_id
      JOIN loja l ON l.id = p_loja_id
     WHERE a.layout_id IS NOT NULL
       AND a.termo IN ('^' || upper(split_part(btrim(p_descricao), ' ', 1)), upper(split_part(btrim(p_descricao), ' ', 1)))
       AND (a.dicionario_id = l.dicionario_loja_id OR a.dicionario_id = l.dicionario_id OR d.camada = 'COMUM')
     ORDER BY CASE WHEN a.dicionario_id = l.dicionario_loja_id THEN 1
                   WHEN a.dicionario_id = l.dicionario_id THEN 2 ELSE 3 END
     LIMIT 1
$$;

-- Seção informada pela origem (API) -> setor do mapa: o primeiro setor cujo nome começa com ela
-- ("Hortifruti" -> "HORTIFRÚTI 1"). Sem correspondência: null (o categorizador decide).
CREATE OR REPLACE FUNCTION layout_por_secao(p_secao TEXT) RETURNS BIGINT
LANGUAGE sql STABLE AS $$
    SELECT id FROM layout_posicao
     WHERE p_secao IS NOT NULL AND btrim(p_secao) <> ''
       AND upper(unaccent(nome_setor)) LIKE upper(unaccent(btrim(p_secao))) || '%'
     ORDER BY id LIMIT 1
$$;

-- Código interno (balança ou produto da casa): 0000000CCCCCD, 2 a 7 dígitos significativos
-- (8 = EAN-8 completado com zeros, produto comum).
CREATE OR REPLACE FUNCTION eh_codigo_interno(p_codigo TEXT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_codigo ~ '^0000[0-9]{9}$' AND length(ltrim(p_codigo, '0')) BETWEEN 2 AND 7
$$;

-- Vendido por quilo (regra 20c): a unidade da origem manda; sem ela, código interno com "kg" na
-- descrição.
DROP FUNCTION IF EXISTS eh_vendido_por_kg(TEXT, TEXT);
CREATE OR REPLACE FUNCTION eh_vendido_por_kg(p_codigo TEXT, p_descricao TEXT, p_unidade TEXT DEFAULT NULL) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN p_unidade = 'KG' THEN true
             WHEN p_unidade = 'UN' THEN false
             ELSE eh_codigo_interno(p_codigo) AND p_descricao ~* '(^|\s)kg(\s|$)'
           END
$$;

-- O que a etiqueta da balança traz no lugar do produto (regra 20a): todo código interno, vendido
-- por quilo ou não, sem os zeros da frente e, se a loja diz que o interno tem dígito
-- verificador, sem o último dígito (0000000040556 -> 4055).
DROP FUNCTION IF EXISTS codigo_balanca_de(TEXT, TEXT);
CREATE OR REPLACE FUNCTION codigo_balanca_de(p_codigo TEXT, p_loja_id INTEGER) RETURNS TEXT
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN eh_codigo_interno(p_codigo) THEN
                CASE WHEN l.etiqueta_interno_dv
                     THEN left(ltrim(p_codigo, '0'), length(ltrim(p_codigo, '0')) - 1)
                     ELSE ltrim(p_codigo, '0') END
           END
      FROM loja l WHERE l.id = p_loja_id
$$;

-- Grupo (códigos auxiliares do mesmo produto: mesma descrição e mesmo preço) — por loja. Loja de
-- descrição cortada não agrupa (regra 22a): "REFRIG COCA COLA" seria Coca de todo tamanho.
DROP FUNCTION IF EXISTS agrupar_produtos();
CREATE OR REPLACE FUNCTION agrupar_produtos(p_loja_id INTEGER) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_alterados INTEGER;
BEGIN
    IF loja_descricao_cortada(p_loja_id) THEN
        UPDATE produtos SET grupo_codigo = codigo_barras
         WHERE loja_id = p_loja_id AND ativo AND grupo_codigo IS DISTINCT FROM codigo_barras;
        GET DIAGNOSTICS v_alterados = ROW_COUNT;
    ELSE
        UPDATE produtos p SET grupo_codigo = g.grupo
          FROM (SELECT id, min(codigo_barras) OVER (PARTITION BY descricao, preco_centavos) AS grupo
                  FROM produtos WHERE ativo AND loja_id = p_loja_id) g
         WHERE g.id = p.id AND p.grupo_codigo IS DISTINCT FROM g.grupo;
        GET DIAGNOSTICS v_alterados = ROW_COUNT;
    END IF;
    UPDATE produtos SET grupo_codigo = NULL WHERE loja_id = p_loja_id AND NOT ativo AND grupo_codigo IS NOT NULL;
    RETURN v_alterados;
END;
$$;

-- Setor do produto (regra 2): ajuste manual > seção da origem (API ou sigla) > categorizador.
-- p_siglas = siglas_da_loja(loja), montado uma vez por carga.
DROP FUNCTION IF EXISTS layout_do_produto(INTEGER, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION layout_do_produto(p_siglas JSONB, p_descricao TEXT, p_expandida TEXT, p_secao TEXT)
RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT coalesce(layout_por_secao(p_secao),
                    (p_siglas ->> ('^' || upper(split_part(btrim(p_descricao), ' ', 1))))::BIGINT,
                    (p_siglas ->> upper(split_part(btrim(p_descricao), ' ', 1)))::BIGINT,
                    categorizar(p_expandida))
$$;

-- ---------------------------------------------------------------------------------------------
-- Pré-lista (substitui a do 026): mesma regra (descrição expandida igual ao termo ou começando com
-- "termo "; "%" no termo vale qualquer trecho; o termo mais longo vence), mas cada produto só é
-- comparado com os termos da MESMA primeira palavra (índice), não com os ~400 — com 27 mil
-- produtos a comparação contra todos estourava o tempo da carga.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE pre_lista_termo ADD COLUMN IF NOT EXISTS primeira VARCHAR(60)
    GENERATED ALWAYS AS (split_part(termo, ' ', 1)) STORED;
CREATE INDEX IF NOT EXISTS pre_lista_termo_primeira_idx ON pre_lista_termo (primeira);

CREATE OR REPLACE FUNCTION vincular_produtos_pre_lista(p_ids BIGINT[] DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_alterados INTEGER;
BEGIN
    WITH alvo AS (
        SELECT p.id, upper(unaccent(coalesce(p.descricao_expandida, p.descricao))) AS texto
          FROM produtos p
         WHERE p_ids IS NULL OR p.id = ANY (p_ids)),
    escolha AS (
        SELECT a.id,
               (SELECT t.item_id
                  FROM pre_lista_termo t
                 WHERE (t.primeira = split_part(a.texto, ' ', 1) OR t.primeira LIKE '%\%%')
                   AND (a.texto LIKE t.termo OR a.texto LIKE t.termo || ' %')
                 ORDER BY length(t.termo) DESC
                 LIMIT 1) AS item
          FROM alvo a)
    UPDATE produtos p SET pre_lista_item_id = e.item
      FROM escolha e
     WHERE p.id = e.id AND p.pre_lista_item_id IS DISTINCT FROM e.item;
    GET DIAGNOSTICS v_alterados = ROW_COUNT;
    RETURN v_alterados;
END;
$$;

DROP FUNCTION IF EXISTS aplicar_carga_pricetab(JSONB, NUMERIC);
CREATE OR REPLACE FUNCTION aplicar_carga(p_loja_id INTEGER, p_itens JSONB, p_limite_inativacao NUMERIC, p_forcar BOOLEAN)
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
    v_dicionario     JSONB := dicionario_da_loja(p_loja_id);
    v_siglas         JSONB := siglas_da_loja(p_loja_id);
    v_cortada        BOOLEAN := loja_descricao_cortada(p_loja_id);
BEGIN
    DROP TABLE IF EXISTS carga_itens;
    CREATE TEMP TABLE carga_itens ON COMMIT DROP AS
        SELECT x.codigo, x."codigoOrigem" AS codigo_origem, x.descricao, x.preco,
               x."semPreco" AS sem_preco, x."descricaoCompleta" AS descricao_completa, x.secao,
               x.unidade, x.promocao, x."promocaoInicio" AS promocao_inicio, x."promocaoFim" AS promocao_fim,
               x.atacado, x."atacadoQuantidade" AS atacado_quantidade, x.condicao,
               CAST(NULL AS TEXT) AS expandida
          FROM jsonb_to_recordset(p_itens) AS x(codigo TEXT, "codigoOrigem" TEXT, descricao TEXT, preco INTEGER,
               "semPreco" TEXT, "descricaoCompleta" TEXT, secao TEXT, unidade TEXT, promocao INTEGER,
               "promocaoInicio" DATE, "promocaoFim" DATE, atacado INTEGER, "atacadoQuantidade" INTEGER,
               condicao TEXT);
    CREATE INDEX ON carga_itens (codigo);

    SELECT count(*) INTO v_itens FROM carga_itens;
    SELECT count(*) INTO v_ativos FROM produtos WHERE loja_id = p_loja_id AND ativo;
    SELECT count(*) INTO v_sumiriam
      FROM produtos p
     WHERE p.loja_id = p_loja_id AND p.ativo
       AND NOT EXISTS (SELECT 1 FROM carga_itens c WHERE c.codigo = p.codigo_barras);

    IF v_itens = 0 OR (NOT p_forcar AND v_ativos > 0 AND v_sumiriam::NUMERIC / v_ativos > p_limite_inativacao) THEN
        RETURN jsonb_build_object('retida', true, 'itens', v_itens, 'ativos', v_ativos, 'sumiriam', v_sumiriam);
    END IF;

    -- Descrição completa da origem vale mais que a expansão (regra 14); senão uma expansão por
    -- descrição distinta.
    -- (só a camada comum se aplica a ela: a loja de API não tem dicionário de catálogo — regra 14).
    UPDATE carga_itens SET expandida = expandir_com_dicionario(left(upper(unaccent(descricao_completa)), 120), v_dicionario, false)
     WHERE descricao_completa IS NOT NULL;
    UPDATE carga_itens c SET expandida = e.expandida
      FROM (SELECT d.descricao, expandir_com_dicionario(d.descricao, v_dicionario, v_cortada) AS expandida
              FROM (SELECT DISTINCT descricao FROM carga_itens WHERE descricao_completa IS NULL) d) e
     WHERE e.descricao = c.descricao AND c.descricao_completa IS NULL;

    UPDATE produtos p SET ativo = true, atualizado_em = now()
      FROM carga_itens c
     WHERE p.loja_id = p_loja_id AND c.codigo = p.codigo_barras AND NOT p.ativo;
    GET DIAGNOSTICS v_reativados = ROW_COUNT;

    UPDATE produtos p SET preco_centavos = c.preco, atualizado_em = now()
      FROM carga_itens c
     WHERE p.loja_id = p_loja_id AND c.codigo = p.codigo_barras AND p.preco_centavos <> c.preco;
    GET DIAGNOSTICS v_precos = ROW_COUNT;

    -- Campos que vêm a cada carga, sem contar como "alteração".
    UPDATE produtos p
       SET sem_preco = c.sem_preco, codigo_origem = c.codigo_origem, unidade = c.unidade,
           promocao_centavos = c.promocao, promocao_inicio = c.promocao_inicio, promocao_fim = c.promocao_fim,
           atacado_centavos = c.atacado, atacado_quantidade = c.atacado_quantidade, condicao = left(c.condicao, 80)
      FROM carga_itens c
     WHERE p.loja_id = p_loja_id AND c.codigo = p.codigo_barras
       AND (p.sem_preco IS DISTINCT FROM c.sem_preco OR p.codigo_origem IS DISTINCT FROM c.codigo_origem
            OR p.unidade IS DISTINCT FROM c.unidade OR p.promocao_centavos IS DISTINCT FROM c.promocao
            OR p.promocao_inicio IS DISTINCT FROM c.promocao_inicio OR p.promocao_fim IS DISTINCT FROM c.promocao_fim
            OR p.atacado_centavos IS DISTINCT FROM c.atacado OR p.atacado_quantidade IS DISTINCT FROM c.atacado_quantidade
            OR p.condicao IS DISTINCT FROM left(c.condicao, 80));

    SELECT count(*) INTO v_descricoes
      FROM produtos p JOIN carga_itens c ON c.codigo = p.codigo_barras
     WHERE p.loja_id = p_loja_id AND p.descricao <> c.descricao;

    WITH alterados AS (
        UPDATE produtos p
           SET descricao = c.descricao,
               descricao_expandida = c.expandida,
               descricao_busca = descricao_para_busca(c.expandida),
               secao_origem = c.secao,
               vendido_por_kg = eh_vendido_por_kg(c.codigo, c.descricao, c.unidade),
               codigo_balanca = codigo_balanca_de(c.codigo, p_loja_id),
               atualizado_em = CASE WHEN p.descricao <> c.descricao THEN now() ELSE p.atualizado_em END,
               layout_id = CASE WHEN p.layout_manual THEN p.layout_id
                                ELSE layout_do_produto(v_siglas, c.descricao, c.expandida, c.secao) END
          FROM carga_itens c
         WHERE p.loja_id = p_loja_id AND c.codigo = p.codigo_barras
           AND (p.descricao <> c.descricao OR p.descricao_expandida IS DISTINCT FROM c.expandida
                OR p.secao_origem IS DISTINCT FROM c.secao OR p.vendido_por_kg <> eh_vendido_por_kg(c.codigo, c.descricao, c.unidade))
        RETURNING p.id)
    SELECT array_agg(id) INTO v_ids_descricao FROM alterados;

    WITH novos AS (
        INSERT INTO produtos (loja_id, codigo_barras, codigo_origem, descricao, descricao_expandida, descricao_busca,
                              preco_centavos, sem_preco, layout_id, vendido_por_kg, codigo_balanca, secao_origem,
                              unidade, promocao_centavos, promocao_inicio, promocao_fim, atacado_centavos,
                              atacado_quantidade, condicao, ativo, atualizado_em)
        SELECT p_loja_id, c.codigo, c.codigo_origem, c.descricao, c.expandida, descricao_para_busca(c.expandida),
               c.preco, c.sem_preco, layout_do_produto(v_siglas, c.descricao, c.expandida, c.secao),
               eh_vendido_por_kg(c.codigo, c.descricao, c.unidade), codigo_balanca_de(c.codigo, p_loja_id), c.secao,
               c.unidade, c.promocao, c.promocao_inicio, c.promocao_fim, c.atacado, c.atacado_quantidade,
               left(c.condicao, 80), true, now()
          FROM carga_itens c
         WHERE NOT EXISTS (SELECT 1 FROM produtos p WHERE p.loja_id = p_loja_id AND p.codigo_barras = c.codigo)
        RETURNING id)
    SELECT array_agg(id) INTO v_ids_novos FROM novos;

    UPDATE produtos p SET ativo = false, atualizado_em = now()
     WHERE p.loja_id = p_loja_id AND p.ativo
       AND NOT EXISTS (SELECT 1 FROM carga_itens c WHERE c.codigo = p.codigo_barras);
    GET DIAGNOSTICS v_inativados = ROW_COUNT;

    IF v_ids_descricao IS NOT NULL OR v_ids_novos IS NOT NULL THEN
        PERFORM vincular_produtos_pre_lista(coalesce(v_ids_descricao, '{}') || coalesce(v_ids_novos, '{}'));
    END IF;

    PERFORM agrupar_produtos(p_loja_id);

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
-- Regra 9d: dicionário alterado -> a loja é marcada e o backend reprocessa (sem esperar carga).
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reprocessar_descricoes(p_loja_id INTEGER) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_ids         BIGINT[];
    v_dicionario  JSONB := dicionario_da_loja(p_loja_id);
    v_siglas      JSONB := siglas_da_loja(p_loja_id);
    v_cortada     BOOLEAN := loja_descricao_cortada(p_loja_id);
    -- Loja de API: a descrição já veio completa da origem — mesmo tratamento da carga (maiúsculas,
    -- sem acento, só a camada comum), não a expansão de abreviações do PRICETAB.
    v_api         BOOLEAN := (SELECT tipo_origem = 'API' FROM loja WHERE id = p_loja_id);
BEGIN
    WITH novas AS (
        SELECT d.descricao, expandir_com_dicionario(CASE WHEN v_api THEN left(upper(unaccent(d.descricao)), 120)
                                                         ELSE d.descricao END, v_dicionario, v_cortada) AS expandida
          FROM (SELECT DISTINCT descricao FROM produtos WHERE loja_id = p_loja_id) d),
    alterados AS (
        UPDATE produtos p
           SET descricao_expandida = n.expandida,
               descricao_busca = descricao_para_busca(n.expandida),
               layout_id = CASE WHEN p.layout_manual THEN p.layout_id
                                ELSE layout_do_produto(v_siglas, p.descricao, n.expandida, p.secao_origem) END
          FROM novas n
         WHERE p.loja_id = p_loja_id AND n.descricao = p.descricao
           AND (p.descricao_expandida IS DISTINCT FROM n.expandida
                OR (NOT p.layout_manual AND p.layout_id IS DISTINCT FROM layout_do_produto(v_siglas, p.descricao, n.expandida, p.secao_origem)))
        RETURNING p.id)
    SELECT array_agg(id) INTO v_ids FROM alterados;
    IF v_ids IS NOT NULL THEN
        PERFORM vincular_produtos_pre_lista(v_ids);
    END IF;
    UPDATE loja SET reprocessar_dicionario = false WHERE id = p_loja_id;
    RETURN coalesce(array_length(v_ids, 1), 0);
END;
$$;

CREATE OR REPLACE FUNCTION marcar_lojas_do_dicionario() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_dicionario INTEGER := CASE WHEN TG_OP = 'DELETE' THEN OLD.dicionario_id ELSE NEW.dicionario_id END;
BEGIN
    UPDATE loja l SET reprocessar_dicionario = true
     WHERE NOT l.reprocessar_dicionario
       AND (l.dicionario_id = v_dicionario OR l.dicionario_loja_id = v_dicionario
            OR EXISTS (SELECT 1 FROM dicionario d WHERE d.id = v_dicionario AND d.camada = 'COMUM'));
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS abreviacao_marca_lojas ON abreviacao;
CREATE TRIGGER abreviacao_marca_lojas AFTER INSERT OR UPDATE OR DELETE ON abreviacao
    FOR EACH ROW EXECUTE FUNCTION marcar_lojas_do_dicionario();

-- ---------------------------------------------------------------------------------------------
-- Produtos já cadastrados (loja 1): recalcula com as funções novas.
-- ---------------------------------------------------------------------------------------------
UPDATE produtos SET codigo_balanca = codigo_balanca_de(codigo_barras, loja_id),
                    vendido_por_kg = eh_vendido_por_kg(codigo_barras, descricao, unidade);
SELECT reprocessar_descricoes(id) FROM loja;
SELECT agrupar_produtos(id) FROM loja;
