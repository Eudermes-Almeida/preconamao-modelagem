"""
Fonte única da pré-lista de compras: categorias e itens (aba "pre lista" da planilha
"categorias de produtos e sub categorias.xlsx", raiz do projeto) e os TERMOS de cada item.

Termo = início de descrição do PRICETAB que identifica o item (MAIÚSCULO, sem acento). Um
produto pertence ao item cujo termo é o MAIS LONGO que casa com o começo da sua descrição,
sempre em palavra inteira (ver vincular_produtos_pre_lista() em scripts/013_pre_lista.sql):
- "SABONETE LIQUIDO PROTEX..." -> Sabonete líquido (termo SABONETE LIQUIDO)
- "SABONETE DOVE ORIGINAL..."  -> Sabonete barra   (herda do termo genérico SABONETE)
Os termos extras cobrem sinônimos e a grafia de produtos já cadastrados (ex.: "MASSA
ESPAGUETE" para Macarrão espaguete, "SALCHICHA" para Salsicha). Um termo só pode apontar
para um item (UNIQUE no banco).

Uso: python tools/pre_lista_seed.py > trecho.sql  (imprime os INSERTs do seed)
     python tools/pre_lista_seed.py --atualizar   (INSERT ... ON CONFLICT, para banco já povoado)
"""

