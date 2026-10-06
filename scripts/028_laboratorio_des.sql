-- =============================================================================================
-- 028 — Laboratório multi-loja: SÓ NO AMBIENTE DE DESENVOLVIMENTO (DES). NUNCA aplicar em produção.
--
-- 5 lojas com nomes fictícios (regra 29), a loja 1 vira "Alfa Centro" (regra 28) e TODAS começam
-- vazias: a primeira carga de cada uma entra pelo caminho novo (regra 26e).
--   1 Alfa Centro   alfa-centro  Rede Alfa  PRICETAB 40  PRICE2.TXT
--   2 Alfa Bairro   alfa-bairro  Rede Alfa  PRICETAB 40  PRICETABS.TXT  (+ 1 regra só dela: 9c)
--   3 Beta Hiper    beta-hiper   Rede Beta  PRICETAB 16  PRICETABF.TXT
--   4 Gama          gama         Rede Gama  PRICETAB 16  PRICETABP.TXT
--   5 Alfa Online   alfa-online  Rede Alfa  API          PRICE2 + 20%, com promoções
-- Chaves dos agentes: só o SHA-256 aqui; as chaves ficam em laboratorio/chaves_lab.json (fora do
-- git). Chaves de relatório do DES: rel-<loja>, rel-rede-alfa; chave geral: chave-geral-des.
-- Reexecutável.
-- =============================================================================================

INSERT INTO rede (id, nome, slug, chave_relatorio_hash) VALUES
  (1, 'Rede Alfa', 'rede-alfa', 'e160c8f4fd504e136f203d8dc889f4c51dd70d7791749e9804beabea51fffa69'),
  (2, 'Rede Beta', 'rede-beta', NULL),
  (3, 'Rede Gama', 'rede-gama', NULL)
ON CONFLICT (id) DO UPDATE SET nome = EXCLUDED.nome, slug = EXCLUDED.slug, chave_relatorio_hash = EXCLUDED.chave_relatorio_hash;
SELECT setval(pg_get_serial_sequence('rede', 'id'), (SELECT max(id) FROM rede));

-- Dicionários do catálogo para as lojas de 16 posições (regras vêm depois, com aprovação) e a
-- camada só da loja 2 (regra 9c: a mesma descrição sai diferente na loja 1 e na loja 2).
INSERT INTO dicionario (nome, camada) VALUES ('Beta', 'CATALOGO'), ('Gama', 'CATALOGO'), ('Alfa Bairro (ajustes)', 'LOJA')
ON CONFLICT (nome) DO NOTHING;
INSERT INTO abreviacao (dicionario_id, termo, expansao)
SELECT id, 'BISC', 'BOLACHA' FROM dicionario WHERE nome = 'Alfa Bairro (ajustes)'
ON CONFLICT (dicionario_id, termo) DO UPDATE SET expansao = EXCLUDED.expansao;

-- Loja 1 -> Alfa Centro.
UPDATE loja SET nome = 'Alfa Centro', nome_curto = 'Alfa Centro', slug = 'alfa-centro', rede_id = 1,
       chave_hash = '065e72ac827b25f0e67e4be0dac6e712b459c0032022e4b94277de956e0ddd3e',
       chave_relatorio_hash = '7cd7e004ccfbc61715e4d7d659c43acd06dbb07ad23ab8ae3ed9f0ebd0b6500b'
 WHERE id = 1;

INSERT INTO loja (id, nome, nome_curto, slug, chave_hash, chave_relatorio_hash, latitude, longitude, raio_m, raio_saida_m)
VALUES
  (2, 'Alfa Bairro', 'Alfa Bairro', 'alfa-bairro', 'e1b56a1819d1e8955e079523dac527565fa124a8f93e36597b1b3774a9f6efb2',
      '0097378aa748b76275a45abd8b71543686b50741096d905d1eb8670787706133', -20.152567, -44.882650, 50, 300),
  (3, 'Beta Hiper', 'Beta Hiper', 'beta-hiper', '4b1e5d8a1dc58e5db9c6235fa6c9f03e83769e129e383f1afe221ebe41150112',
      '843f598f16f05a63c372cf7d939bdfa4ea38545d1eb69c6b950851510572a3f3', -20.162567, -44.872650, 80, 400),
  (4, 'Gama Supermercado', 'Gama', 'gama', '12e763f18e83948db27d1af9968d7f0d741e157493dc3327e57982f63644cd07',
      '2bb68c55f689874be8c695a279039bce60287d486f005313d7fe73aafe75d642', -20.172567, -44.862650, 50, 300),
  (5, 'Alfa Online', 'Alfa Online', 'alfa-online', 'df5e50ed2ccce24ead80515038c1d31a4a987f6d41297ffb3db752d2136b6793',
      'a4d235803c4671fec1843db71e17233212060cd2a9abe45dcd36cf44ada04896', -20.182567, -44.852650, 50, 300)
ON CONFLICT (id) DO UPDATE SET nome = EXCLUDED.nome, nome_curto = EXCLUDED.nome_curto, slug = EXCLUDED.slug,
    chave_hash = EXCLUDED.chave_hash, chave_relatorio_hash = EXCLUDED.chave_relatorio_hash,
    latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, raio_m = EXCLUDED.raio_m, raio_saida_m = EXCLUDED.raio_saida_m;
