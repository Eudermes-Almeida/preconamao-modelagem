-- =============================================================================================
-- 038 — SÓ DES (laboratório): loja 6 "Delta Banco", alimentada pelo conector de banco
-- =============================================================================================
-- NÃO aplicar em produção. O "ERP" é o MySQL do laboratório (container erp-mysql-lab, porta 13306,
-- banco erp_lab, VIEW vw_simplifica_precos com os produtos do PRICE2; ver
-- laboratorio/conector_banco). O agente (modo "banco") roda no computador do laboratório e envia
-- para o DES com a chave da loja 6 (laboratorio/chaves_lab.json).
-- A loja nasce como cópia da loja 5 (mesma rede e dicionário PRICE2), sem produtos: a 1ª carga
-- completa do agente preenche tudo.
-- =============================================================================================

INSERT INTO loja (id, nome, chave_hash, limite_sem_sinal_min, chave_relatorio_hash, slug, nome_curto, latitude, longitude,
                  raio_m, raio_saida_m, rede_id, tipo_origem, formato_id, dicionario_id, dicionario_loja_id,
                  intervalo_coleta_min, ativa, limite_inativacao, etiqueta_prefixo, etiqueta_codigo_inicio,
                  etiqueta_codigo_tamanho, etiqueta_valor_inicio, etiqueta_valor_tamanho, etiqueta_interno_dv,
                  queda_preco_limite, queda_preco_minima)
SELECT 6, 'Delta Banco', encode(sha256(convert_to('lab-delta-banco-6-chave', 'UTF8')), 'hex'), 15, chave_relatorio_hash,
       'delta-banco', 'Delta', latitude + 0.01, longitude + 0.01,
       raio_m, raio_saida_m, rede_id, 'API', (SELECT id FROM formato_origem WHERE nome = 'Banco de dados (agente)'),
       dicionario_id, NULL, intervalo_coleta_min, true, limite_inativacao, etiqueta_prefixo, etiqueta_codigo_inicio,
       etiqueta_codigo_tamanho, etiqueta_valor_inicio, etiqueta_valor_tamanho, etiqueta_interno_dv,
       queda_preco_limite, queda_preco_minima
  FROM loja WHERE id = 5
ON CONFLICT (id) DO UPDATE SET formato_id = EXCLUDED.formato_id, tipo_origem = 'API', agente_id = NULL, pedir_completa = false;

SELECT setval(pg_get_serial_sequence('loja', 'id'), greatest((SELECT max(id) FROM loja), 6));
