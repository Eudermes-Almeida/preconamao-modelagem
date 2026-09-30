-- Instalações do app na tela inicial do celular (botão "Instalar o app"), para o relatório da aba
-- administrativa (/admin). Os mesmos registros vão para o Google Analytics 4 (evento app_instalado).
--
-- Uma linha por aparelho e loja: reinstalar no mesmo aparelho não conta de novo. No iPhone o app
-- instalado não enxerga os dados do Safari, então lá ele ganha um aparelho_id novo (conta uma vez,
-- na primeira abertura pelo ícone).
--
-- origem:     BOTAO     o cliente aceitou a janela de instalação aberta pelo nosso botão
--             NAVEGADOR instalou pelo menu do navegador, ou só percebemos na 1ª abertura pelo ícone
-- plataforma: ANDROID, IOS ou OUTRA (computador etc.), deduzida do navegador.

CREATE TABLE IF NOT EXISTS instalacao_app (
    id             BIGSERIAL   PRIMARY KEY,
    loja_id        INTEGER     NOT NULL REFERENCES loja(id),
    aparelho_id    UUID        NOT NULL,
    origem         VARCHAR(10) NOT NULL CHECK (origem IN ('BOTAO', 'NAVEGADOR')),
    plataforma     VARCHAR(10) NOT NULL CHECK (plataforma IN ('ANDROID', 'IOS', 'OUTRA')),
    registrado_em  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT instalacao_app_loja_aparelho_uk UNIQUE (loja_id, aparelho_id)
);

CREATE INDEX IF NOT EXISTS instalacao_app_loja_data_idx ON instalacao_app (loja_id, registrado_em);

-- Mesma regra do 016/018: a API REST pública do Supabase não enxerga nada; o back conecta como postgres.
ALTER TABLE instalacao_app ENABLE ROW LEVEL SECURITY;
