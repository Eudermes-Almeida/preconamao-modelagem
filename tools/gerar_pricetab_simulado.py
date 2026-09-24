"""
Gera um PRICETAB.TXT SIMULADO (não existe arquivo oficial da loja piloto): o catálogo que
já está no banco + um produto fictício para cada item da pré-lista (tools/pre_lista_seed.py)
que ainda não tinha produto correspondente.

- Produtos já cadastrados entram com o MESMO código de barras, descrição e preço — as
  propagandas de oferta (oferta-<codigo>.png no front) dependem desses códigos.
- Produtos novos recebem código EAN-13 fictício com prefixo 200 (faixa GS1 de uso interno
  da loja: nunca colide com código de produto real) e dígito verificador válido.
- Cada descrição nova começa pelo termo do item da pré-lista, como o PRICETAB faria.

Uso:
    python tools/gerar_pricetab_simulado.py <produtos_atuais.txt> <saida PRICETAB.TXT>
onde produtos_atuais.txt tem uma linha "codigo|descricao|preco_centavos" por produto
(exportado do banco: SELECT codigo_barras, descricao, preco_centavos FROM produtos).
"""
import sys
from pathlib import Path

# (descrição até 40 caracteres, preço em centavos) — fictícios.
NOVOS_PRODUTOS: list[tuple[str, int]] = [
    # Mercearia, Cereais e Grãos
    ('ARROZ INTEGRAL CAMIL TIPO 1 1KG', 899),
    ('FEIJAO CARIOCA KICALDO TIPO 1 1KG', 849),
    ('FEIJAO PRETO CAMIL TIPO 1 1KG', 919),
    ('ACUCAR REFINADO UNIAO 1KG', 549),
    ('ACUCAR CRISTAL CARAVELAS 5KG', 1999),
    ('SAL REFINADO CISNE 1KG', 329),
    ('FARINHA DE TRIGO DONA BENTA 1KG', 649),
    ('FARINHA DE TRIGO INTEGRAL RENATA 1KG', 789),
    ('FARINHA DE MANDIOCA TORRADA YOKI 500G', 599),
    ('FARINHA DE MILHO FLOCAO YOKI 500G', 459),
    ('FUBA MIMOSO SINHA 1KG', 489),
    ('CAFE PILAO TRADICIONAL 500G', 1890),
    ('AVEIA EM FLOCOS QUAKER 250G', 699),
    ('OLEO DE SOJA LIZA 900ML', 849),
    ('MACARRAO PARAFUSO ADRIA 500G', 489),
    ('MOLHO DE TOMATE POMAROLA SACHE 300G', 349),
    ('EXTRATO DE TOMATE ELEFANTE 310G', 699),
    ('KETCHUP HEINZ TRADICIONAL 397G', 1299),
    ('ERVILHA EM CONSERVA QUERO LATA 170G', 399),
    ('SARDINHA EM OLEO GOMES DA COSTA 125G', 749),
    ('ATUM RALADO GOMES DA COSTA 170G', 999),
    ('VINAGRE DE ALCOOL CASTELO 750ML', 329),
    # Frios, Laticínios e Embutidos
    ('LEITE INTEGRAL ITALAC UHT 1 LITRO', 549),
    ('LEITE DESNATADO ITALAC UHT 1 LITRO', 589),
    ('QUEIJO PRATO FATIADO TIROLEZ QUILO', 5990),
    ('QUEIJO MINAS FRESCAL SCALA 500G', 2490),
    ('QUEIJO PARMESAO RALADO VIGOR 50G', 899),
    ('PRESUNTO COZIDO FATIADO SADIA QUILO', 3990),
    ('PEITO DE PERU DEFUMADO SADIA QUILO', 6990),
    ('MANTEIGA COM SAL AVIACAO 200G', 1590),
    ('LEITE CONDENSADO MOCA 395G', 749),
    ('SALAME ITALIANO SADIA FATIADO 100G', 1290),
    # Açougue e Pescados
    ('CARNE MOIDA BOVINA PATINHO KG', 3990),
    ('ACEM BOVINO EM PEDACOS KG', 2990),
    ('PEITO DE FRANGO SEM OSSO SADIA KG', 2190),
    ('COXA E SOBRECOXA DE FRANGO SADIA KG', 1390),
    ('BIFE DE LOMBO SUINO SEARA KG', 2690),
    ('POSTA DE CACAO CONGELADA 500G', 2890),
    # Padaria e Sobremesas
    ('PAO FRANCES UNIDADE', 90),
    ('PAO DE HAMBURGUER WICKBOLD 4 UNIDADES', 899),
    ('PAO DE QUEIJO FRESCO PADARIA QUILO', 3990),
    ('BOLO DE CHOCOLATE CASEIRO FATIA', 790),
    ('TORRADA TRADICIONAL BAUDUCCO 142G', 649),
    ('BISCOITO RECHEADO TRAKINAS MORANGO 126G', 299),
    ('BISCOITO AGUA E SAL MARILAN 184G', 449),
    ('BISCOITO MAISENA MARILAN 400G', 599),
    ('BISCOITO DE POLVILHO GLOBO 30G', 349),
    ('GELATINA EM PO ROYAL MORANGO 25G', 249),
    ('PUDIM DE BAUNILHA DR OETKER 50G', 499),
    # Hortifrúti
    ('BANANA PRATA QUILO', 699),
    ('MACA GALA QUILO', 999),
    ('LARANJA PERA QUILO', 499),
    ('LIMAO TAHITI QUILO', 599),
    ('MAMAO FORMOSA QUILO', 699),
    ('MELANCIA INTEIRA QUILO', 349),
    ('BATATA INGLESA QUILO', 549),
    ('BATATA DOCE QUILO', 499),
    ('CEBOLA NACIONAL QUILO', 449),
    ('ALHO NACIONAL QUILO', 2990),
    ('CHUCHU QUILO', 399),
    ('ABOBRINHA ITALIANA QUILO', 599),
    ('COUVE MANTEIGA MACO', 349),
    # Congelados e Sorvetes
    ('PIZZA CONGELADA SADIA CALABRESA 460G', 1990),
    ('NUGGETS DE FRANGO SADIA 300G', 1290),
    ('ACAI TRADICIONAL POLPA 1 LITRO', 2290),
    # Bebidas Não Alcoólicas
    ('CHA MATE LEAO NATURAL 1,5 LITRO', 699),
    # Adega e Bebidas Alcoólicas
    ('VODKA SMIRNOFF 998ML', 3990),
    ('CACHACA 51 GARRAFA 965ML', 1590),
    # Higiene Pessoal e Beleza
    ('SABONETE LIQUIDO PROTEX REFIL 200ML', 1290),
    ('FIO DENTAL ORAL B ESSENTIAL 50M', 899),
    ('DESODORANTE AEROSOL REXONA 150ML', 1690),
    ('LENCO DE PAPEL KLEENEX BOLSO 10UN', 299),
    ('ABSORVENTE ALWAYS NOTURNO COM 8', 1190),
    ('APARELHO DE BARBEAR GILLETTE PRESTOBARBA', 1490),
    ('ESPUMA DE BARBEAR GILLETTE 175G', 2190),
    ('CREME HIDRATANTE NIVEA 200ML', 1990),
    # Infantil
    ('LENCO UMEDECIDO INFANTIL HUGGIES 48UN', 1290),
    ('SHAMPOO INFANTIL JOHNSONS BABY 200ML', 1490),
    ('SABONETE LIQUIDO INFANTIL JOHNSONS 200ML', 1590),
    ('POMADA CONTRA ASSADURAS BEPANTOL 30G', 2490),
    ('LEITE EM PO INFANTIL NAN SUPREME 800G', 6990),
    ('MINGAU DE CEREAIS INFANTIL MUCILON 230G', 1190),
    # Limpeza Doméstica
    ('SABAO LIQUIDO OMO LAVAGEM PERFEITA 900ML', 2890),
    ('DESINFETANTE PINHO SOL ORIGINAL 500ML', 899),
    ('AGUA SANITARIA QBOA 1 LITRO', 499),
    ('SABAO EM BARRA YPE GLICERINADO 5UN', 1190),
    ('ESPONJA DE ACO BOMBRIL 8 UNIDADES', 399),
    ('ESPONJA DUPLA FACE SCOTCH BRITE 3UN', 649),
    ('SACO PARA LIXO DOVER ROLL 50L 30UN', 1290),
    ('PANO DE CHAO ALGODAO BRANCO FLASH LIMP', 799),
    ('PANO DE PRATO ESTAMPADO SANTISTA', 999),
    # Pet Shop
    ('RACAO PARA GATOS WHISKAS CARNE 1KG', 2990),
    ('AREIA SANITARIA PIPICAT CLASSIC 4KG', 1690),
    ('PETISCO MORDEDOR DOGUITOS OSSINHO 45G', 699),
    ('SHAMPOO PET NEUTRO SANOL DOG 500ML', 1890),
    # Drogaria e Bem-Estar
    ('PARACETAMOL 750MG EMS COM 20 COMPRIMIDOS', 1290),
    ('DIPIRONA SODICA 500MG GOTAS 20ML', 699),
    ('CURATIVO ADESIVO BAND AID 10 UNIDADES', 799),
    ('ALCOOL EM GEL 70 ASSEPSIA 500G', 1290),
    # Bazar e Utilidades
    ('PILHA ALCALINA AA DURACELL COM 4', 2490),
    ('PILHA ALCALINA AAA DURACELL COM 4', 2490),
    ('FITA ADESIVA TRANSPARENTE 3M 45MMX45M', 890),
    ('CANETA ESFEROGRAFICA BIC AZUL', 250),
]

