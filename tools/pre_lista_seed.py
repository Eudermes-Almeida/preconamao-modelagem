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
        ('Farinha de trigo tradicional', ['FARINHA DE TRIGO']),
        ('Farinha de trigo integral', ['FARINHA DE TRIGO INTEGRAL']),
        ('Farinha de mandioca torrada', ['FARINHA DE MANDIOCA']),
        ('Farinha de milho', ['FARINHA DE MILHO']),
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
        ('Molho de pimenta', ['MOLHO DE PIMENTA']),
        ('Milho em conserva', ['MILHO EM CONSERVA', 'CONSERVA DE MILHO', 'MILHO VERDE']),
        ('Ervilha em conserva', ['ERVILHA']),
        ('Sardinha em óleo', ['SARDINHA']),
        ('Atum enlatado', ['ATUM']),
        ('Vinagre', ['VINAGRE']),
    ]),
    ('Frios, Laticínios e Embutidos', [
        ('Leite integral', ['LEITE INTEGRAL', 'LEITE']),
        ('Leite desnatado', ['LEITE DESNATADO']),
        ('Leite zero lactose', ['LEITE ZERO LACTOSE']),
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
        ('Creme de leite', ['CREME DE LEITE']),
        ('Leite condensado', ['LEITE CONDENSADO']),
        ('Salame', ['SALAME']),
        ('Salsicha', ['SALSICHA', 'SALCHICHA']),
    ]),
    ('Açougue e Pescados', [
        ('Contra filé bovino', ['CONTRA FILE']),
        ('Alcatra bovina', ['ALCATRA', 'CARNE DE BOI ALCATRA']),
        ('Carne moída bovina', ['CARNE MOIDA']),
        ('Acém bovino', ['ACEM']),
        ('Peito de frango', ['PEITO DE FRANGO']),
        ('Coxa e sobrecoxa de frango', ['COXA E SOBRECOXA', 'COXA', 'SOBRECOXA']),
        ('Linguiça calabresa defumada', ['LINGUICA CALABRESA', 'LINGUICA']),
        ('Bife de lombo suíno', ['BIFE DE LOMBO', 'LOMBO']),
        ('Costela suína', ['COSTELA SUINA', 'CARNE DE PORCO COSTELA']),
        ('Filet de tilápia', ['FILE DE TILAPIA', 'FILET DE TILAPIA', 'TILAPIA']),
        ('Camarão cinza', ['CAMARAO']),
        ('Posta de cação', ['POSTA DE CACAO']),
    ]),
    ('Padaria e Sobremesas', [
        ('Pão de forma', ['PAO DE FORMA']),
        ('Pão francês', ['PAO FRANCES']),
        ('Pão de hambúrguer', ['PAO DE HAMBURGUER']),
        ('Pão de queijo', ['PAO DE QUEIJO']),
        ('Bolo de chocolate', ['BOLO DE CHOCOLATE', 'BOLO']),
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
        ('Nuggets de frango', ['NUGGETS']),
        ('Polpa de fruta', ['POLPA']),
        ('Sorvete', ['SORVETE']),
        ('Açaí', ['ACAI']),
    ]),
    ('Bebidas Não Alcoólicas', [
        ('Refrigerante', ['REFRIGERANTE']),
        ('Água mineral', ['AGUA MINERAL']),
        ('Suco', ['SUCO']),
        ('Refresco', ['REFRESCO']),
        ('Chá mate', ['CHA MATE']),
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
        ('Enxaguante bucal', ['ENXAGUANTE BUCAL', 'ANTISEPTICO BUCAL']),
        ('Fio dental', ['FIO DENTAL']),
        ('Desodorante', ['DESODORANTE']),
        ('Papel higiênico', ['PAPEL HIGIENICO']),
        ('Lenço de papel', ['LENCO DE PAPEL']),
        ('Absorvente feminino', ['ABSORVENTE']),
        ('Aparelho de barbear', ['APARELHO DE BARBEAR']),
        ('Espuma de barbear', ['ESPUMA DE BARBEAR']),
        ('Creme hidratante', ['CREME HIDRATANTE', 'HIDRATANTE']),
    ]),
    ('Infantil (Bebês e Crianças)', [
        ('Fralda descartável', ['FRALDA']),
        ('Lenço umedecido infantil', ['LENCO UMEDECIDO']),
        ('Shampoo infantil', ['SHAMPOO INFANTIL']),
        ('Sabonete líquido infantil', ['SABONETE LIQUIDO INFANTIL']),
        ('Pomada contra assaduras', ['POMADA']),
        ('Leite em pó infantil', ['LEITE EM PO INFANTIL', 'LEITE EM PO']),
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
        ('Esponja de aço', ['ESPONJA DE ACO', 'LA DE ACO']),
        ('Esponja de lavar louças', ['ESPONJA DUPLA FACE', 'ESPONJA']),
        ('Inseticida aerossol', ['INSETICIDA']),
        ('Purificador de ar', ['PURIFICADOR DE AR', 'ODORIZADOR']),
        ('Saco para lixo', ['SACO PARA LIXO', 'SACO DE LIXO', 'SACO LIXO']),
        ('Pano de chão', ['PANO DE CHAO']),
        ('Pano de prato', ['PANO DE PRATO']),
    ]),
    ('Pet Shop', [
        ('Ração para cães', ['RACAO PARA CAES', 'RACAO CAES', 'RACAO PEDIGREE']),
        ('Ração para gatos', ['RACAO PARA GATOS', 'RACAO GATOS']),
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
        ('Pilhas alcalinas tamanho AA', ['PILHA ALCALINA AA', 'PILHAS ALCALINAS AA']),
        ('Pilhas alcalinas tamanho AAA', ['PILHA ALCALINA AAA', 'PILHAS ALCALINAS AAA']),
        ('Fita adesiva transparente', ['FITA ADESIVA']),
        ('Caderno universitário', ['CADERNO']),
        ('Caneta esferográfica', ['CANETA']),
        ('Vaso de plástico para plantas', ['VASO DE PLASTICO', 'PLANTEIRA VASO', 'VASO']),
        ('Chinelo de borracha', ['CHINELO']),
    ]),
]


def _sql(texto: str) -> str:
    return "'" + texto.replace("'", "''") + "'"


def gera_sql() -> str:
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
    return (
        "INSERT INTO pre_lista_categoria (id, nome, ordem) VALUES\n  " + ",\n  ".join(categorias) + ";\n\n"
        "INSERT INTO pre_lista_item (id, categoria_id, nome, ordem) VALUES\n  " + ",\n  ".join(itens) + ";\n\n"
        "INSERT INTO pre_lista_termo (item_id, termo) VALUES\n  " + ",\n  ".join(termos) + ";\n"
    )


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    print(gera_sql(), end='')
