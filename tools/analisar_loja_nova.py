"""
Análise de uma LOJA NOVA a partir do PRICETAB dela (rotina de entrada de loja do multi-loja: cada
loja é um caso estudado à parte). Varre o arquivo inteiro e responde, sem tocar no banco:

  1. Formato: codificação, terminação das linhas, preço (reais/centavos), tamanho da descrição
     (40 posições ou cortada em 16), registros quebrados em duas linhas, linhas inválidas.
  2. Códigos: tamanhos, códigos internos (balança) e dígito verificador, EAN-8 completado com zeros,
     pares que viram o mesmo código padronizado (13 x 14 dígitos).
  3. Duplicados e preços: código repetido (preço igual / um zerado / preços diferentes), preço 0,00,
     descrições com vários códigos (códigos auxiliares).
  4. Siglas de seção candidatas (primeira palavra curta e muito repetida, ex.: HF, PAD).
  5. Abreviações mais frequentes e quais dicionários prontos já as conhecem.
  6. Como cada dicionário pronto (tools/dicionarios/*.csv) se sai neste arquivo, e as abreviações
     que mudam de sentido entre dicionários (ex.: SAND = sanduíche no PRICE2, sandália no Beta).
  7. Semelhança com os PRICETABs das lojas já conhecidas (mesma rede/sistema?).
  8. Recomendação: reaproveitar um dicionário (só se o padrão for o MESMO) ou criar um exclusivo.

Uso:
  python tools/analisar_loja_nova.py <PRICETAB.TXT> [--referencias <pasta com PRICETABs conhecidos>]
Gera <arquivo>_analise.md ao lado do arquivo analisado e mostra o resumo na tela.
"""
import argparse
import collections
import re
from pathlib import Path

PASTA_DICIONARIOS = Path(__file__).with_name('dicionarios')
# arquivo conhecido -> (dicionário do catálogo, loja)
REFERENCIA_DICIONARIO = {}
if (PASTA_DICIONARIOS / 'lojas_referencia.csv').exists():
    for _l in (PASTA_DICIONARIOS / 'lojas_referencia.csv').read_text(encoding='utf-8').splitlines():
        if _l.strip() and not _l.startswith('#') and not _l.startswith('arquivo;'):
            _a, _d, _n = (_l.split(';') + ['', ''])[:3]
            REFERENCIA_DICIONARIO[_a.strip().upper()] = (_d.strip(), _n.strip())
REFERENCIAS_PADRAO = Path(__file__).resolve().parents[2] / 'PRICETABS'
INICIO_REGISTRO = re.compile(r'^\d{1,14}\|')
PRECO_REAIS = re.compile(r'^\d{1,3}(\.?\d{3})*,\d{2}$')
PRECO_CENTAVOS = re.compile(r'^\d{1,10}$')


# ------------------------------------------------------------------------------------------------
# Leitura (mesmas regras do leitor do backend: emenda linhas quebradas, ignora as inválidas)
# ------------------------------------------------------------------------------------------------
def ler(caminho: Path):
    bruto = caminho.read_bytes()
    texto = bruto.decode('latin-1')
    linhas = texto.splitlines()
    registros, invalidas, emendadas = [], [], 0
    i = 0
    while i < len(linhas):
        linha = linhas[i].rstrip()
        i += 1
        if not linha.strip():
            continue
        while not re.match(r'^\d{1,14}\|.*\|[\d.,]+\|\|?$', linha) and i < len(linhas) \
                and linhas[i].strip() and not INICIO_REGISTRO.match(linhas[i]):
            linha += linhas[i].rstrip()
            i += 1
            emendadas += 1
        sem_fim = linha[:-2] if linha.endswith('||') else linha[:-1] if linha.endswith('|') else None
        partes = sem_fim.split('|') if sem_fim is not None else []
        if len(partes) != 3 or not partes[0].strip().isdigit() or not partes[1].strip():
            invalidas.append(linha[:60])
            continue
        preco = partes[2].strip()
        if PRECO_REAIS.match(preco):
            centavos = int(preco.replace('.', '').replace(',', ''))
        elif PRECO_CENTAVOS.match(preco):
            centavos = int(preco)
        else:
            invalidas.append(linha[:60])
            continue
        registros.append((partes[0].strip(), partes[1].rstrip(), partes[1].strip(), centavos, preco))
    return bruto, linhas, registros, invalidas, emendadas


