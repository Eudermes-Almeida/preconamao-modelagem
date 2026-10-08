-- =============================================================================================
-- 032 — SÓ DES (laboratório): loja 5 "Alfa Online" passa a usar a API simulada RPInfo
-- =============================================================================================
-- NÃO aplicar em produção. A loja 5 sai da API simulada v1 (porta 18090) e vai para a API simulada
-- no formato real da RPInfo (porta 18091, api_simulada/servidor_rpinfo.js). A URL e a unidade
-- (CNPJ fictício da unidade 001 do simulador) ficam na credencial; usuário e senha continuam os do
-- laboratório e são gravados pelo PUT /admin/lojas/5/credencial-api (senha cifrada no servidor).
-- Os produtos da loja 5 saem para a 1ª carga entrar inteira pelo caminho novo (regra 28a).
-- Atenção ao reaplicar: se a API devolver o MESMO conteúdo da última carga, a coleta responde
-- "Mesmos dados da carga nº …" e não recarrega (proteção contra reprocessar). Para forçar:
-- /lab/mudar-preco num produto → coletar → /lab/reiniciar → coletar.
-- Voltar para a v1: formato 'API simulada v1', url http://127.0.0.1:18090 e unidade NULL.
-- =============================================================================================

-- Na RPInfo o código interno do pesável vem COM dígito verificador (0000000002189 = 218 + 9; resposta
-- 14 da homologação), como nas lojas 1 a 4: a etiqueta da balança traz o código sem o dígito.
UPDATE loja SET formato_id = (SELECT id FROM formato_origem WHERE nome = 'API RPInfo'), etiqueta_interno_dv = true,
       hash_aplicado = NULL, hash_informado = NULL, hash_divergente_desde = NULL, ultima_coleta_em = NULL,
       liberar_proxima_carga = false
 WHERE id = 5 AND nome = 'Alfa Online';

UPDATE credencial_api SET url = 'http://127.0.0.1:18091', unidade = '11222333000181', atualizada_em = now()
 WHERE loja_id = 5;

DELETE FROM produtos WHERE loja_id = 5;
