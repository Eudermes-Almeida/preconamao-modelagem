-- Quarteirão passa a ser identificado por letra (A/B/C) em vez de número (1/2/3) — pedido do
-- usuário para não confundir com o número da rua ao ler o mapa da loja.
ALTER TABLE layout_posicao ALTER COLUMN quarteirao TYPE VARCHAR(1)
    USING (CASE quarteirao
        WHEN 1 THEN 'A'
        WHEN 2 THEN 'B'
        WHEN 3 THEN 'C'
    END);

ALTER TABLE layout_posicao ADD CONSTRAINT layout_posicao_quarteirao_check CHECK (quarteirao IN ('A', 'B', 'C'));
