-- "Família", 2ª etapa: aviso no celular (Web Push) quando chega uma lista ou quando alguém aceita
-- o convite, mesmo com o app fechado.
--
-- Cada aparelho que tocar em "Ativar avisos" gera, no navegador, uma inscrição no serviço de push
-- do próprio navegador (Google no Chrome/Android, Apple no iPhone com o app instalado, Mozilla no
-- Firefox). Aqui fica só o que é preciso para mandar o aviso: o endereço da inscrição e as duas
-- chaves públicas que cifram o conteúdo (só o aparelho consegue ler). Nenhum dado pessoal.
--
-- O mesmo membro pode ter mais de uma inscrição (ex.: Chrome e app instalado); uma inscrição que o
-- serviço de push responder como extinta (404/410) é apagada no envio.

CREATE TABLE IF NOT EXISTS familia_aviso_inscricao (
    id             BIGSERIAL    PRIMARY KEY,
    membro_id      BIGINT       NOT NULL REFERENCES familia_membro(id) ON DELETE CASCADE,
    endpoint       VARCHAR(1000) NOT NULL UNIQUE,
    p256dh         VARCHAR(120) NOT NULL,
    auth           VARCHAR(40)  NOT NULL,
    criado_em      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    atualizado_em  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS familia_aviso_inscricao_membro_idx ON familia_aviso_inscricao (membro_id);

-- Mesma regra do 016/018/019/020: a API REST pública do Supabase não enxerga nada; o back conecta como postgres.
ALTER TABLE familia_aviso_inscricao ENABLE ROW LEVEL SECURITY;
