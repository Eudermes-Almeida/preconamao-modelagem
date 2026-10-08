-- =============================================================================================
-- 034 — Agente RPInfo na loja + trava de queda de preço
-- =============================================================================================
-- Decidido em 08/10/2026 (laboratorio / Word "Integração RPInfo pelo Agente na loja", v2.2):
--   - formato "API RPInfo (agente)": a API da RPInfo é consultada pelo AGENTE dentro da loja, que
--     só envia pacotes JSON para POST /cargas/rpinfo (conexão de saída). O servidor NÃO coleta
--     essas lojas (parametros.coleta = AGENTE) e não usa credencial_api para elas.
--   - loja.pedir_completa: o servidor marca e o agente, ao enviar o sinal, recebe "fazer completa".
--   - loja.agente_id: só 1 agente por loja (o 1º que se identificar; trocar = limpar a coluna).
--   - Trava de QUEDA DE PREÇO (segurança R7): carga RETIDA se mais de queda_preco_limite (5%) dos
--     produtos ativos tiverem o preço efetivo derrubado em mais de queda_preco_minima (50%).
-- Reexecutável.
-- =============================================================================================

INSERT INTO formato_origem (nome, tipo, parametros, observacao) VALUES
  ('API RPInfo (agente)', 'API',
   '{"dialeto": "RPINFO", "coleta": "AGENTE", "tamanhoPagina": 100}',
   'RPInfo consultada pelo AGENTE na rede da loja (modo "rpinfo"); o agente envia pacotes JSON para POST /cargas/rpinfo. O servidor não coleta.')
ON CONFLICT (nome) DO UPDATE SET tipo = EXCLUDED.tipo, parametros = EXCLUDED.parametros, observacao = EXCLUDED.observacao;

ALTER TABLE loja ADD COLUMN IF NOT EXISTS pedir_completa BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS agente_id VARCHAR(80);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS queda_preco_limite NUMERIC(4,3) NOT NULL DEFAULT 0.05;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS queda_preco_minima NUMERIC(4,3) NOT NULL DEFAULT 0.50;

CREATE OR REPLACE FUNCTION aplicar_carga(p_loja_id INTEGER, p_itens JSONB, p_limite_inativacao NUMERIC, p_forcar BOOLEAN,
                                         p_internos JSONB DEFAULT NULL)
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
    -- Carga PARCIAL (coleta incremental): só os produtos do ERP em p_internos (códigos internos
    -- que mudaram, foram desativados ou excluídos) podem perder códigos; o resto fica como está.
    -- (NULL ou o JSON null = completa.)
    v_parcial        BOOLEAN := coalesce(jsonb_typeof(p_internos) = 'array', false);
    v_internos       TEXT[] := CASE WHEN jsonb_typeof(p_internos) = 'array'
                                    THEN ARRAY(SELECT jsonb_array_elements_text(p_internos)) ELSE '{}' END;
    -- Trava de queda de preço (scripts/034): fração dos produtos ativos e queda mínima por produto.
    v_queda_limite   NUMERIC := coalesce((SELECT queda_preco_limite FROM loja WHERE id = p_loja_id), 0.05);
    v_queda_minima   NUMERIC := coalesce((SELECT queda_preco_minima FROM loja WHERE id = p_loja_id), 0.50);
    v_quedas         INTEGER;