SELECT setval(pg_get_serial_sequence('loja', 'id'), (SELECT max(id) FROM loja));

-- Origem, formato e dicionário de cada loja; proteção de preço LIGADA nas 5 (regra 11g):
-- PRICETAB 5 min, API 15 min (3 coletas de 5 min sem sucesso).
UPDATE loja l SET rede_id = 1, tipo_origem = 'PRICETAB', ativa = true, limite_inativacao = 0.20, limite_sem_sinal_min = 5,
       formato_id = (SELECT id FROM formato_origem WHERE nome = 'PRICETAB 40 posições'),
       dicionario_id = (SELECT id FROM dicionario WHERE nome = 'PRICE2'), dicionario_loja_id = NULL, intervalo_coleta_min = NULL
 WHERE l.id = 1;
UPDATE loja l SET rede_id = 1, tipo_origem = 'PRICETAB', ativa = true, limite_inativacao = 0.20, limite_sem_sinal_min = 5,
       formato_id = (SELECT id FROM formato_origem WHERE nome = 'PRICETAB 40 posições'),
       dicionario_id = (SELECT id FROM dicionario WHERE nome = 'PRICE2'),
       dicionario_loja_id = (SELECT id FROM dicionario WHERE nome = 'Alfa Bairro (ajustes)'), intervalo_coleta_min = NULL
 WHERE l.id = 2;
UPDATE loja l SET rede_id = 2, tipo_origem = 'PRICETAB', ativa = true, limite_inativacao = 0.20, limite_sem_sinal_min = 5,
       formato_id = (SELECT id FROM formato_origem WHERE nome = 'PRICETAB 16 posições'),
       dicionario_id = (SELECT id FROM dicionario WHERE nome = 'Beta'), dicionario_loja_id = NULL, intervalo_coleta_min = NULL
 WHERE l.id = 3;
UPDATE loja l SET rede_id = 3, tipo_origem = 'PRICETAB', ativa = true, limite_inativacao = 0.20, limite_sem_sinal_min = 5,
       formato_id = (SELECT id FROM formato_origem WHERE nome = 'PRICETAB 16 posições'),
       dicionario_id = (SELECT id FROM dicionario WHERE nome = 'Gama'), dicionario_loja_id = NULL, intervalo_coleta_min = NULL
 WHERE l.id = 4;
-- Loja da API: descrição e seção vêm da origem (sem dicionário do catálogo, só a camada comum);
-- etiqueta no layout REAL do técnico (6 dígitos, código interno sem dígito verificador).
UPDATE loja l SET rede_id = 1, tipo_origem = 'API', ativa = true, limite_inativacao = 0.20, limite_sem_sinal_min = 15,
       formato_id = (SELECT id FROM formato_origem WHERE nome = 'API simulada v1'),
       dicionario_id = NULL, dicionario_loja_id = NULL, intervalo_coleta_min = 5, etiqueta_interno_dv = false
 WHERE l.id = 5;

-- Etiqueta das lojas 1 a 4 (achado A2 aprovado): código de 6 dígitos, interno com verificador.
UPDATE loja SET etiqueta_prefixo = '2', etiqueta_codigo_inicio = 1, etiqueta_codigo_tamanho = 6,
       etiqueta_valor_inicio = 7, etiqueta_valor_tamanho = 5, etiqueta_interno_dv = true
 WHERE id BETWEEN 1 AND 4;

-- Todas começam vazias (regras 26e e 28a): a primeira carga entra pelo caminho novo.
DELETE FROM produtos WHERE loja_id BETWEEN 1 AND 5;
UPDATE loja SET hash_aplicado = NULL, hash_informado = NULL, hash_divergente_desde = NULL, ultimo_sinal_em = NULL,
       alerta_ativo = NULL, alerta_enviado_em = NULL, liberar_proxima_carga = false, reprocessar_dicionario = false,
       ultima_coleta_em = NULL
 WHERE id BETWEEN 1 AND 5;
-- Arquivos antigos guardados no banco saem (regra 10f); as fichas das cargas ficam.
UPDATE carga_pricetab SET arquivo = NULL WHERE arquivo IS NOT NULL;

-- Campanhas com alcances de teste (regra 4c): Coca-Cola 1L só na Rede Alfa (lojas 1, 2 e 5);
-- Doritos só na loja 3; Sorvete Ygloo com campanha VENCIDA (não pode aparecer). O resto: todas.
UPDATE campanha SET alcance = 'REDE', rede_id = 1 WHERE arte LIKE '%7894900011715%';
UPDATE campanha SET alcance = 'LOJAS', rede_id = NULL WHERE arte LIKE '%7892840822408%';
INSERT INTO campanha_loja (campanha_id, loja_id) SELECT id, 3 FROM campanha WHERE arte LIKE '%7892840822408%'
ON CONFLICT DO NOTHING;
UPDATE campanha SET inicio = DATE '2026-09-01', fim = DATE '2026-09-30' WHERE arte LIKE '%7898347310486%';
