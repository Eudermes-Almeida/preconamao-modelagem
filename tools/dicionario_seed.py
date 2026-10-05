"""
Gera os INSERTs da tabela abreviacao a partir de dicionario_abreviacoes.csv (fonte única do
dicionário). No banco, expandir_descricao() (scripts/025_pricetab_real.sql) aplica as regras;
toda carga do PRICETAB recalcula a descrição expandida de todos os produtos do arquivo, então
basta trocar o dicionário no banco para a próxima carga já usar o novo.

Uso: python tools/dicionario_seed.py > trecho.sql
"""
from pathlib import Path

ARQUIVO = Path(__file__).with_name('dicionario_abreviacoes.csv')


def _sql(texto: str) -> str:
    return "'" + texto.replace("'", "''") + "'"


def le_regras() -> list[tuple[str, str]]:
    regras: dict[str, str] = {}
    for linha in ARQUIVO.read_text(encoding='utf-8').splitlines():
        if not linha.strip() or linha.startswith('#') or linha.startswith('abreviacao;'):
            continue
        abreviacao, expansao, *_ = linha.split(';')
        termo = ' '.join(abreviacao.upper().split())
        if termo in regras:
            raise SystemExit(f'Abreviação repetida no dicionário: {termo}')
        regras[termo] = ' '.join(expansao.upper().split())
    return list(regras.items())


def gera_sql() -> str:
    linhas = [f"({_sql(termo)}, {_sql(expansao)})" for termo, expansao in le_regras()]
    return ("INSERT INTO abreviacao (termo, expansao) VALUES\n  "
            + ",\n  ".join(linhas) + ";\n")


if __name__ == '__main__':
    print(gera_sql(), end='')