BEGIN
    DROP TABLE IF EXISTS carga_itens;
    CREATE TEMP TABLE carga_itens ON COMMIT DROP AS
        SELECT x.codigo, x."codigoOrigem" AS codigo_origem, x.descricao, x.preco,
               x."semPreco" AS sem_preco, x."descricaoCompleta" AS descricao_completa, x.secao,
               x.unidade, x.promocao, x."promocaoInicio" AS promocao_inicio, x."promocaoFim" AS promocao_fim,
               x.atacado, x."atacadoQuantidade" AS atacado_quantidade, x.condicao,
               x."codigoInterno" AS codigo_interno, CAST(NULL AS TEXT) AS expandida
          FROM jsonb_to_recordset(p_itens) AS x(codigo TEXT, "codigoOrigem" TEXT, descricao TEXT, preco INTEGER,
               "semPreco" TEXT, "descricaoCompleta" TEXT, secao TEXT, unidade TEXT, promocao INTEGER,
               "promocaoInicio" DATE, "promocaoFim" DATE, atacado INTEGER, "atacadoQuantidade" INTEGER,
               condicao TEXT, "codigoInterno" TEXT);
    CREATE INDEX ON carga_itens (codigo);

    SELECT count(*) INTO v_itens FROM carga_itens;
    SELECT count(*) INTO v_ativos FROM produtos WHERE loja_id = p_loja_id AND ativo;
    SELECT count(*) INTO v_sumiriam
      FROM produtos p
     WHERE p.loja_id = p_loja_id AND p.ativo
       AND (NOT v_parcial OR p.codigo_interno_origem = ANY (v_internos))
       AND NOT EXISTS (SELECT 1 FROM carga_itens c WHERE c.codigo = p.codigo_barras);

    IF (v_itens = 0 AND NOT v_parcial) OR (NOT p_forcar AND v_ativos > 0 AND v_sumiriam::NUMERIC / v_ativos > p_limite_inativacao) THEN
        RETURN jsonb_build_object('retida', true, 'motivo', 'INATIVACAO', 'itens', v_itens, 'ativos', v_ativos, 'sumiriam', v_sumiriam);
    END IF;

    -- Trava de QUEDA DE PREÇO (scripts/034, segurança R7): se muitos produtos ativos tiverem o preço
    -- efetivo (promoção válida hoje ou preço normal) derrubado de uma vez, a carga fica RETIDA. Uma
    -- promoção legítima num produto isolado não dispara; uma queda geral (invasão, erro em massa) sim.
    SELECT count(*) INTO v_quedas
      FROM produtos p JOIN carga_itens c ON c.codigo = p.codigo_barras
     WHERE p.loja_id = p_loja_id AND p.ativo
       AND (CASE WHEN p.promocao_centavos > 0 AND p.promocao_centavos < p.preco_centavos
                      AND current_date BETWEEN coalesce(p.promocao_inicio, current_date) AND coalesce(p.promocao_fim, current_date - 1)
                 THEN p.promocao_centavos ELSE p.preco_centavos END) > 0
       AND (CASE WHEN c.promocao > 0 AND c.promocao < c.preco
                      AND current_date BETWEEN coalesce(c.promocao_inicio, current_date) AND coalesce(c.promocao_fim, current_date - 1)
                 THEN c.promocao ELSE c.preco END)
           < (CASE WHEN p.promocao_centavos > 0 AND p.promocao_centavos < p.preco_centavos
                        AND current_date BETWEEN coalesce(p.promocao_inicio, current_date) AND coalesce(p.promocao_fim, current_date - 1)
                   THEN p.promocao_centavos ELSE p.preco_centavos END) * (1 - v_queda_minima);

    IF NOT p_forcar AND v_ativos > 0 AND v_quedas::NUMERIC / v_ativos > v_queda_limite THEN
        RETURN jsonb_build_object('retida', true, 'motivo', 'QUEDA_PRECO', 'itens', v_itens, 'ativos', v_ativos,
                                  'quedas', v_quedas, 'quedaMinima', v_queda_minima, 'quedaLimite', v_queda_limite);
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
           codigo_interno_origem = c.codigo_interno,
           promocao_centavos = c.promocao, promocao_inicio = c.promocao_inicio, promocao_fim = c.promocao_fim,
           atacado_centavos = c.atacado, atacado_quantidade = c.atacado_quantidade, condicao = left(c.condicao, 80)
      FROM carga_itens c
     WHERE p.loja_id = p_loja_id AND c.codigo = p.codigo_barras
       AND (p.sem_preco IS DISTINCT FROM c.sem_preco OR p.codigo_origem IS DISTINCT FROM c.codigo_origem
            OR p.codigo_interno_origem IS DISTINCT FROM c.codigo_interno
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
                              atacado_quantidade, condicao, codigo_interno_origem, ativo, atualizado_em)
        SELECT p_loja_id, c.codigo, c.codigo_origem, c.descricao, c.expandida, descricao_para_busca(c.expandida),
               c.preco, c.sem_preco, layout_do_produto(v_siglas, c.descricao, c.expandida, c.secao),
               eh_vendido_por_kg(c.codigo, c.descricao, c.unidade), codigo_balanca_de(c.codigo, p_loja_id), c.secao,
               c.unidade, c.promocao, c.promocao_inicio, c.promocao_fim, c.atacado, c.atacado_quantidade,
               left(c.condicao, 80), c.codigo_interno, true, now()
          FROM carga_itens c
         WHERE NOT EXISTS (SELECT 1 FROM produtos p WHERE p.loja_id = p_loja_id AND p.codigo_barras = c.codigo)
        RETURNING id)
    SELECT array_agg(id) INTO v_ids_novos FROM novos;

    UPDATE produtos p SET ativo = false, atualizado_em = now()
     WHERE p.loja_id = p_loja_id AND p.ativo
       AND (NOT v_parcial OR p.codigo_interno_origem = ANY (v_internos))
       AND NOT EXISTS (SELECT 1 FROM carga_itens c WHERE c.codigo = p.codigo_barras);
    GET DIAGNOSTICS v_inativados = ROW_COUNT;

    IF v_ids_descricao IS NOT NULL OR v_ids_novos IS NOT NULL THEN
        PERFORM vincular_produtos_pre_lista(coalesce(v_ids_descricao, '{}') || coalesce(v_ids_novos, '{}'));
    END IF;

    PERFORM agrupar_produtos(p_loja_id);

    RETURN jsonb_build_object(
        'retida', false,
        'parcial', v_parcial,
        'itens', v_itens,
        'novos', coalesce(array_length(v_ids_novos, 1), 0),
        'precosAlterados', v_precos,
        'descricoesAlteradas', v_descricoes,
        'inativados', v_inativados,
        'reativados', v_reativados);
END;
$$;