# (categoria, [(item, [termos])])
PRE_LISTA: list[tuple[str, list[tuple[str, list[str]]]]] = [
    ('Mercearia, Cereais e Grãos', [
        ('Arroz', ['ARROZ']),
        ('Arroz integral', ['ARROZ INTEGRAL']),
        ('Feijão carioca', ['FEIJAO CARIOCA', 'FEIJAO']),
        ('Feijão preto', ['FEIJAO PRETO']),
        ('Açúcar refinado', ['ACUCAR REFINADO', 'ACUCAR']),
        ('Açúcar cristal', ['ACUCAR CRISTAL']),
        ('Sal refinado', ['SAL REFINADO', 'SAL']),
        ('Farinha de trigo tradicional', ['FARINHA DE TRIGO', 'FARINHA TRIGO']),
        ('Farinha de trigo integral', ['FARINHA DE TRIGO INTEGRAL']),
        ('Farinha de mandioca torrada', ['FARINHA DE MANDIOCA', 'FARINHA MANDIOCA']),
        ('Farinha de milho', ['FARINHA DE MILHO', 'FARINHA MILHO']),
        ('Fubá mimoso', ['FUBA']),
        ('Café', ['CAFE']),
        ('Cereal matinal', ['CEREAL MATINAL', 'CEREAL']),
        ('Aveia', ['AVEIA']),
        ('Óleo de soja', ['OLEO DE SOJA', 'OLEO']),
        ('Azeite de oliva', ['AZEITE']),
        ('Macarrão espaguete', ['MACARRAO ESPAGUETE', 'MASSA ESPAGUETE', 'MACARRAO', 'MASSA']),
        ('Macarrão parafuso', ['MACARRAO PARAFUSO', 'MASSA PARAFUSO']),
        ('Molho de tomate', ['MOLHO DE TOMATE']),
        ('Extrato de tomate', ['EXTRATO DE TOMATE']),
        ('Maionese', ['MAIONESE']),
        ('Ketchup', ['KETCHUP']),
        ('Mostarda amarela', ['MOSTARDA']),
        ('Molho de pimenta', ['MOLHO DE PIMENTA', 'MOLHO PIMENTA']),
        ('Milho em conserva', ['MILHO EM CONSERVA', 'CONSERVA DE MILHO', 'MILHO VERDE']),
        ('Ervilha em conserva', ['ERVILHA']),
        ('Sardinha em óleo', ['SARDINHA']),
        ('Atum enlatado', ['ATUM']),
        ('Vinagre', ['VINAGRE']),
    ]),
    ('Frios, Laticínios e Embutidos', [
        ('Leite integral', ['LEITE INTEGRAL', 'LEITE']),
        ('Leite desnatado', ['LEITE DESNATADO', 'LEITE % DESNATADO', 'LEITE % SEMIDESNATADO']),
        ('Leite zero lactose', ['LEITE ZERO LACTOSE', 'LEITE % ZERO LACTOSE', 'LEITE LONGA VIDA % ZERO LACTOSE %', 'LEITE LONGA VIDA % NOLAC %']),
        ('Queijo mussarela', ['QUEIJO MUSSARELA', 'MUSSARELA']),
        ('Queijo prato', ['QUEIJO PRATO']),
        ('Queijo minas', ['QUEIJO MINAS']),
        ('Queijo parmesão ralado', ['QUEIJO PARMESAO']),
        ('Presunto cozido', ['PRESUNTO']),
        ('Peito de peru', ['PEITO DE PERU']),
        ('Manteiga', ['MANTEIGA']),
        ('Margarina', ['MARGARINA']),
        ('Requeijão cremoso', ['REQUEIJAO']),
        ('Iogurte', ['IOGURTE']),
        ('Creme de leite', ['CREME DE LEITE', 'CREME CULINARIO']),
        ('Leite condensado', ['LEITE CONDENSADO']),
        ('Salame', ['SALAME']),
        ('Salsicha', ['SALSICHA', 'SALCHICHA']),
    ]),
    ('Açougue e Pescados', [
        ('Contra filé bovino', ['CONTRA FILE', 'CARNE BOVINA CONTRA FILE']),
        ('Alcatra bovina', ['ALCATRA', 'CARNE DE BOI ALCATRA', 'CARNE BOVINA ALCATRA']),
        ('Carne moída bovina', ['CARNE MOIDA', 'CARNE BOVINA MOIDA']),
        ('Acém bovino', ['ACEM', 'CARNE BOVINA ACEM']),
        ('Peito de frango', ['PEITO DE FRANGO', 'PEITO FRANGO', 'FILE PEITO']),
        ('Coxa e sobrecoxa de frango', ['COXA E SOBRECOXA', 'COXA', 'SOBRECOXA', 'FILE COXA']),
        ('Linguiça calabresa defumada', ['LINGUICA CALABRESA', 'LINGUICA']),
        ('Bife de lombo suíno', ['BIFE DE LOMBO', 'LOMBO', 'CARNE SUINA LOMBO', 'CARNE SUINA COPA LOMBO']),
        ('Costela suína', ['COSTELA SUINA', 'CARNE DE PORCO COSTELA', 'CARNE SUINA COSTELA', 'CARNE SUINA COSTELINHA']),
        ('Filet de tilápia', ['FILE DE TILAPIA', 'FILET DE TILAPIA', 'TILAPIA', 'PEIXE FILE TILAPIA']),
        ('Camarão cinza', ['CAMARAO']),
        ('Posta de cação', ['POSTA DE CACAO']),
    ]),
    ('Padaria e Sobremesas', [
        ('Pão de forma', ['PAO DE FORMA', 'PAO FORMA']),
        ('Pão francês', ['PAO FRANCES']),
        ('Pão de hambúrguer', ['PAO DE HAMBURGUER', 'PAO HAMBURGUER']),
        ('Pão de queijo', ['PAO DE QUEIJO', 'PAO QUEIJO']),
        ('Bolo de chocolate', ['BOLO DE CHOCOLATE', 'BOLO', 'PADARIA BOLO']),
        ('Torrada', ['TORRADA']),
        ('Biscoito recheado', ['BISCOITO RECHEADO']),
        ('Biscoito água e sal', ['BISCOITO AGUA E SAL', 'BISCOITO CREAM CRACKER']),
        ('Biscoito maisena', ['BISCOITO MAISENA', 'BISCOITO MAIZENA']),
        ('Biscoito de polvilho', ['BISCOITO DE POLVILHO', 'BISCOITO POLVILHO']),
        ('Gelatina em pó', ['GELATINA']),
        ('Pudim de baunilha', ['PUDIM']),
    ]),
    ('Hortifrúti (Frutas, Verduras e Legumes)', [
        ('Banana prata', ['BANANA']),
        ('Maçã', ['MACA']),
        ('Laranja', ['LARANJA']),
        ('Limão', ['LIMAO']),
        ('Mamão', ['MAMAO']),
        ('Melancia', ['MELANCIA']),
        ('Batata inglesa', ['BATATA INGLESA', 'BATATA']),
        ('Batata doce', ['BATATA DOCE']),
        ('Cebola', ['CEBOLA']),
        ('Alho', ['ALHO']),
        ('Tomate', ['TOMATE']),
        ('Cenoura', ['CENOURA', 'LEGUME CENOURA']),
        ('Chuchu', ['CHUCHU']),
        ('Abobrinha', ['ABOBRINHA']),
        ('Alface', ['ALFACE', 'VERDURA ALFACE']),
        ('Couve', ['COUVE']),
        ('Ovos', ['OVOS', 'OVO']),
    ]),
    ('Congelados e Sorvetes', [
        ('Batata palito congelada', ['BATATA PALITO']),
        ('Lasanha congelada', ['LASANHA']),
        ('Pizza congelada', ['PIZZA']),
        ('Pão de queijo congelado', ['PAO DE QUEIJO CONGELADO', 'PAES DE QUEIJO CONGELADOS']),
        ('Nuggets de frango', ['NUGGETS', 'EMPANADO']),
        ('Polpa de fruta', ['POLPA']),
        ('Sorvete', ['SORVETE']),
        ('Açaí', ['ACAI']),
    ]),
    ('Bebidas Não Alcoólicas', [
        ('Refrigerante', ['REFRIGERANTE']),
        ('Água mineral', ['AGUA MINERAL']),
        ('Suco', ['SUCO']),
        ('Refresco', ['REFRESCO']),
        ('Chá mate', ['CHA MATE', 'CHA MATTE']),
        ('Energético', ['ENERGETICO']),
    ]),
    ('Adega e Bebidas Alcoólicas', [
        ('Cerveja', ['CERVEJA']),
        ('Vinho', ['VINHO']),
        ('Whisky', ['WHISKY', 'UISQUE']),
        ('Vodka', ['VODKA']),
        ('Cachaça', ['CACHACA']),
    ]),
    ('Higiene Pessoal e Beleza', [
        ('Sabonete barra', ['SABONETE BARRA', 'SABONETE']),
        ('Sabonete líquido', ['SABONETE LIQUIDO']),
        ('Shampoo', ['SHAMPOO']),
        ('Condicionador', ['CONDICIONADOR']),
        ('Creme dental', ['CREME DENTAL']),
        ('Enxaguante bucal', ['ENXAGUANTE BUCAL', 'ANTISEPTICO BUCAL', 'ENXAGUANTE']),
        ('Fio dental', ['FIO DENTAL']),
        ('Desodorante', ['DESODORANTE']),
        ('Papel higiênico', ['PAPEL HIGIENICO']),
        ('Lenço de papel', ['LENCO DE PAPEL']),
        ('Absorvente feminino', ['ABSORVENTE']),
        ('Aparelho de barbear', ['APARELHO DE BARBEAR', 'APARELHO BARBEAR']),
        ('Espuma de barbear', ['ESPUMA DE BARBEAR', 'CREME DE BARBEAR']),
        ('Creme hidratante', ['CREME HIDRATANTE', 'HIDRATANTE', 'LOCAO HIDRATANTE']),
    ]),
    ('Infantil (Bebês e Crianças)', [
        ('Fralda descartável', ['FRALDA']),
        ('Lenço umedecido infantil', ['LENCO UMEDECIDO']),
        ('Shampoo infantil', ['SHAMPOO INFANTIL']),
        ('Sabonete líquido infantil', ['SABONETE LIQUIDO INFANTIL']),
        ('Pomada contra assaduras', ['POMADA']),
        ('Leite em pó infantil', ['LEITE EM PO INFANTIL', 'FORMULA INFANTIL']),
        ('Mingau de cereais infantil', ['MINGAU']),
    ]),
    ('Limpeza Doméstica', [
        ('Detergente', ['DETERGENTE']),
        ('Sabão em pó', ['SABAO EM PO']),
        ('Sabão líquido', ['SABAO LIQUIDO']),
        ('Amaciante', ['AMACIANTE', 'LAVANDERIA AMACIANTE']),
        ('Desinfetante', ['DESINFETANTE']),
        ('Limpador multiuso', ['LIMPADOR MULTIUSO', 'LIMPADOR', 'MULTIUSO']),
        ('Água sanitária', ['AGUA SANITARIA']),
        ('Sabão em barra', ['SABAO EM BARRA']),
        ('Esponja de aço', ['ESPONJA DE ACO', 'LA DE ACO', 'PALHA ACO']),
        ('Esponja de lavar louças', ['ESPONJA DUPLA FACE', 'ESPONJA']),
        ('Inseticida aerossol', ['INSETICIDA']),
        ('Purificador de ar', ['PURIFICADOR DE AR', 'ODORIZADOR', 'PURIFICADOR']),
        ('Saco para lixo', ['SACO PARA LIXO', 'SACO DE LIXO', 'SACO LIXO']),
        ('Pano de chão', ['PANO DE CHAO']),
        ('Pano de prato', ['PANO DE PRATO']),
    ]),
    ('Pet Shop', [
        ('Ração para cães', ['RACAO PARA CAES', 'RACAO CAES', 'RACAO PEDIGREE', 'RACAO CACHORRO']),
        ('Ração para gatos', ['RACAO PARA GATOS', 'RACAO GATOS', 'RACAO GATO']),
        ('Areia sanitária', ['AREIA SANITARIA', 'AREIA HIGIENICA']),
        ('Petisco mordedor', ['PETISCO']),
        ('Coleira', ['COLEIRA']),
        ('Shampoo neutro para pets', ['SHAMPOO PET']),
    ]),
    ('Drogaria e Bem-Estar', [
        ('Doralgina comprimidos', ['DORALGINA']),
        ('Paracetamol comprimidos', ['PARACETAMOL']),
        ('Dipirona sódica', ['DIPIRONA']),
        ('Vitamina C', ['VITAMINA C', 'COMPRIMIDO VITAMINA C']),
        ('Suplemento whey protein', ['WHEY PROTEIN', 'SUPLEMENTO WHEY', 'NUTRICAO ESPORTIVA WHEY']),
        ('Protetor solar', ['PROTETOR SOLAR', 'DERMOCOSMETICO PROTETOR SOLAR']),
        # "ADOANTE": grafia (sem cedilha) do produto já cadastrado — ver categorizador.py.
        ('Adoçante líquido', ['ADOCANTE', 'ADOANTE']),
        ('Curativo adesivo', ['CURATIVO']),
        ('Álcool em gel', ['ALCOOL EM GEL', 'ALCOOL GEL']),
    ]),
    ('Bazar e Utilidades', [
        ('Lâmpada led', ['LAMPADA']),
        ('Pilhas alcalinas tamanho AA', ['PILHA ALCALINA AA', 'PILHAS ALCALINAS AA', 'PILHA % AA']),
        ('Pilhas alcalinas tamanho AAA', ['PILHA ALCALINA AAA', 'PILHAS ALCALINAS AAA', 'PILHA % AAA', 'PILHA % AAA2']),
        ('Fita adesiva transparente', ['FITA ADESIVA']),
        ('Caderno universitário', ['CADERNO']),
        ('Caneta esferográfica', ['CANETA']),
        ('Vaso de plástico para plantas', ['VASO DE PLASTICO', 'PLANTEIRA VASO', 'VASO']),
        ('Chinelo de borracha', ['CHINELO', 'SANDALIA HAVAIANAS', 'SANDALIA']),
    ]),
]

