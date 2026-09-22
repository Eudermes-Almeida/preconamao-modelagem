-- Carga gerada automaticamente por tools/carga_pricetab.py a partir do PRICETAB.TXT

INSERT INTO produtos (codigo_barras, descricao, preco_centavos) VALUES ('7891031405406', 'MOSTARDA AMARELA HEMMER 200G', 1230) ON CONFLICT (codigo_barras) DO UPDATE SET descricao = EXCLUDED.descricao, preco_centavos = EXCLUDED.preco_centavos;
INSERT INTO produtos (codigo_barras, descricao, preco_centavos) VALUES ('7896051114024', 'CREME DE LEITE ITAMBE 200G', 479) ON CONFLICT (codigo_barras) DO UPDATE SET descricao = EXCLUDED.descricao, preco_centavos = EXCLUDED.preco_centavos;
INSERT INTO produtos (codigo_barras, descricao, preco_centavos) VALUES ('7896007811304', 'MOLHO DE PIMENTA KENKO 150ML', 629) ON CONFLICT (codigo_barras) DO UPDATE SET descricao = EXCLUDED.descricao, preco_centavos = EXCLUDED.preco_centavos;
INSERT INTO produtos (codigo_barras, descricao, preco_centavos) VALUES ('7891150107533', 'MAIONESE HELLMANNS 335ML', 1430) ON CONFLICT (codigo_barras) DO UPDATE SET descricao = EXCLUDED.descricao, preco_centavos = EXCLUDED.preco_centavos;
