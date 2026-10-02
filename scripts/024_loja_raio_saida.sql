-- Raio de saída da loja (v1.14.1).
--
-- Dois raios, decididos em 02/10/2026:
-- - raio_m (entrada, script 023): até onde a loja aparece para ser escolhida pela localização;
-- - raio_saida_m: até onde a escolha continua valendo. Grande de propósito: em supermercados
--   imensos o cliente no fundo da loja ou no estacionamento não pode "ter ido embora".
-- O app só tira a loja com duas leituras seguidas, confiáveis (margem de erro até 150 m) e fora deste
-- raio. Sem sinal, erro ou leitura imprecisa, a loja continua.

ALTER TABLE loja ADD COLUMN IF NOT EXISTS raio_saida_m INTEGER;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'loja_raio_saida_valido') THEN
        ALTER TABLE loja ADD CONSTRAINT loja_raio_saida_valido CHECK (raio_saida_m BETWEEN 10 AND 10000);
    END IF;
END $$;

UPDATE loja SET raio_saida_m = 300 WHERE id = 1 AND raio_saida_m IS NULL;
