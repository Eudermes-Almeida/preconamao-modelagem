-- Backfill de layout_id para os produtos carregados antes da coluna existir (script
-- 010): os 5 produtos iniciais (supabase_setup_preconamao.sql, fora do repo) + os
-- scripts 007 e 008. Novas cargas (009 em diante) já nascem com layout_id direto do
-- carga_pricetab.py, sem precisar deste backfill.

UPDATE produtos SET layout_id = 7 WHERE codigo_barras = '7891024134610'; -- CREME DENTAL COLGATE 180G CALCI-PROTECT -> HIGIENE E BELEZA 1
UPDATE produtos SET layout_id = 23 WHERE codigo_barras = '7898255671617'; -- MULTIUSO VEJA 500ML -> LIMPEZA 2
UPDATE produtos SET layout_id = 23 WHERE codigo_barras = '7898005490529'; -- ALCOOL 70 ARCHOTE 1L -> LIMPEZA 2
UPDATE produtos SET layout_id = 23 WHERE codigo_barras = '7898065730085'; -- PEDRA SANITARIA SANY LAVANDA -> LIMPEZA 2
UPDATE produtos SET layout_id = 7 WHERE codigo_barras = '7898255671914'; -- SABONACEO CREMOSO AUDAX FACILITA 300ML -> HIGIENE E BELEZA 1
UPDATE produtos SET layout_id = 5 WHERE codigo_barras = '7891031405406'; -- MOSTARDA AMARELA HEMMER 200G -> MERCEARIA 1
UPDATE produtos SET layout_id = 26 WHERE codigo_barras = '7896051114024'; -- CREME DE LEITE ITAMBE 200G -> FRIOS E LATICÍNIOS 3
UPDATE produtos SET layout_id = 5 WHERE codigo_barras = '7896007811304'; -- MOLHO DE PIMENTA KENKO 150ML -> MERCEARIA 1
UPDATE produtos SET layout_id = 5 WHERE codigo_barras = '7891150107533'; -- MAIONESE HELLMANNS 335ML -> MERCEARIA 1
UPDATE produtos SET layout_id = 29 WHERE codigo_barras = '7892840813420'; -- CHOCOLATE BARRA GAROTO AO LEITE 80G -> BOMBONIERE
UPDATE produtos SET layout_id = 5 WHERE codigo_barras = '7891010571108'; -- AZEITE GALLO EXTRA VIRGEM 500ML -> MERCEARIA 1
UPDATE produtos SET layout_id = 2 WHERE codigo_barras = '7896451001475'; -- CONTRA FILE BOVINO QUILO -> AÇOUGUE
UPDATE produtos SET layout_id = 31 WHERE codigo_barras = '7899026423831'; -- FILE DE TILAPIA COPMAR 400G -> PESCADOS
UPDATE produtos SET layout_id = 22 WHERE codigo_barras = '7894900011517'; -- CERVEJA SPATEN LATA 350ML -> BEBIDAS ALCOÓLICAS 2
UPDATE produtos SET layout_id = 14 WHERE codigo_barras = '7891000315507'; -- REFRIGERANTE COCA COLA PET 2 LITROS -> BEBIDAS NÃO ALCOÓLICAS 2
UPDATE produtos SET layout_id = 3 WHERE codigo_barras = '7891000053508'; -- COMPRIMIDO VITAMINA C REDOXON COM 10 -> FARMÁCIA/DROGARIA
UPDATE produtos SET layout_id = 11 WHERE codigo_barras = '7891095012558'; -- BATATA PALITO CONGELADA MCCAIN 720G -> CONGELADOS E RESFRIADOS 1
UPDATE produtos SET layout_id = 3 WHERE codigo_barras = '7891024132050'; -- DORALGINA COMPRIMIDO COM 20 -> FARMÁCIA/DROGARIA
UPDATE produtos SET layout_id = 23 WHERE codigo_barras = '7896051111024'; -- SABAO EM PO OMO SANITARIO 1KG -> LIMPEZA 2
UPDATE produtos SET layout_id = 7 WHERE codigo_barras = '7891150027725'; -- SABONETE DOVE ORIGINAL 90G -> HIGIENE E BELEZA 1
UPDATE produtos SET layout_id = 19 WHERE codigo_barras = '7896068201534'; -- TOMATE ITALIANO QUILO -> HORTIFRÚTI 2
UPDATE produtos SET layout_id = 7 WHERE codigo_barras = '7891000451403'; -- FRALDA PAMPERS COMFORT SEC GRANDE COM 30 -> HIGIENE E BELEZA 1
UPDATE produtos SET layout_id = 23 WHERE codigo_barras = '7891010951108'; -- DETERGENTE YPE NEUTRO 500ML -> LIMPEZA 2
UPDATE produtos SET layout_id = 25 WHERE codigo_barras = '7896004003888'; -- ARROZ TIO JOAO TIPO 1 5KG -> MERCEARIA 3
UPDATE produtos SET layout_id = 1 WHERE codigo_barras = '7896058004550'; -- PAO DE FORMA WICKBOLD TRADICIONAL 450G -> PADARIA
UPDATE produtos SET layout_id = 20 WHERE codigo_barras = '7896022204557'; -- RACAO PEDIGREE SACHE ADULTO 100G -> PET SHOP 2
UPDATE produtos SET layout_id = 18 WHERE codigo_barras = '7896001000118'; -- LAMPADA LED TASCHIBRA 9W -> BAZAR 2