def canonico(c: str) -> str:
    s = c.lstrip('0')
    return s if len(s) > 13 else s.zfill(13)


def dv_ean(corpo: str) -> int:
    soma = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(corpo)))
    return (10 - soma % 10) % 10


# ------------------------------------------------------------------------------------------------
# Dicionários (mesmo algoritmo de expandir_com_dicionario no banco, scripts/027)
# ------------------------------------------------------------------------------------------------
def ler_dicionario(arquivo: Path) -> dict:
    regras = {}
    for linha in arquivo.read_text(encoding='utf-8').splitlines():
        if not linha.strip() or linha.startswith('#') or linha.startswith('abreviacao;'):
            continue
        partes = linha.split(';')
        termo = ' '.join(partes[0].upper().split())
        setor = partes[2].strip() if len(partes) > 2 else ''
        regras[termo] = '' if setor else ' '.join(partes[1].upper().split())
    return regras


def expandir(descricao: str, dic: dict, cortada: bool) -> str:
    palavras = []
    for w in descricao.split():
        if re.match(r'(?i)^[CS]/', w):
            palavras.append('COM' if w[0].upper() == 'C' else 'SEM')
            if len(w) > 2:
                palavras.append(w[2:])
        else:
            palavras.append(w)
    total = len(palavras)
    limite = total - 1 if cortada and len(descricao.strip()) >= 16 and total > 1 else total
    fim_numero = bool(re.search(r'\s\d{2}$', descricao.strip()))
    saida, i = [], 0
    while i < total:
        achou = False
        if i < limite:
            for n in range(min(3, limite - i), 0, -1):
                chave = ' '.join(palavras[i:i + n]).upper()
                candidatas = []
                if fim_numero and i == 0:
                    candidatas.append('^' + chave + '#FIM_NUMERO')
                if fim_numero:
                    candidatas.append(chave + '#FIM_NUMERO')
                if i == 0:
                    candidatas.append('^' + chave)
                candidatas.append(chave)
                expansao = next((dic[c] for c in candidatas if c in dic), None)
                if expansao is not None:
                    if expansao:
                        saida.append(expansao)
                    i += n
                    achou = True
                    break
        if not achou:
            saida.append(palavras[i])
            i += 1
    return ' '.join(saida)


def combinar(*camadas: dict) -> dict:
    resultado = {}
    for camada in reversed(camadas):  # a mais específica (primeira) vence
        resultado.update(camada)
    return resultado