PREFIXO_CODIGO = '200'


def digito_verificador_ean13(doze_digitos: str) -> str:
    soma = sum(int(d) * (3 if i % 2 else 1) for i, d in enumerate(doze_digitos))
    return str((10 - soma % 10) % 10)


def linha_pricetab(codigo: str, descricao: str, preco_centavos: int) -> str:
    return f"{codigo}|{descricao:<40}|{preco_centavos:010d}||"


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    atuais = []
    for linha in Path(sys.argv[1]).read_text(encoding='utf-8').splitlines():
        if linha.strip():
            codigo, descricao, preco = linha.split('|')
            atuais.append((codigo, descricao, int(preco)))

    descricoes_atuais = {d for _, d, _ in atuais}
    codigos_usados = {c for c, _, _ in atuais}
    linhas = [linha_pricetab(*p) for p in atuais]

    sequencia = 0
    for descricao, preco in NOVOS_PRODUTOS:
        if len(descricao) > 40:
            raise ValueError(f'descrição com mais de 40 caracteres: {descricao}')
        if descricao in descricoes_atuais:
            raise ValueError(f'produto já existe no banco: {descricao}')
        while True:
            sequencia += 1
            doze = f"{PREFIXO_CODIGO}{sequencia:09d}"
            codigo = doze + digito_verificador_ean13(doze)
            if codigo not in codigos_usados:
                break
        codigos_usados.add(codigo)
        linhas.append(linha_pricetab(codigo, descricao, preco))

    # Latin-1 e CRLF, como o arquivo exportado pela balança/PDV (ver carga_pricetab.py).
    Path(sys.argv[2]).write_text('\r\n'.join(linhas) + '\r\n', encoding='latin-1', newline='')
    print(f"{len(atuais)} produto(s) do banco + {len(NOVOS_PRODUTOS)} novo(s) = {len(linhas)} linha(s)")


if __name__ == '__main__':
    main()
