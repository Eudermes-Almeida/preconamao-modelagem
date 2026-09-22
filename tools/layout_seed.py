"""
Fonte única das 33 posições do layout físico da loja piloto (ver layout_loja.png e
categorias de produtos e sub categorias.xlsx, na raiz do projeto). Usado para gerar o
seed de scripts/010_layout_loja.sql — não é importado em tempo de execução por nada.

rua = coluna do layout (1 a 5, esquerda pra direita); quarteirao = linha (1 a 3, topo
pra baixo); lado = ESQUERDA/DIREITA (face da gôndola) ou CENTRO (setor de atendimento,
sem gôndola de dois lados: padaria, açougue, farmácia/drogaria).

Mesma numeração de id usada em tools/categorizador.py (NOME_SETOR/PALAVRAS_CHAVE).
"""

# id: (nome_setor, rua, quarteirao, lado)
LAYOUT_POSICAO: dict[int, tuple[str, int, int, str]] = {
    1: ('PADARIA', 1, 1, 'CENTRO'),
    2: ('AÇOUGUE', 3, 1, 'CENTRO'),
    3: ('FARMÁCIA/DROGARIA', 5, 1, 'CENTRO'),
    4: ('BEBIDAS NÃO ALCOÓLICAS 1', 1, 1, 'ESQUERDA'),
    5: ('MERCEARIA 1', 1, 1, 'DIREITA'),
    6: ('FRIOS E LATICÍNIOS 1', 2, 1, 'ESQUERDA'),
    7: ('HIGIENE E BELEZA 1', 2, 1, 'DIREITA'),
    8: ('BAZAR 1', 3, 1, 'ESQUERDA'),
    9: ('HORTIFRÚTI 1', 3, 1, 'DIREITA'),
    10: ('PET SHOP 1', 4, 1, 'ESQUERDA'),
    11: ('CONGELADOS E RESFRIADOS 1', 4, 1, 'DIREITA'),
    12: ('BEBIDAS ALCOÓLICAS 1', 5, 1, 'ESQUERDA'),
    13: ('LIMPEZA 1', 5, 1, 'DIREITA'),
    14: ('BEBIDAS NÃO ALCOÓLICAS 2', 1, 2, 'ESQUERDA'),
    15: ('MERCEARIA 2', 1, 2, 'DIREITA'),
    16: ('FRIOS E LATICÍNIOS 2', 2, 2, 'ESQUERDA'),
    17: ('HIGIENE E BELEZA 2', 2, 2, 'DIREITA'),
    18: ('BAZAR 2', 3, 2, 'ESQUERDA'),
    19: ('HORTIFRÚTI 2', 3, 2, 'DIREITA'),
    20: ('PET SHOP 2', 4, 2, 'ESQUERDA'),
    21: ('CONGELADOS E RESFRIADOS 2', 4, 2, 'DIREITA'),
    22: ('BEBIDAS ALCOÓLICAS 2', 5, 2, 'ESQUERDA'),
    23: ('LIMPEZA 2', 5, 2, 'DIREITA'),
    24: ('BEBIDAS NÃO ALCOÓLICAS 3', 1, 3, 'ESQUERDA'),
    25: ('MERCEARIA 3', 1, 3, 'DIREITA'),
    26: ('FRIOS E LATICÍNIOS 3', 2, 3, 'ESQUERDA'),
    27: ('HIGIENE E BELEZA 3', 2, 3, 'DIREITA'),
    28: ('INFANTIL', 3, 3, 'ESQUERDA'),
    29: ('BOMBONIERE', 3, 3, 'DIREITA'),
    30: ('ECOLOGIA', 4, 3, 'ESQUERDA'),
    31: ('PESCADOS', 4, 3, 'DIREITA'),
    32: ('PERFUMARIA', 5, 3, 'ESQUERDA'),
    33: ('BEM ESTAR', 5, 3, 'DIREITA'),
}
