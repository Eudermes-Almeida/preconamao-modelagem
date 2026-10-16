-- =============================================================================================
-- 042 — Desativar a chave do agente da loja pelo painel (pendência C5 do flyer TI)
-- =============================================================================================
-- "Como revogar o acesso? A chave da loja é desativada no painel de imediato." O painel /admin
-- (chave geral) ganha dois botões por loja:
--   * Desativar chave: o servidor passa a recusar a chave (401) em todos os envios do agente
--     (preços, sinal de vida, situação). A loja continua no app com os últimos preços.
--   * Gerar nova chave: troca o hash, desfaz a desativação e libera o registro do agente
--     (agente_id). A chave nova aparece UMA vez no painel; aqui só fica o SHA-256 dela.
-- Não há "reativar a mesma chave": se ela foi desativada por suspeita de vazamento, a volta é
-- sempre com uma chave nova.
-- =============================================================================================

ALTER TABLE loja ADD COLUMN IF NOT EXISTS chave_desativada_em TIMESTAMPTZ;

COMMENT ON COLUMN loja.chave_desativada_em IS
    'Quando a chave do agente foi desativada no painel; NULL = chave válida. Gerar nova chave volta para NULL.';
