"""
Gera scripts/029_dicionarios.sql a partir dos dicionários em tools/dicionarios/*.csv (multi-loja,
regras 8b, 9 e 21). Cada CSV é um dicionário do catálogo (comum.csv = camada COMUM; os outros =
CATALOGO), com as colunas:
    abreviacao;expansao;setor;observacao
"^" no começo da abreviação = só vale como primeira palavra. "#FIM_NUMERO" no fim = regra
condicional: só vale quando a descrição termina com 2 dígitos ("^SAND#FIM_NUMERO" = sandália, pelo
tamanho do calçado). "setor" preenchido = SIGLA DE SEÇÃO
(a expansão fica vazia: a sigla sai da descrição e define o setor do mapa pelo nome do setor em
layout_posicao, ex.: "HORTIFRÚTI 1").

O script gerado substitui as regras de cada dicionário (DELETE + INSERT, numa transação); o banco
marca as lojas que usam o dicionário e o backend reprocessa as descrições sozinho (regra 9d).

Uso: python tools/dicionarios_seed.py   (escreve scripts/029_dicionarios.sql)
"""
from pathlib import Path

PASTA = Path(__file__).with_name('dicionarios')
DESTINO = Path(__file__).parent.parent / 'scripts' / '029_dicionarios.sql'
# arquivo -> (nome do dicionário no banco, camada)
DICIONARIOS = {
    'comum.csv': ('Comum', 'COMUM'),
    'price2.csv': ('PRICE2', 'CATALOGO'),
    'beta.csv': ('Beta', 'CATALOGO'),
    'gama.csv': ('Gama', 'CATALOGO'),
}


def _sql(texto: str) -> str:
    return "'" + texto.replace("'", "''") + "'"


def le(arquivo: Path) -> list[tuple[str, str, str]]:
    regras: dict[str, tuple[str, str]] = {}
    for linha in arquivo.read_text(encoding='utf-8').splitlines():
        if not linha.strip() or linha.startswith('#') or linha.startswith('abreviacao;'):
            continue
        partes = linha.split(';')
        termo = ' '.join(partes[0].upper().split())
        expansao = ' '.join(partes[1].upper().split()) if len(partes) > 1 else ''
        setor = partes[2].strip() if len(partes) > 2 else ''
        if termo in regras:
            raise SystemExit(f'{arquivo.name}: abreviação repetida: {termo}')
        regras[termo] = (expansao, setor)
    return [(t, e, s) for t, (e, s) in regras.items()]


def gera() -> str:
    partes = ["-- 029 — Dicionários do catálogo (gerado por tools/dicionarios_seed.py a partir de",
              "-- tools/dicionarios/*.csv; NÃO editar à mão). Reexecutável: substitui as regras de cada",
              "-- dicionário. O banco marca as lojas que usam cada um e o backend reprocessa (regra 9d).", ""]
    for arquivo, (nome, camada) in DICIONARIOS.items():
        regras = le(PASTA / arquivo)
        partes.append(f"-- {nome} ({camada}): {len(regras)} regras")
        partes.append(f"INSERT INTO dicionario (nome, camada) VALUES ({_sql(nome)}, {_sql(camada)}) ON CONFLICT (nome) DO NOTHING;")
        partes.append(f"DELETE FROM abreviacao WHERE dicionario_id = (SELECT id FROM dicionario WHERE nome = {_sql(nome)});")
        valores = []
        for termo_condicao, expansao, setor in regras:
            termo, _, condicao = termo_condicao.partition('#')
            layout = f"(SELECT id FROM layout_posicao WHERE nome_setor = {_sql(setor)})" if setor else 'NULL'
            valores.append(f"  ((SELECT id FROM dicionario WHERE nome = {_sql(nome)}), {_sql(termo)}, "
                           f"{'NULL' if setor else _sql(expansao)}, {layout}, {_sql(condicao) if condicao else 'NULL'})")
        partes.append("INSERT INTO abreviacao (dicionario_id, termo, expansao, layout_id, condicao) VALUES\n" + ",\n".join(valores) + ";")
        partes.append("")
    return "\n".join(partes)


if __name__ == '__main__':
    DESTINO.write_text(gera(), encoding='utf-8')
    print(f'{DESTINO.name} gerado')
