"""
FERRAMENTA DE EMERGÊNCIA desde o script 016: o caminho normal é o agente da loja
(agente_pricetab/) enviando o arquivo para a API, que aplica a diferença sozinha. Esta carga não
inativa produtos que sumiram nem atualiza o "hash aplicado" da loja.

Converte um arquivo PRICETAB.TXT (formato Gertec) em um script SQL de carga,
seguindo a mesma convenção de scripts numerados usada no projeto RAIO_X_UNIDADE
(modelagem_dados_postgres/scripts/NNN_carga_*_local.sql).

Formato de cada linha, conforme o documento de contexto do projeto:
CODIGO_DE_BARRAS(13)|DESCRICAO(40, padded)|PRECO(10, zero-padded, sem virgula)||

Uso:
    python tools/carga_pricetab.py caminho/para/PRICETAB.TXT
"""
import re
import sys
from pathlib import Path

from categorizador import categorizar

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"


def proximo_numero_sequencial() -> int:
    numeros = []
    for arquivo in SCRIPTS_DIR.glob("*.sql"):
        match = re.match(r"^(\d+)_", arquivo.name)
        if match:
            numeros.append(int(match.group(1)))
    return max(numeros, default=0) + 1


def parseia_linha(linha: str, numero_linha: int) -> tuple[str, str, int] | None:
    linha_tratada = linha.rstrip("\r\n")
    if not linha_tratada.strip():
        return None

    if not linha_tratada.endswith("||"):
        print(f"[aviso] linha {numero_linha} não termina com '||', ignorada: {linha_tratada!r}", file=sys.stderr)
        return None

    corpo = linha_tratada[:-2]
    partes = corpo.split("|")
    if len(partes) != 3:
        print(f"[aviso] linha {numero_linha} não tem 3 campos separados por '|', ignorada: {linha_tratada!r}", file=sys.stderr)
        return None

    codigo_barras, descricao, preco_str = partes
    codigo_barras = codigo_barras.strip()
    descricao = descricao.rstrip()
    preco_str = preco_str.strip()

    # Código curto = código interno de produto pesável (ver eh_pesavel), não é erro.
    if len(codigo_barras) != 13 and not eh_pesavel(codigo_barras):
        print(f"[aviso] linha {numero_linha}: código de barras com {len(codigo_barras)} caracteres (esperado 13): {codigo_barras!r}", file=sys.stderr)

    # A coluna produtos.descricao é VARCHAR(40) (ver entity/ProdutoEntity.java); sem isto o
    # INSERT falha inteiro no banco, já com linhas anteriores da mesma carga commitadas.
    if len(descricao) > 40:
        print(f"[aviso] linha {numero_linha}: descrição com {len(descricao)} caracteres, cortada para 40: {descricao!r}", file=sys.stderr)
        descricao = descricao[:40].rstrip()

    try:
        preco_centavos = int(preco_str)
    except ValueError:
        print(f"[aviso] linha {numero_linha}: preço inválido, ignorada: {preco_str!r}", file=sys.stderr)
        return None

    return codigo_barras, descricao, preco_centavos


# Produto de balança (hortifrúti, açougue, padaria): no PRICETAB vem com o código interno curto
# (ex.: 2984), não com um EAN-13, e o preço é o do quilo. Hipótese até chegar um PRICETAB real;
# ver scripts/015_produtos_pesaveis.sql e EtiquetaBalanca.java no back.
def eh_pesavel(codigo_barras: str) -> bool:
    return codigo_barras.isdigit() and len(codigo_barras) <= 6


def escapa_sql(texto: str) -> str:
    return texto.replace("'", "''")


def gera_sql(produtos: list[tuple[str, str, int]]) -> str:
    linhas = [
        "-- Carga gerada automaticamente por tools/carga_pricetab.py a partir do PRICETAB.TXT",
        "-- layout_id resolvido por tools/categorizador.py (heurística por palavra-chave a partir",
        "-- da descrição); NULL quando nenhuma palavra-chave bateu — o produto fica sem localização",
        "-- na tela até alguém revisar o dicionário ou ajustar manualmente.",
        "",
    ]
    sem_categoria = []
    for codigo_barras, descricao, preco_centavos in produtos:
        layout_id = categorizar(descricao)
        if layout_id is None:
            sem_categoria.append((codigo_barras, descricao))
        valor_layout_id = "NULL" if layout_id is None else str(layout_id)
        vendido_por_kg = "true" if eh_pesavel(codigo_barras) else "false"
        # Localização corrigida à mão (layout_manual, script 016) não é sobrescrita; produto que
        # estava inativo e voltou ao arquivo é reativado.
        linhas.append(
            "INSERT INTO produtos (codigo_barras, descricao, preco_centavos, layout_id, vendido_por_kg) VALUES "
            f"('{escapa_sql(codigo_barras)}', '{escapa_sql(descricao)}', {preco_centavos}, {valor_layout_id}, {vendido_por_kg}) "
            "ON CONFLICT (codigo_barras) DO UPDATE SET "
            "descricao = EXCLUDED.descricao, preco_centavos = EXCLUDED.preco_centavos, "
            "layout_id = CASE WHEN produtos.layout_manual THEN produtos.layout_id ELSE EXCLUDED.layout_id END, "
            "vendido_por_kg = EXCLUDED.vendido_por_kg, ativo = true, atualizado_em = now();"
        )

    # Recalcula o item da pré-lista de todos os produtos a partir dos termos (herança
    # textual, ver scripts/013_pre_lista.sql) — os produtos novos desta carga incluídos.
    linhas += [
        "",
        "SELECT vincular_produtos_pre_lista();",
    ]

    if sem_categoria:
        print(f"[aviso] {len(sem_categoria)} produto(s) sem localização (layout_id NULL):", file=sys.stderr)
        for codigo_barras, descricao in sem_categoria:
            print(f"  - {codigo_barras}: {descricao}", file=sys.stderr)

    return "\n".join(linhas) + "\n"


def main() -> None:
    if len(sys.argv) != 2:
        print("Uso: python tools/carga_pricetab.py caminho/para/PRICETAB.TXT", file=sys.stderr)
        sys.exit(1)

    caminho_entrada = Path(sys.argv[1])
    if not caminho_entrada.is_file():
        print(f"Arquivo não encontrado: {caminho_entrada}", file=sys.stderr)
        sys.exit(1)

    produtos = []
    with caminho_entrada.open(encoding="latin-1") as arquivo:
        for numero_linha, linha in enumerate(arquivo, start=1):
            resultado = parseia_linha(linha, numero_linha)
            if resultado:
                produtos.append(resultado)

    if not produtos:
        print("Nenhum produto válido encontrado no arquivo.", file=sys.stderr)
        sys.exit(1)

    SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    numero = proximo_numero_sequencial()
    caminho_saida = SCRIPTS_DIR / f"{numero:03d}_carga_pricetab_local.sql"
    caminho_saida.write_text(gera_sql(produtos), encoding="utf-8")

    print(f"{len(produtos)} produto(s) processado(s).")
    print(f"Script gerado em: {caminho_saida}")


if __name__ == "__main__":
    main()
