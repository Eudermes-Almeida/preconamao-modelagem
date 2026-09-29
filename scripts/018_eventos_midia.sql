-- Relatório de mídias (aba administrativa /admin): cada interação do cliente com uma oferta vira
-- uma linha em evento_midia, enviada pelo app em lote (POST /eventos). Os mesmos eventos vão para o
-- Google Analytics 4 direto do navegador (auditoria independente); aqui fica o relatório operacional.
--
-- Tipos:   EXIBICAO     oferta visível por 1 s ou mais (anúncio de 4 s, ou card na tela Ofertas
--                       com metade à mostra; o card conta uma vez por abertura da tela)
--          FAVORITAR / DESFAVORITAR   coração da tela Ofertas
--          LOCALIZAR    toque em "Localizar" na oferta
--          PRE_LISTA    oferta incluída na pré-lista (tirar não gera evento)
-- Origens: ANUNCIO (publicidade durante a consulta) e TELA_OFERTAS.
--
-- aparelho_id: código aleatório gerado no aparelho (localStorage), sem nenhum dado pessoal; serve
-- para contar aparelhos distintos (alcance) e barrar envio abusivo.
-- A hora é a do servidor ao receber (o relógio do celular não é confiável); o app envia a cada ~10 s.

CREATE TABLE IF NOT EXISTS evento_midia (
    id             BIGSERIAL   PRIMARY KEY,
    loja_id        INTEGER     NOT NULL REFERENCES loja(id),
    tipo           VARCHAR(12) NOT NULL CHECK (tipo IN ('EXIBICAO', 'FAVORITAR', 'DESFAVORITAR', 'LOCALIZAR', 'PRE_LISTA')),
    origem         VARCHAR(12) NOT NULL CHECK (origem IN ('ANUNCIO', 'TELA_OFERTAS')),
    codigo_barras  VARCHAR(14) NOT NULL,
    aparelho_id    UUID        NOT NULL,
    registrado_em  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS evento_midia_loja_data_idx ON evento_midia (loja_id, registrado_em);
CREATE INDEX IF NOT EXISTS evento_midia_aparelho_data_idx ON evento_midia (aparelho_id, registrado_em);

-- Chave de leitura do relatório (cabeçalho X-Chave-Relatorio), separada da chave do agente: quem
-- lê o relatório não consegue enviar PRICETAB. Só o hash SHA-256 é gravado; NULL = relatório
-- fechado. Gerar a chave fora do repositório e gravar com:
--   UPDATE loja SET chave_relatorio_hash = encode(sha256(convert_to('<chave>', 'UTF8')), 'hex') WHERE id = 1;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS chave_relatorio_hash VARCHAR(64);

-- Mesma regra do 016: a API REST pública do Supabase não enxerga nada; o back conecta como postgres.
ALTER TABLE evento_midia ENABLE ROW LEVEL SECURITY;
