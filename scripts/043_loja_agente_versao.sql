-- =============================================================================================
-- 043 — Versão do agente de cada loja (pendência C7 do flyer TI: fluxo de nova versão)
-- =============================================================================================
-- O agente (2.5 em diante) manda a versão no cabeçalho X-Versao-Agente de todo envio; o servidor
-- guarda a última aqui e o painel /admin mostra "agente 2.5", marcando "versão antiga" quando a
-- loja está abaixo da versão atual (agente.versao-atual no application.properties do backend).
-- Não há atualização automática: a versão nova é entregue à TI, que instala quando decidir.
-- Agente antigo (sem o cabeçalho) continua aceito; a versão fica vazia.
-- =============================================================================================

ALTER TABLE loja ADD COLUMN IF NOT EXISTS agente_versao    VARCHAR(20);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS agente_versao_em TIMESTAMPTZ;

COMMENT ON COLUMN loja.agente_versao IS 'Versão informada pelo agente no último envio (X-Versao-Agente); NULL = agente anterior à 2.5.';
COMMENT ON COLUMN loja.agente_versao_em IS 'Quando o agente informou essa versão pela primeira vez.';
