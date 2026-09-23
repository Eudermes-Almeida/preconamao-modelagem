"""
Fonte única das 33 posições do layout físico da loja piloto (ver layout_loja.png e
categorias de produtos e sub categorias.xlsx, na raiz do projeto). Usado para gerar o
seed de scripts/010_layout_loja.sql — não é importado em tempo de execução por nada.

rua = coluna do layout (1 a 5, esquerda pra direita); quarteirao = linha, identificada
por letra A/B/C (topo pra baixo, ver scripts/012_quarteirao_letra.sql) — não é mais
número, pra não confundir com o número da rua ao ler o mapa; lado = ESQUERDA/DIREITA
(face da gôndola) ou CENTRO (setor de atendimento, sem gôndola de dois lados: padaria,
açougue, farmácia/drogaria).

Mesma numeração de id usada em tools/categorizador.py (NOME_SETOR/PALAVRAS_CHAVE).
"""

# id: (nome_setor, rua, quarteirao, lado)
LAYOUT_POSICAO: dict[int, tuple[str, int, str, str]] = {
    1: ('PADARIA', 1, 'A', 'CENTRO'),
    2: ('AÇOUGUE', 3, 'A', 'CENTRO'),
    3: ('FARMÁCIA/DROGARIA', 5, 'A', 'CENTRO'),
    4: ('BEBIDAS NÃO ALCOÓLICAS 1', 1, 'A', 'ESQUERDA'),
    5: ('MERCEARIA 1', 1, 'A', 'DIREITA'),
    6: ('FRIOS E LATICÍNIOS 1', 2, 'A', 'ESQUERDA'),
    7: ('HIGIENE E BELEZA 1', 2, 'A', 'DIREITA'),
    8: ('BAZAR 1', 3, 'A', 'ESQUERDA'),
    9: ('HORTIFRÚTI 1', 3, 'A', 'DIREITA'),
    10: ('PET SHOP 1', 4, 'A', 'ESQUERDA'),
    11: ('CONGELADOS E RESFRIADOS 1', 4, 'A', 'DIREITA'),
    12: ('BEBIDAS ALCOÓLICAS 1', 5, 'A', 'ESQUERDA'),
    13: ('LIMPEZA 1', 5, 'A', 'DIREITA'),
    14: ('BEBIDAS NÃO ALCOÓLICAS 2', 1, 'B', 'ESQUERDA'),
    15: ('MERCEARIA 2', 1, 'B', 'DIREITA'),
    16: ('FRIOS E LATICÍNIOS 2', 2, 'B', 'ESQUERDA'),
    17: ('HIGIENE E BELEZA 2', 2, 'B', 'DIREITA'),
    18: ('BAZAR 2', 3, 'B', 'ESQUERDA'),
    19: ('HORTIFRÚTI 2', 3, 'B', 'DIREITA'),
    20: ('PET SHOP 2', 4, 'B', 'ESQUERDA'),
    21: ('CONGELADOS E RESFRIADOS 2', 4, 'B', 'DIREITA'),
    22: ('BEBIDAS ALCOÓLICAS 2', 5, 'B', 'ESQUERDA'),
    23: ('LIMPEZA 2', 5, 'B', 'DIREITA'),
    24: ('BEBIDAS NÃO ALCOÓLICAS 3', 1, 'C', 'ESQUERDA'),
    25: ('MERCEARIA 3', 1, 'C', 'DIREITA'),
    26: ('FRIOS E LATICÍNIOS 3', 2, 'C', 'ESQUERDA'),
    27: ('HIGIENE E BELEZA 3', 2, 'C', 'DIREITA'),
    28: ('INFANTIL', 3, 'C', 'ESQUERDA'),
    29: ('BOMBONIERE', 3, 'C', 'DIREITA'),
    30: ('ECOLOGIA', 4, 'C', 'ESQUERDA'),
    31: ('PESCADOS', 4, 'C', 'DIREITA'),
    32: ('PERFUMARIA', 5, 'C', 'ESQUERDA'),
    33: ('BEM ESTAR', 5, 'C', 'DIREITA'),
}
