-- =============================================================================================
-- 037 — Conector de banco de dados (agente na loja lendo uma VIEW no banco do ERP)
-- =============================================================================================
-- Caminho 3 de integração (flyers e apresentação): a TI da loja cria no banco do ERP a VIEW
-- padrão vw_simplifica_precos (contrato: laboratorio/conector_banco/CONTRATO_VIEW.md) e um
-- usuário que só tem SELECT nela. O agente (modo "banco", ODBC) lê a VIEW DENTRO da loja e envia
-- os pacotes para POST /cargas/banco — mesmo fluxo do agente RPInfo (completa + incremental, foto
-- local, fila, travas de 20% e de queda de preço). O servidor não acessa o banco da loja.
-- Reexecutável.
-- =============================================================================================

INSERT INTO formato_origem (nome, tipo, parametros, observacao) VALUES
  ('Banco de dados (agente)', 'API',
   '{"dialeto": "VIEW_PADRAO", "coleta": "AGENTE"}',
   'Banco do ERP lido pelo AGENTE na rede da loja (modo "banco", ODBC) na VIEW padrão vw_simplifica_precos; o agente envia pacotes JSON para POST /cargas/banco. O servidor não acessa o banco.')
ON CONFLICT (nome) DO UPDATE SET tipo = EXCLUDED.tipo, parametros = EXCLUDED.parametros, observacao = EXCLUDED.observacao;
