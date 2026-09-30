-- "Família": um celular manda itens da pré-lista para outro (ex.: a esposa, em casa, manda o que
-- falta para o marido que está no mercado). Sem cadastro e sem dado pessoal além do primeiro nome
-- que a própria pessoa digita.
--
-- Cada aparelho gera uma chave secreta no navegador (localStorage) e manda no cabeçalho
-- X-Chave-Familia; aqui só fica o hash SHA-256 (familia_membro). O membro só é criado quando a
-- pessoa usa a Família pela primeira vez.
--
-- Ligação: um convite (link do WhatsApp ou código de 8 caracteres), de uso único e válido por
-- 7 dias. Aceito, a ligação vale nos DOIS sentidos: duas linhas em familia_contato, cada uma com
-- o apelido que aquele membro deu ao outro ("Marido", "Esposa"). Remover apaga as duas.
--
-- Lista enviada: os itens saem da pré-lista de quem envia e ficam PENDENTE até quem recebe
-- aceitar (a pré-lista dele soma as quantidades) ou recusar.

CREATE TABLE IF NOT EXISTS familia_membro (
    id          BIGSERIAL   PRIMARY KEY,
    chave_hash  VARCHAR(64) NOT NULL UNIQUE,
    nome        VARCHAR(30),
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS familia_convite (
    id                 BIGSERIAL   PRIMARY KEY,
    codigo             VARCHAR(8)  NOT NULL UNIQUE,
    loja_id            INTEGER     NOT NULL REFERENCES loja(id),
    de_membro_id       BIGINT      NOT NULL REFERENCES familia_membro(id) ON DELETE CASCADE,
    -- Como quem convidou vai chamar quem aceitar.
    apelido_convidado  VARCHAR(30) NOT NULL,
    criado_em          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expira_em          TIMESTAMPTZ NOT NULL,
    aceito_em          TIMESTAMPTZ,
    aceito_por_id      BIGINT      REFERENCES familia_membro(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS familia_convite_loja_data_idx ON familia_convite (loja_id, aceito_em);

CREATE TABLE IF NOT EXISTS familia_contato (
    id          BIGSERIAL   PRIMARY KEY,
    membro_id   BIGINT      NOT NULL REFERENCES familia_membro(id) ON DELETE CASCADE,
    contato_id  BIGINT      NOT NULL REFERENCES familia_membro(id) ON DELETE CASCADE,
    apelido     VARCHAR(30) NOT NULL,
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT familia_contato_uk UNIQUE (membro_id, contato_id),
    CONSTRAINT familia_contato_outro_ck CHECK (membro_id <> contato_id)
);

CREATE TABLE IF NOT EXISTS familia_lista (
    id              BIGSERIAL   PRIMARY KEY,
    loja_id         INTEGER     NOT NULL REFERENCES loja(id),
    de_membro_id    BIGINT      NOT NULL REFERENCES familia_membro(id) ON DELETE CASCADE,
    para_membro_id  BIGINT      NOT NULL REFERENCES familia_membro(id) ON DELETE CASCADE,
    -- {"itens": {"<id do item>": qtd}, "produtos": {"<código>": {"descricao": "...", "quantidade": n}}}
    conteudo        JSONB       NOT NULL,
    quantidade_itens INTEGER    NOT NULL,
    situacao        VARCHAR(10) NOT NULL DEFAULT 'PENDENTE' CHECK (situacao IN ('PENDENTE', 'ACEITA', 'RECUSADA')),
    enviada_em      TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolvida_em    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS familia_lista_para_idx ON familia_lista (para_membro_id, situacao);
CREATE INDEX IF NOT EXISTS familia_lista_loja_data_idx ON familia_lista (loja_id, enviada_em);

-- Mesma regra do 016/018/019: a API REST pública do Supabase não enxerga nada; o back conecta como postgres.
ALTER TABLE familia_membro ENABLE ROW LEVEL SECURITY;
ALTER TABLE familia_convite ENABLE ROW LEVEL SECURITY;
ALTER TABLE familia_contato ENABLE ROW LEVEL SECURITY;
ALTER TABLE familia_lista ENABLE ROW LEVEL SECURITY;
