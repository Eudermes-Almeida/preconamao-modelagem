-- =============================================================================================
-- 035 — SÓ DES (laboratório): loja 5 "Alfa Online" passa a ser alimentada pelo AGENTE (modo rpinfo)
-- =============================================================================================
-- NÃO aplicar em produção. O agente (laboratorio/agente_rpinfo) roda no computador do laboratório,
-- consulta o simulador RPInfo (http://127.0.0.1:18091) como se fosse a "API interna da loja" e
-- envia os pacotes para o DES (POST /cargas/rpinfo) com a chave da loja 5.
--   - formato 'API RPInfo (agente)': o servidor para de coletar a loja 5;
--   - a credencial da API da loja 5 sai do servidor (passa a existir só no agente);
--   - agente_id limpo (o 1º agente que se identificar fica registrado).
-- Os produtos NÃO são apagados: a 1ª completa do agente substitui o conteúdo (códigos internos iguais).
-- Voltar para a coleta pelo servidor: aplicar de novo o 032 e regravar a credencial.
-- =============================================================================================

UPDATE loja SET formato_id = (SELECT id FROM formato_origem WHERE nome = 'API RPInfo (agente)'),
       agente_id = NULL, pedir_completa = false
 WHERE id = 5 AND nome = 'Alfa Online';

DELETE FROM credencial_api WHERE loja_id = 5;
