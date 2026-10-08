-- =============================================================================================
-- 031 — Coleta pela API da RPInfo ("RP Services")
-- =============================================================================================
-- A coleta por API (regra 12) passa a falar "dialetos": cada ERP tem rotas, autenticação e
-- campos próprios. O dialeto fica na ficha do formato (formato_origem.parametros.dialeto):
--   SIMPLES = API simulada v1 do laboratório (token Bearer + páginas numeradas);
--   RPINFO  = API real da RPInfo (token no cabeçalho "token", produtos paginados pelo último
--             Codigo, unidade da loja identificada pelo CNPJ).
-- A credencial ganha "unidade": como a loja é identificada DENTRO do sistema de gestão (RPInfo:
-- CNPJ da unidade). Não é segredo (fica em texto, ao contrário da senha).
-- Reexecutável.
-- =============================================================================================

ALTER TABLE credencial_api ADD COLUMN IF NOT EXISTS unidade VARCHAR(40);

INSERT INTO formato_origem (nome, tipo, parametros, observacao) VALUES
  ('API simulada v1', 'API',
   '{"dialeto": "SIMPLES", "tamanhoPagina": 500}',
   'Laboratório: token + produtos em páginas (modelagem_dados_postgres/api_simulada/servidor.js).'),
  ('API RPInfo', 'API',
   '{"dialeto": "RPINFO", "tamanhoPagina": 100}',
   'RPInfo "RP Services": POST /v1.2/auth; GET /v3.2/produtounidade/listaprodutos/{lastID}/unidade/{CNPJ}/detalhado/ativos; '
   'GET /v1.1/departamentos. Preço = PrecoPDV (o do caixa); oferta só dentro da validade (DataOferta).')
ON CONFLICT (nome) DO UPDATE SET tipo = EXCLUDED.tipo, parametros = EXCLUDED.parametros, observacao = EXCLUDED.observacao;
