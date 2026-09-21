-- Busca de produto por descrição falada (Fase 3 - voz).
-- pg_trgm: similaridade por trigramas (word_similarity), tolera erro de reconhecimento de voz.
-- unaccent: o texto falado vem acentuado ("álcool"); as descrições do PRICETAB vêm sem acento.
-- Sem índice por ora: o catálogo de uma loja é pequeno. Se a busca ficar lenta, criar um índice GIN
-- sobre uma função IMMUTABLE que envolva unaccent(lower(descricao)).

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