# Categorias criadas depois da planilha (id e ordem fixos, depois das 14 da planilha).
CATEGORIAS_ADICIONAIS: list[str] = [
    'Doces e Snacks',  # 15 — PRICETAB real (026)
    'Tabacaria',       # 16 — PRICETAB real (026)
]

# Itens criados depois da planilha, com id fixo a partir de 167: acrescentá-los no meio de
# PRE_LISTA mudaria o id de todos os itens seguintes (e a pré-lista salva no aparelho do
# cliente é por id). (id, categoria, item, [termos])
ITENS_ADICIONAIS: list[tuple[int, str, str, list[str]]] = [
    (167, 'Hortifrúti (Frutas, Verduras e Legumes)', 'Repolho', ['REPOLHO']),  # 015_produtos_pesaveis.sql
    # --- PRICETAB real (PRICE2.TXT, 2026-10-05): itens que faltavam (ver analise_pre_lista_PRICE2.xlsx)
    (168, 'Mercearia, Cereais e Grãos', 'Achocolatado', ['ACHOCOLATADO']),
    (169, 'Mercearia, Cereais e Grãos', 'Cappuccino', ['CAPPUCCINO']),
    (170, 'Mercearia, Cereais e Grãos', 'Chá em sachê', ['CHA']),
    (171, 'Mercearia, Cereais e Grãos', 'Filtro de café', ['FILTRO PAPEL', 'FILTRO CAFE', 'FILTRO DE CAFE']),
    (172, 'Mercearia, Cereais e Grãos', 'Tempero', ['TEMPERO', 'CONDIMENTO']),
    (173, 'Mercearia, Cereais e Grãos', 'Caldo em tablete', ['CALDO']),
    (174, 'Mercearia, Cereais e Grãos', 'Outros molhos (shoyu, barbecue, inglês)', ['MOLHO']),
    (175, 'Mercearia, Cereais e Grãos', 'Pimenta em conserva', ['PIMENTA']),
    (176, 'Mercearia, Cereais e Grãos', 'Azeitona', ['AZEITONA']),
    (177, 'Mercearia, Cereais e Grãos', 'Palmito', ['PALMITO']),
    (178, 'Mercearia, Cereais e Grãos', 'Coco ralado', ['COCO']),
    (179, 'Mercearia, Cereais e Grãos', 'Farofa pronta', ['FAROFA']),
    (180, 'Mercearia, Cereais e Grãos', 'Outras farinhas', ['FARINHA']),
    (181, 'Mercearia, Cereais e Grãos', 'Polvilho', ['POLVILHO']),
    (182, 'Mercearia, Cereais e Grãos', 'Canjica', ['CANJICA']),
    (183, 'Mercearia, Cereais e Grãos', 'Fermento', ['FERMENTO']),
    (184, 'Mercearia, Cereais e Grãos', 'Bicarbonato', ['BICARBONATO']),
    (185, 'Mercearia, Cereais e Grãos', 'Mistura para bolo', ['MISTURA PARA BOLO']),
    (186, 'Mercearia, Cereais e Grãos', 'Chantilly', ['CREME CHANTILLY', 'CHANTILLY']),
    (187, 'Mercearia, Cereais e Grãos', 'Sementes (chia, linhaça)', ['SEMENTE']),
    (188, 'Mercearia, Cereais e Grãos', 'Pasta de amendoim', ['PASTA AMENDOIM', 'PASTA DE AMENDOIM']),
    (189, 'Mercearia, Cereais e Grãos', 'Batata palha', ['BATATA PALHA']),
    (190, 'Mercearia, Cereais e Grãos', 'Milho de pipoca', ['MILHO PIPOCA', 'MILHO DE PIPOCA']),
    (191, 'Frios, Laticínios e Embutidos', 'Leite em pó', ['LEITE EM PO', 'LEITE EM PO % DESNATADO']),
    (192, 'Frios, Laticínios e Embutidos', 'Bebida láctea', ['BEBIDA LACTEA']),
    (193, 'Frios, Laticínios e Embutidos', 'Leite fermentado', ['LEITE FERMENTADO']),
    (194, 'Frios, Laticínios e Embutidos', 'Petit suisse', ['PETIT']),
    (195, 'Frios, Laticínios e Embutidos', 'Sobremesa pronta', ['SOBREMESA']),
    (196, 'Frios, Laticínios e Embutidos', 'Ricota', ['RICOTA', 'CREME RICOTA', 'QUEIJO RICOTA']),
    (197, 'Frios, Laticínios e Embutidos', 'Outros queijos (coalho, provolone, canastra)', ['QUEIJO']),
    (198, 'Frios, Laticínios e Embutidos', 'Mortadela', ['MORTADELA']),
    (199, 'Frios, Laticínios e Embutidos', 'Apresuntado', ['APRESUNTADO']),
    (200, 'Frios, Laticínios e Embutidos', 'Bacon', ['BACON']),
    (201, 'Açougue e Pescados', 'Outros cortes bovinos', ['CARNE BOVINA']),
    (202, 'Açougue e Pescados', 'Outros cortes suínos', ['CARNE SUINA']),
    (203, 'Açougue e Pescados', 'Asa de frango', ['ASA', 'COXINHA ASA', 'MEIO ASA', 'MEIO DA ASA']),
    (204, 'Açougue e Pescados', 'Frango inteiro / passarinho', ['FRANGO']),
    (205, 'Açougue e Pescados', 'Outros peixes', ['PEIXE']),
    (206, 'Padaria e Sobremesas', 'Outros pães (doce, integral, artesanal)', ['PAO', 'PAOZINHO']),
    (207, 'Padaria e Sobremesas', 'Pão de alho', ['PAO ALHO', 'PAO DE ALHO']),
    (208, 'Padaria e Sobremesas', 'Roscas e broinhas', ['ROSCA', 'BROINHA', 'PADARIA BROA']),
    (209, 'Padaria e Sobremesas', 'Bolinho', ['BOLINHO']),
    (210, 'Padaria e Sobremesas', 'Panetone', ['PANETONE', 'CHOCOTTONE']),
    (211, 'Padaria e Sobremesas', 'Biscoito wafer', ['BISCOITO WAFER']),
    (212, 'Padaria e Sobremesas', 'Biscoito amanteigado e rosquinha', ['BISCOITO AMANTEIGADO', 'ROSQUINHA']),
    (213, 'Padaria e Sobremesas', 'Cookies', ['COOKIES', 'COOKIE']),
    (214, 'Padaria e Sobremesas', 'Outros biscoitos', ['BISCOITO']),
    (215, 'Hortifrúti (Frutas, Verduras e Legumes)', 'Uva', ['UVA']),
    (216, 'Hortifrúti (Frutas, Verduras e Legumes)', 'Mandioca', ['MANDIOCA']),
    (217, 'Congelados e Sorvetes', 'Hambúrguer', ['HAMBURGUER']),
    (218, 'Congelados e Sorvetes', 'Sanduíche pronto', ['SANDUICHE']),
    (219, 'Bebidas Não Alcoólicas', 'Isotônico', ['ISOTONICO']),
    (220, 'Bebidas Não Alcoólicas', 'Água de coco', ['AGUA COCO', 'AGUA DE COCO']),
    (221, 'Bebidas Não Alcoólicas', 'Água tônica', ['AGUA TONICA']),
    (222, 'Bebidas Não Alcoólicas', 'Água saborizada', ['AGUA SABORIZADA']),
    (223, 'Bebidas Não Alcoólicas', 'Gelo', ['GELO']),
    (224, 'Bebidas Não Alcoólicas', 'Outras bebidas (soja, proteica)', ['BEBIDA']),
    (225, 'Adega e Bebidas Alcoólicas', 'Coquetel alcoólico', ['COQUETEL']),
    (226, 'Adega e Bebidas Alcoólicas', 'Bebida mista (ice)', ['BEBIDA MISTA', 'BEBIDA ICE']),
    (227, 'Adega e Bebidas Alcoólicas', 'Gin', ['GIN']),
    (228, 'Adega e Bebidas Alcoólicas', 'Rum', ['RUM']),
    (229, 'Adega e Bebidas Alcoólicas', 'Espumante', ['ESPUMANTE']),
    (230, 'Higiene Pessoal e Beleza', 'Escova dental', ['ESCOVA DENTAL']),
    (231, 'Higiene Pessoal e Beleza', 'Escova de cabelo', ['ESCOVA CABELO', 'ESCOVA DE CABELO']),
    (232, 'Higiene Pessoal e Beleza', 'Creme para pentear e tratamento', ['CREME PARA PENTEAR', 'CREME DE TRATAMENTO', 'CREME CAPILAR']),
    (233, 'Higiene Pessoal e Beleza', 'Tintura de cabelo', ['TINTURA']),
    (234, 'Higiene Pessoal e Beleza', 'Esmalte', ['ESMALTE']),
    (235, 'Higiene Pessoal e Beleza', 'Protetor diário', ['PROTECAO DIARIO', 'PROTETOR DIARIO']),
    (236, 'Higiene Pessoal e Beleza', 'Preservativo', ['PRESERVATIVO']),
    (237, 'Higiene Pessoal e Beleza', 'Algodão', ['ALGODAO']),
    (238, 'Higiene Pessoal e Beleza', 'Haste flexível', ['HASTE']),
    (239, 'Higiene Pessoal e Beleza', 'Talco', ['TALCO']),
    (240, 'Infantil (Bebês e Crianças)', 'Farinha láctea', ['FARINHA LACTEA']),
    (241, 'Limpeza Doméstica', 'Alvejante', ['ALVEJANTE']),
    (242, 'Limpeza Doméstica', 'Limpa alumínio, forno e piso', ['LIMPA']),
    (243, 'Limpeza Doméstica', 'Pedra sanitária', ['PEDRA SANITARIA']),
    (244, 'Limpeza Doméstica', 'Desentupidor', ['DESENTUPIDOR']),
    (245, 'Limpeza Doméstica', 'Vassoura e rodo', ['VASSOURA', 'RODO']),
    (246, 'Limpeza Doméstica', 'Cera', ['CERA']),
    (247, 'Limpeza Doméstica', 'Papel toalha', ['PAPEL TOALHA']),
    (248, 'Drogaria e Bem-Estar', 'Repelente', ['REPELENTE']),
    (249, 'Drogaria e Bem-Estar', 'Própolis', ['EXTRATO DE PROPOLIS', 'PROPOLIS']),
    (250, 'Bazar e Utilidades', 'Papel alumínio', ['PAPEL ALUMINIO']),
    (251, 'Bazar e Utilidades', 'Vela de aniversário', ['VELA']),
    (252, 'Bazar e Utilidades', 'Balão de festa', ['BALAO']),
    (253, 'Bazar e Utilidades', 'Descartáveis (copo, prato, talher)', ['COPO DESCARTAVEL', 'PRATO DESCARTAVEL', 'COLHER DESCARTAVEL', 'GARFO DESCARTAVEL', 'POTE DESCARTAVEL']),
    (254, 'Doces e Snacks', 'Chocolate', ['CHOCOLATE']),
    (255, 'Doces e Snacks', 'Bombom', ['BOMBOM']),
    (256, 'Doces e Snacks', 'Balas, drops e chicletes', ['BALA', 'DROPS', 'CHICLETE', 'PASTILHA', 'PIRULITO']),
    (257, 'Doces e Snacks', 'Salgadinho', ['SALGADINHO', 'BATATA CROQUES', 'BATATA PRINGLES', 'BATATA CHIPS', 'PURURUCA']),
    (258, 'Doces e Snacks', 'Amendoim', ['AMENDOIM']),
    (259, 'Doces e Snacks', 'Pipoca de micro-ondas', ['PIPOCA']),
    (260, 'Doces e Snacks', 'Doce de leite', ['DOCE LEITE', 'DOCE DE LEITE']),
    (261, 'Doces e Snacks', 'Doces (paçoca, goiabada, cocada)', ['DOCE', 'RAPADURA', 'GOIABADA', 'PACOCA']),
    (262, 'Doces e Snacks', 'Barra de cereal', ['BARRA CEREAL', 'BARRA DE CEREAL']),
    (263, 'Tabacaria', 'Cigarro', ['CIGARRO']),
]


