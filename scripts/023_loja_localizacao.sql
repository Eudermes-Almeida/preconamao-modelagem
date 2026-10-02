-- Geolocalização da loja (v1.14.0).
--
-- O link do app é público: sem saber em qual loja o cliente está, ele poderia ver dentro da loja B
-- os preços da loja A. O cliente informa a loja pelo QR code afixado nela (endereço
-- www.simplificacompras.app.br/<slug>) ou escolhe numa lista que só traz as lojas cujo raio alcança
-- a posição do celular. A distância é calculada no próprio celular: a localização do cliente não é
-- enviada ao servidor.
--
-- Loja sem latitude/longitude não aparece para o cliente (não é parceira com localização).
-- Durante os testes, a loja piloto (id 1) é o escritório do Simplifica Compras (Rua São Paulo, 778,
-- Divinópolis - MG); o ponto vem do Google Maps e pode ser trocado pelo medido no local, pelo botão
-- "Registrar a posição desta loja" do /admin.

ALTER TABLE loja ADD COLUMN IF NOT EXISTS slug VARCHAR(60);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS nome_curto VARCHAR(30);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS latitude NUMERIC(9, 6);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS longitude NUMERIC(9, 6);
ALTER TABLE loja ADD COLUMN IF NOT EXISTS raio_m INTEGER;
ALTER TABLE loja ADD COLUMN IF NOT EXISTS posicao_atualizada_em TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'loja_slug_unico') THEN
        ALTER TABLE loja ADD CONSTRAINT loja_slug_unico UNIQUE (slug);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'loja_slug_formato') THEN
        -- Só minúsculas, números e hífens (é um pedaço do endereço do QR code).
        ALTER TABLE loja ADD CONSTRAINT loja_slug_formato CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'loja_raio_valido') THEN
        ALTER TABLE loja ADD CONSTRAINT loja_raio_valido CHECK (raio_m BETWEEN 10 AND 2000);
    END IF;
END $$;

UPDATE loja
   SET slug = 'escritorio-simplifica',
       nome_curto = 'Escritório Simplifica',
       latitude = -20.142567,
       longitude = -44.892650,
       raio_m = 50
 WHERE id = 1
   AND slug IS NULL;
