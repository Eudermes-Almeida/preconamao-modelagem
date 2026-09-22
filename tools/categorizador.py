"""
Casa a descrição de um produto do PRICETAB com uma posição do layout físico da loja
(tabela layout_posicao), usando um dicionário de palavras-chave.

Fonte oficial das categorias/subcategorias: planilha "categorias de produtos e sub
categorias.xlsx" (raiz do projeto), cruzada com o layout_loja.png. Os 33 ids abaixo
seguem a mesma numeração de modelagem_dados_postgres/scripts/010_layout_loja.sql.

Duas camadas de casamento, nessa ordem:
1. SOBRESCRITAS (frase exata, mais específica) — resolve ambiguidades conhecidas, ex.:
   "DOCE DE LEITE" não é bala (bomboniere), é mercearia; "PAO DE QUEIJO" é congelado,
   não padaria.
2. PALAVRAS-CHAVE (palavra única, ordem importa: mais específica primeiro, mais
   genérica por último, já que a primeira que bater vence).

Isto é uma heurística sobre texto livre, não uma verdade absoluta: vai deixar produtos
sem categoria (ver SEM_CATEGORIA_CONHECIDOS abaixo) e pode acertar a gaveta errada em
casos ambíguos. Revisar conforme o catálogo real da loja piloto crescer.
"""
import re
import unicodedata

# Nome do setor por id, só para debug/relatório (não é usado no casamento em si).
NOME_SETOR = {
    1: 'PADARIA', 2: 'AÇOUGUE', 3: 'FARMÁCIA/DROGARIA',
    4: 'BEBIDAS NÃO ALCOÓLICAS 1', 5: 'MERCEARIA 1', 6: 'FRIOS E LATICÍNIOS 1',
    7: 'HIGIENE E BELEZA 1', 8: 'BAZAR 1', 9: 'HORTIFRÚTI 1', 10: 'PET SHOP 1',
    11: 'CONGELADOS E RESFRIADOS 1', 12: 'BEBIDAS ALCOÓLICAS 1', 13: 'LIMPEZA 1',
    14: 'BEBIDAS NÃO ALCOÓLICAS 2', 15: 'MERCEARIA 2', 16: 'FRIOS E LATICÍNIOS 2',
    17: 'HIGIENE E BELEZA 2', 18: 'BAZAR 2', 19: 'HORTIFRÚTI 2', 20: 'PET SHOP 2',
    21: 'CONGELADOS E RESFRIADOS 2', 22: 'BEBIDAS ALCOÓLICAS 2', 23: 'LIMPEZA 2',
    24: 'BEBIDAS NÃO ALCOÓLICAS 3', 25: 'MERCEARIA 3', 26: 'FRIOS E LATICÍNIOS 3',
    27: 'HIGIENE E BELEZA 3', 28: 'INFANTIL', 29: 'BOMBONIERE', 30: 'ECOLOGIA',
    31: 'PESCADOS', 32: 'PERFUMARIA', 33: 'BEM ESTAR',
}

# Frases (mais de uma palavra) checadas antes das palavras soltas — resolvem casos em
# que a palavra genérica bateria na gaveta errada.
SOBRESCRITAS: list[tuple[str, int]] = [
    ('DOCE DE LEITE', 5),        # senão "DOCE" isolado iria para bomboniere (29)
    ('ZERO LACTOSE', 6),         # senão "LEITE" isolado iria para laticínios 3 (26)
    ('PAO DE QUEIJO', 11),       # senão "PAES"/"QUEIJO" iriam para padaria/laticínios
    ('PAES DE QUEIJO', 11),
]