# ------------------------------------------------------------------------------------------------
def analisar(caminho: Path, referencias: Path) -> str:
    bruto, linhas, registros, invalidas, emendadas = ler(caminho)
    md = [f'# Análise de loja nova — `{caminho.name}`', '']
    total = len(registros)

    # 1. Formato
    larguras = collections.Counter(len(r[1]) for r in registros)
    largura_tipica = larguras.most_common(1)[0][0] if registros else 0
    cortada = largura_tipica <= 20
    reais = sum(1 for r in registros if ',' in r[4])
    termina_duplo = sum(1 for l in linhas if l.rstrip().endswith('||'))
    nao_ascii = sum(1 for b in bruto if b > 127)
    md += ['## 1. Formato', '',
           f'- Registros válidos: **{total}** · linhas inválidas: **{len(invalidas)}** '
           f'({100 * len(invalidas) / max(total + len(invalidas), 1):.2f}% — limite da carga: 2%)',
           f'- Registros quebrados em duas linhas (emendados): **{emendadas}**',
           f'- Preço: **{"reais com vírgula (12,99)" if reais > total / 2 else "centavos (0000001299)"}** · linhas terminadas em "||": {termina_duplo}',
           f'- Largura da descrição mais comum: **{largura_tipica}** posições → '
           + ('**descrição CORTADA** (ficha "PRICETAB 16 posições": não agrupar, não expandir a última palavra)'
              if cortada else 'descrição completa (ficha "PRICETAB 40 posições")'),
           f'- Bytes acima de 127 (acentos/caracteres especiais em Latin-1): {nao_ascii}', '']
    if invalidas:
        md += ['Exemplos de linhas inválidas:', ''] + [f'    {l}' for l in invalidas[:5]] + ['']

    # 2. Códigos
    tamanhos = collections.Counter(len(r[0]) for r in registros)
    por_canonico = collections.defaultdict(list)
    for r in registros:
        por_canonico[canonico(r[0])].append(r)
    internos = [r for r in registros if r[0].startswith('0000') and 2 <= len(r[0].lstrip('0')) <= 7]
    dv_ok = sum(1 for r in internos if dv_ean(r[0].lstrip('0')[:-1]) == int(r[0][-1]))
    tam_internos = collections.Counter(len(r[0].lstrip('0')) for r in internos)
    ean8 = sum(1 for r in registros if len(r[0].lstrip('0')) == 8 and len(r[0]) > 8)
    pares = sum(1 for v in por_canonico.values() if len({len(x[0]) for x in v}) > 1)
    com_kg = sum(1 for r in internos if re.search(r'(?i)(^|\s)kg(\s|$)', r[2]))
    md += ['## 2. Códigos', '',
           f'- Tamanhos: {", ".join(f"{k} dígitos: {v}" for k, v in sorted(tamanhos.items()))}',
           f'- Códigos internos (balança/casa): **{len(internos)}** · com "kg" na descrição: {com_kg} · '
           f'dígito verificador confere: **{dv_ok} ({100 * dv_ok / max(len(internos), 1):.0f}%)** · '
           f'dígitos significativos: {dict(sorted(tam_internos.items()))}',
           f'  → etiqueta: {"interno COM dígito verificador" if dv_ok > len(internos) * 0.9 else "interno SEM dígito verificador (confirmar)"};'
           f' código de até {max(tam_internos) - (1 if dv_ok > len(internos) * 0.9 else 0) if tam_internos else "?"} dígitos — **confirmar com uma etiqueta real da loja**',
           f'- EAN-8 completado com zeros: {ean8} · pares 13 x 14 dígitos (viram um código só): **{pares}**', '']

    # 3. Duplicados e preços
    repetidos = {k: v for k, v in por_canonico.items() if len(v) > 1}
    casos = collections.Counter()
    exemplos_conflito = []
    for k, v in repetidos.items():
        positivos = {x[3] for x in v if x[3] > 0}
        if len({x[3] for x in v}) == 1:
            casos['preço igual'] += 1
        elif len(positivos) == 1:
            casos['um com preço, outro 0,00'] += 1
        else:
            casos['PREÇOS DIFERENTES (ficam sem preço)'] += 1
            if len(exemplos_conflito) < 3:
                exemplos_conflito.append(f'{k} {v[0][2]}: ' + ' x '.join(f'{x[3] / 100:.2f}' for x in v))
    zeros = sum(1 for k, v in por_canonico.items() if all(x[3] == 0 for x in v))
    por_descricao = collections.Counter(r[2] for r in registros)
    auxiliares = sum(1 for d, n in por_descricao.items() if n > 1)
    md += ['## 3. Duplicados e preços', '',
           f'- Códigos repetidos no arquivo: **{len(repetidos)}** → ' + (', '.join(f'{k}: {v}' for k, v in casos.items()) or 'nenhum'),
           f'- Preço 0,00 (ficam "sem preço"): **{zeros}**',
           f'- Descrições com mais de um código: {auxiliares} '
           + ('(na descrição cortada isso NÃO indica código auxiliar: produtos diferentes ficam com o mesmo texto)' if cortada
              else '(códigos auxiliares do mesmo produto: o app agrupa)'), '']
    if exemplos_conflito:
        md += ['Exemplos de preços diferentes no mesmo código:', ''] + [f'    {e}' for e in exemplos_conflito] + ['']

    # 4. Siglas candidatas
    primeiras = collections.Counter(r[2].split()[0].upper() for r in registros if r[2].split())
    siglas = [(w, n) for w, n in primeiras.most_common(200) if len(w) <= 3 and w.isalpha() and n >= max(20, total * 0.005)]
    md += ['## 4. Primeiras palavras curtas e frequentes — sigla de seção ou abreviação? (confirmar)', '',
           'Sigla de seção (ex.: HF = hortifrúti) sai da descrição e define o setor; abreviação vira palavra.', '']
    todos = {'comum': ler_dicionario(PASTA_DICIONARIOS / 'comum.csv')} if (PASTA_DICIONARIOS / 'comum.csv').exists() else {}
    todos.update({a.stem: ler_dicionario(a) for a in sorted(PASTA_DICIONARIOS.glob('*.csv')) if a.stem != 'comum'})
    for w, n in siglas[:12]:
        exemplos = [r[2] for r in registros if r[2].upper().startswith(w + ' ')][:3]
        conhecida = []
        for nome, dic in todos.items():
            for chave in ('^' + w, w):
                if chave in dic:
                    conhecida.append(f'{nome}: ' + ('SIGLA DE SEÇÃO' if dic[chave] == '' else dic[chave]))
                    break
        md.append(f'- **{w}** ({n}): ' + ' · '.join(exemplos)
                  + ('  — já conhecida como ' + '; '.join(conhecida) if conhecida else '  — **desconhecida**'))
    if not siglas:
        md.append('- nenhuma')
    md.append('')

    # 5 e 6. Dicionários
    arquivos = sorted(PASTA_DICIONARIOS.glob('*.csv'))
    comum = ler_dicionario(PASTA_DICIONARIOS / 'comum.csv') if (PASTA_DICIONARIOS / 'comum.csv').exists() else {}
    catalogos = {a.stem: ler_dicionario(a) for a in arquivos if a.stem != 'comum'}
    descricoes = sorted({r[2] for r in registros})
    tokens = collections.Counter()
    for d in descricoes:
        ws = d.split()
        for w in (ws[:-1] if cortada and len(d) >= 16 and len(ws) > 1 else ws):
            if re.fullmatch(r'[A-Za-z]{2,}', w):
                tokens[w.upper()] += 1
    md += ['## 5. Palavras mais frequentes (candidatas a abreviação) e quem as conhece', '',
           '| Palavra | Descrições | Comum | ' + ' | '.join(catalogos) + ' |', '|---|---|---|' + '---|' * len(catalogos)]
    for w, n in tokens.most_common(40):
        def sentido(d):
            for chave in (w, '^' + w):
                if chave in d:
                    return d[chave] or '(sigla)'
            return '·'
        md.append(f'| {w} | {n} | {sentido(comum)} | ' + ' | '.join(sentido(c) for c in catalogos.values()) + ' |')
    md.append('')

    md += ['## 6. Como cada dicionário pronto se sai (descrições expandidas)', '',
           '| Dicionário | Descrições que mudam | % |', '|---|---|---|']
    resultados = {}
    so_comum = sum(1 for d in descricoes if expandir(d, comum, cortada).upper() != d.upper())
    md.append(f'| só Comum | {so_comum} | {100 * so_comum / max(len(descricoes), 1):.1f}% |')
    for nome, cat in catalogos.items():
        dic = combinar(cat, comum)
        mudam = sum(1 for d in descricoes if expandir(d, dic, cortada).upper() != d.upper())
        resultados[nome] = mudam
        md.append(f'| Comum + {nome} | {mudam} | {100 * mudam / max(len(descricoes), 1):.1f}% |')
    md.append('')
    # Abreviações frequentes NESTE arquivo que mudam de sentido entre os catálogos.
    conflitos = []
    for w, n in tokens.most_common(300):
        sentidos = {}
        for nome, cat in catalogos.items():
            s = cat.get(w) or cat.get('^' + w)
            if s:
                sentidos[nome] = s
        if len(set(sentidos.values())) > 1 and n >= 5:
            conflitos.append((w, n, sentidos))
    md += ['### Abreviações deste arquivo com sentido DIFERENTE entre os dicionários (decidir caso a caso)', '']
    for w, n, sentidos in conflitos[:15]:
        exemplos = [d for d in descricoes if re.search(rf'(^|\s){re.escape(w)}(\s|$)', d, re.I)][:3]
        md.append(f'- **{w}** ({n} descrições): ' + ' · '.join(f'{k} = {v}' for k, v in sentidos.items())
                  + f' — ex.: {" · ".join(exemplos)}')
    if not conflitos:
        md.append('- nenhuma')
    md.append('')

    # 7. Semelhança com lojas conhecidas
    md += ['## 7. Semelhança com os PRICETABs já conhecidos', '',
           '| Arquivo | Códigos em comum | Destes, com a MESMA descrição | Mesmo preço |', '|---|---|---|---|']
    meus = {canonico(r[0]): (r[2], r[3]) for r in registros}
    semelhanca = {}
    if referencias and referencias.exists():
        for ref in sorted(referencias.glob('*.TXT')) + sorted(referencias.glob('*.txt')):
            if ref.resolve() == caminho.resolve() or ref.read_bytes() == bruto:
                continue  # o próprio arquivo (ou uma cópia idêntica dele)
            _, _, regs_ref, _, _ = ler(ref)
            dele = {canonico(r[0]): (r[2], r[3]) for r in regs_ref}
            comuns = set(meus) & set(dele)
            mesma = sum(1 for c in comuns if meus[c][0] == dele[c][0])
            mesmo_preco = sum(1 for c in comuns if meus[c][1] == dele[c][1])
            semelhanca[ref.name] = (len(comuns), mesma)
            md.append(f'| {ref.name} | {len(comuns)} ({100 * len(comuns) / max(len(meus), 1):.0f}%) | '
                      f'{mesma} ({100 * mesma / max(len(comuns), 1):.0f}%) | {mesmo_preco} |')
    md.append('')

    # 8. Recomendação
    md += ['## 8. Recomendação', '']
    mesma_origem = [(n, c, m) for n, (c, m) in semelhanca.items() if c > len(meus) * 0.5 and m > c * 0.9]
    melhor = max(resultados, key=resultados.get) if resultados else None
    if mesma_origem:
        n, c, m = max(mesma_origem, key=lambda x: x[2])
        dicionario, loja = REFERENCIA_DICIONARIO.get(n.upper(), ('?', '?'))
        md.append(f'- **Mesmo padrão de {n}** ({loja}): {100 * c / len(meus):.0f}% dos códigos em comum e {100 * m / max(c, 1):.0f}% '
                  'com a MESMA descrição → mesma rede/sistema. **Reaproveitar a ficha de formato e o dicionário '
                  f'"{dicionario}"** (conferir as seções 5 e 6; ajustes só desta loja vão na camada da loja).')
    else:
        md.append('- **Padrão novo** (nenhum arquivo conhecido com a mesma descrição para os mesmos códigos) → '
                  '**criar um dicionário EXCLUSIVO** para esta loja, partindo da camada Comum e das palavras da seção 5.')
        if melhor:
            md.append(f'- Como ponto de partida, o dicionário que mais expande aqui é **{melhor}** '
                      f'({resultados[melhor]} descrições) — usar só como referência, revisando cada regra.')
    md.append(f'- Ficha de formato: **{"PRICETAB 16 posições" if cortada else "PRICETAB 40 posições"}**.')
    if siglas:
        md.append(f'- Confirmar o significado das primeiras palavras curtas da seção 4: {", ".join(w for w, _ in siglas[:6])}.')
    if conflitos:
        md.append(f'- Atenção às abreviações ambíguas: {", ".join(w for w, _, _ in conflitos[:8])}.')
    md.append('- Pedir uma etiqueta real da balança (com a linha do PRICETAB) para confirmar o layout.')
    return '\n'.join(md) + '\n'


if __name__ == '__main__':
    p = argparse.ArgumentParser(description='Análise do PRICETAB de uma loja nova')
    p.add_argument('arquivo', type=Path)
    p.add_argument('--referencias', type=Path, default=REFERENCIAS_PADRAO,
                   help='pasta com os PRICETABs das lojas conhecidas (padrão: PRICETABS/ na raiz do projeto)')
    args = p.parse_args()
    relatorio = analisar(args.arquivo, args.referencias)
    destino = args.arquivo.with_name(args.arquivo.stem + '_analise.md')
    destino.write_text(relatorio, encoding='utf-8')
    print(relatorio[relatorio.index('## 8. Recomendação'):])
    print(f'Relatório completo: {destino}')
