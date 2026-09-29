"""
Gera os INSERTs da tabela categorizador_regra a partir de categorizador.py, que continua sendo a
fonte única das regras. No banco, a função categorizar() (scripts/016_carga_automatica.sql)
aplica as mesmas duas camadas, na mesma ordem:
1. FRASE: o termo aparece em qualquer ponto da descrição normalizada (primeira da lista vence);
2. PALAVRA: o termo é uma palavra inteira da descrição (primeira da lista vence).
Termo repetido na mesma camada: vale a primeira ocorrência, como no Python.

Uso: python tools/categorizador_seed.py > trecho.sql
"""
from categorizador import PALAVRAS_CHAVE, SOBRESCRITAS


def _sql(texto: str) -> str:
    return "'" + texto.replace("'", "''") + "'"


def gera_sql() -> str:
    linhas = []
    for tipo, regras in (('FRASE', SOBRESCRITAS), ('PALAVRA', PALAVRAS_CHAVE)):
        vistos: set[str] = set()
        for ordem, (termo, layout_id) in enumerate(regras, start=1):
            if termo in vistos:
                continue
            vistos.add(termo)
            linhas.append(f"({_sql(tipo)}, {ordem}, {_sql(termo)}, {layout_id})")
    return ("INSERT INTO categorizador_regra (tipo, ordem, termo, layout_id) VALUES\n  "
            + ",\n  ".join(linhas) + ";\n")


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    print(gera_sql(), end='')