def _sql(texto: str) -> str:
    return "'" + texto.replace("'", "''") + "'"


def gera_sql(atualizar: bool = False) -> str:
    """INSERTs das 3 tabelas da pré-lista; ids fixos (1..N na ordem da planilha), como no
    seed do layout, para o front e os scripts poderem referenciar um item sem consulta."""
    categorias, itens, termos = [], [], []
    item_id = 0
    vistos: set[str] = set()
    for cat_id, (categoria, lista) in enumerate(PRE_LISTA, start=1):
        categorias.append(f"({cat_id}, {_sql(categoria)}, {cat_id})")
        for ordem, (item, termos_item) in enumerate(lista, start=1):
            item_id += 1
            itens.append(f"({item_id}, {cat_id}, {_sql(item)}, {ordem})")
            for termo in termos_item:
                if termo in vistos:
                    raise ValueError(f'termo repetido: {termo}')
                vistos.add(termo)
                termos.append(f"({item_id}, {_sql(termo)})")
    nomes_categorias = [categoria for categoria, _ in PRE_LISTA] + CATEGORIAS_ADICIONAIS
    for cat_id, categoria in enumerate(CATEGORIAS_ADICIONAIS, start=len(PRE_LISTA) + 1):
        categorias.append(f"({cat_id}, {_sql(categoria)}, {cat_id})")
    for item_id, categoria, item, termos_item in ITENS_ADICIONAIS:
        cat_id = nomes_categorias.index(categoria) + 1
        ja_na_planilha = len(PRE_LISTA[cat_id - 1][1]) if cat_id <= len(PRE_LISTA) else 0
        ordem = ja_na_planilha + 1 + sum(
            1 for outro in ITENS_ADICIONAIS if outro[1] == categoria and outro[0] < item_id)
        itens.append(f"({item_id}, {cat_id}, {_sql(item)}, {ordem})")
        for termo in termos_item:
            if termo in vistos:
                raise ValueError(f'termo repetido: {termo}')
            vistos.add(termo)
            termos.append(f"({item_id}, {_sql(termo)})")
    if atualizar:
        # Para bancos que já têm a pré-lista (026 em diante): acrescenta o que falta e move o termo
        # que mudou de item, sem apagar nada (o celular do cliente guarda a pré-lista pelo id).
        return (
            "INSERT INTO pre_lista_categoria (id, nome, ordem) VALUES\n  " + ",\n  ".join(categorias)
            + "\nON CONFLICT (id) DO UPDATE SET nome = EXCLUDED.nome, ordem = EXCLUDED.ordem;\n\n"
            "INSERT INTO pre_lista_item (id, categoria_id, nome, ordem) VALUES\n  " + ",\n  ".join(itens)
            + "\nON CONFLICT (id) DO UPDATE SET categoria_id = EXCLUDED.categoria_id, nome = EXCLUDED.nome, ordem = EXCLUDED.ordem;\n\n"
            "INSERT INTO pre_lista_termo (item_id, termo) VALUES\n  " + ",\n  ".join(termos)
            + "\nON CONFLICT (termo) DO UPDATE SET item_id = EXCLUDED.item_id;\n"
        )
    return (
        "INSERT INTO pre_lista_categoria (id, nome, ordem) VALUES\n  " + ",\n  ".join(categorias) + ";\n\n"
        "INSERT INTO pre_lista_item (id, categoria_id, nome, ordem) VALUES\n  " + ",\n  ".join(itens) + ";\n\n"
        "INSERT INTO pre_lista_termo (item_id, termo) VALUES\n  " + ",\n  ".join(termos) + ";\n"
    )


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    print(gera_sql(atualizar='--atualizar' in sys.argv), end='')