# Palavras únicas, já em MAIÚSCULO e sem acento (ver normaliza()). A primeira que bater
# na descrição vence — por isso termos de marca/produto específicos vêm antes dos
# termos de categoria bem genéricos (CARNE, FRUTA, PAO...).
PALAVRAS_CHAVE: list[tuple[str, int]] = [
    # --- Bomboniere (29) ---
    ('BOMBOM', 29), ('BALA', 29), ('BALAS', 29), ('PIRULITO', 29), ('PIRULITOS', 29),
    ('CHOCOLATE', 29),
    # --- Açougue (2, header) ---
    ('LINGUICA', 2), ('LINGUICAS', 2), ('ALCATRA', 2), ('BOVINO', 2), ('PORCO', 2),
    ('FRANGO', 2), ('BOI', 2), ('CARNE', 2),
    # --- Pescados (31) ---
    ('TILAPIA', 31), ('CAMARAO', 31), ('PESCADO', 31), ('PESCADOS', 31), ('LULA', 31),
    ('PEIXE', 31),
    # --- Bebidas alcoólicas 1 / 2 (12 / 22) ---
    ('WHISKY', 12), ('UISQUE', 12), ('DESTILADO', 12), ('DESTILADOS', 12), ('VINHO', 12),
    ('VINHOS', 12), ('CERVEJA', 22), ('CERVEJAS', 22),
    # --- Bebidas não alcoólicas 1 / 2 / 3 (4 / 14 / 24) ---
    ('ENERGETICO', 4), ('ENERGETICOS', 4), ('AGUA', 4), ('CHA', 4),
    ('REFRIGERANTE', 14), ('COCA', 14), ('GUARANA', 14),
    ('REFRESCO', 24), ('TANG', 24), ('SUCO', 24), ('SUCOS', 24),
    # --- Bem estar (33) ---
    ('ADOCANTE', 33), ('ADOANTE', 33),  # "ADOANTE": grafia sem cedilha usada no PRICETAB de teste
    ('LIGHT', 33), ('LIGTH', 33),
    # --- Congelados e resfriados 1 / 2 (11 / 21) ---
    ('POLPA', 11), ('LASANHA', 11), ('SALCHICHA', 11), ('SALSICHA', 11),
    ('DEFUMADO', 11), ('DEFUMADA', 11), ('CONGELADO', 11), ('CONGELADA', 11),
    ('SORVETE', 21), ('SORVETES', 21),
    # --- Drogaria (3, header) ---
    ('DORALGINA', 3), ('REDOXON', 3), ('VITAMINA', 3), ('COMPRIMIDO', 3),
    ('DERMOCOSMETICO', 3), ('PROTETOR', 3), ('WHEY', 3), ('NUTRICAO', 3),
    ('MEDICAMENTO', 3), ('FARMACIA', 3), ('DROGARIA', 3),
    # --- Frios e laticínios 1 / 2 / 3 (6 / 16 / 26) ---
    ('REQUEIJAO', 6), ('EMBUTIDO', 6), ('LACTOSE', 6),
    ('MUSSARELA', 16), ('MARGARINA', 16), ('MANTEIGA', 16), ('QUEIJO', 16),
    ('IOGURTE', 26), ('LACTEO', 26), ('LEITE', 26),
    # --- Higiene e beleza 1 / 2 / 3 (7 / 17 / 27) ---
    ('PAMPERS', 7), ('FRALDA', 7), ('LISTERINE', 7), ('BUCAL', 7), ('DENTAL', 7),
    ('SABONACEO', 7), ('SABONETE', 7), ('MAQUIAGEM', 7),
    ('ELSEVE', 17), ('SHAMPOO', 17), ('CONDICIONADOR', 17),
    ('HIGIENICO', 27), ('NEVE', 27),
    # --- Hortifrúti 1 / 2 (9 / 19) ---
    ('ALFACE', 9), ('ORGANICO', 9), ('VERDURA', 9), ('OVOS', 9), ('OVO', 9),
    ('CENOURA', 19), ('TOMATE', 19), ('LEGUME', 19), ('FRUTA', 19),
    # --- Limpeza 1 / 2 (13 / 23) ---
    ('RAID', 13), ('GLADE', 13), ('INSETICIDA', 13), ('PURIFICADOR', 13), ('FOGAO', 13),
    ('LAVANDERIA', 23), ('AMACIANTE', 23), ('VEJA', 23), ('LIMPADOR', 23),
    ('DETERGENTE', 23), ('SABAO', 23), ('SANITARIA', 23), ('ALCOOL', 23),
    # --- Mercearia 1 / 2 / 3 (5 / 15 / 25) ---
    ('MOSTARDA', 5), ('MAIONESE', 5), ('AZEITE', 5), ('CONSERVA', 5), ('MILHO', 5),
    ('BISCOITO', 5), ('MOLHO', 5), ('TEMPERO', 5),
    ('CEREAL', 15), ('MATINAL', 15),
    ('ESPAGUETE', 25), ('MACARRAO', 25), ('MASSA', 25), ('ARROZ', 25),
    # --- Padaria (1, header) ---
    ('WICKBOLD', 1), ('PAO', 1), ('PAES', 1), ('CONFEITARIA', 1),
    # --- Pet Shop 1 / 2 (10 / 20) ---
    ('MORDEDOR', 10), ('COLEIRA', 10), ('COMEDOURO', 10),
    ('PEDIGREE', 20), ('RACAO', 20),
    # --- Bazar 1 / 2 (8 / 18) ---
    ('AUTOMOTIVO', 8),
    ('TILIBRA', 18), ('CADERNO', 18), ('PANELA', 18), ('COZINHA', 18),
    ('HAVAIANAS', 18), ('CHINELO', 18), ('CALCADO', 18), ('LUPO', 18), ('ROUPA', 18),
    ('LAMPADA', 18),
    # --- Infantil (28) ---
    ('BRINQUEDO', 28),
    # --- Ecologia (30) ---
    ('NUTRIPLAN', 30), ('PLANTEIRA', 30), ('PLANTA', 30), ('VASO', 30),
    # --- Perfumaria (32) ---
    ('KAIAK', 32), ('PERFUME', 32),
]

_STOPWORDS_IRRELEVANTES = set()  # reservado; hoje o casamento é por palavra inteira, não frase.


def normaliza(texto: str) -> str:
    """Maiúsculo e sem acento, mesma normalização usada na busca por voz do backend
    (unaccent + upper) — garante que 'AÇOUGUE' e 'ACOUGUE' casam igual."""
    sem_acento = unicodedata.normalize('NFD', texto).encode('ascii', 'ignore').decode('ascii')
    return sem_acento.upper()


def categorizar(descricao: str) -> int | None:
    """Devolve o layout_id da primeira sobrescrita ou palavra-chave que bater na
    descrição (já normalizada), ou None se nada bateu."""
    texto = normaliza(descricao)

    for frase, layout_id in SOBRESCRITAS:
        if frase in texto:
            return layout_id

    palavras = set(re.findall(r'[A-Z0-9]+', texto))
    for chave, layout_id in PALAVRAS_CHAVE:
        if chave in palavras:
            return layout_id

    return None
