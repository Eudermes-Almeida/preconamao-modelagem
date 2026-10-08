"""Gera dados_rpinfo.json da API simulada RPInfo (loja 5 "Alfa Online" do laboratório).

Mesma base da API simulada v1 (base_loja1.json: produtos da loja 1 do DES, preço = PRICE2 + 20%),
agora no formato REAL da API RPInfo ("RP Services"), copiado das respostas da homologação em
laboratorio/loja5_api_rpinfo/respostas (07/10/2026):
  - produto com os 198 campos (modelo_produto_rpinfo.json: nomes reais, valores neutros), campos
    em PascalCase; Codigo interno sequencial (a paginação é pelo último Codigo);
  - códigos auxiliares do mesmo produto em codBarrasAlterados[] (precoVenda 0 = mesmo preço);
  - oferta: Oferta "S", Preco = PrecoPDV = preço da oferta, PrecoNormal = "de", DtIniOferta e
    DataOferta (fim) em dd-MM-yyyy; Departamento sempre vazio (só CodigoDepartamento);
  - DataHoraManutencao "dd/MM/yyyy HH:mm:ss.SSS".

"Defeitos" reais acrescentados de propósito (o nosso lado tem de aguentar):
  - ofertas VENCIDAS ainda com Oferta "S" (a RPInfo não filtra validade; ex. real: café de 2023);
  - Preco diferente de PrecoPDV (ex. real: Sazón 97,97 x 5,97) — o caixa cobra o PrecoPDV;
  - descrição "NÃO ENCONTRADO NO RP ÁTOMO" (6% da amostra real) no lugar da descrição;
  - Funcao "KG"/"LT"/"VM;V4;KG" em produto vendido por unidade (é a unidade do preço por kg da
    etiqueta, não venda a peso); quem diz balança é Balanca = "P" (pesável, resposta 14: açougue,
    código interno COM dígito verificador e TipoEmbalagem "KG");
  - descrição com "*" na frente e com o próprio Codigo no fim (resposta 14);
  - Preco 0 com Bloqueado "S" e PrecoPDV preenchido (resposta 14; significado a confirmar);
  - SetorLoja como "R1", "R52", "ILHA11" além de "D07";
  - código de CAIXA (DUN-14, fatorEmbalagem 12, sem preço próprio) entre os auxiliares, e
    auxiliar com preço próprio (precoVenda > 0);
  - produtos inativos (só aparecem na rota sem /ativos).

Uso: python gerar_dados_rpinfo.py   (reexecutável, sempre igual: semente fixa; datas relativas a hoje)
"""
import json
import os
import random
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

AQUI = os.path.dirname(os.path.abspath(__file__))
random.seed(20261008)
hoje = date.today()

base = json.load(open(os.path.join(AQUI, 'base_loja1.json'), encoding='utf-8'))
modelo = json.load(open(os.path.join(AQUI, 'modelo_produto_rpinfo.json'), encoding='utf-8'))

# Departamentos no estilo da RPInfo (códigos de 3 dígitos). Os nomes NÃO batem de propósito com
# os setores do nosso layout em vários casos (como numa loja real): aí vale o categorizador.
DEPARTAMENTOS = [
    ('101', 'Comodities'), ('102', 'Mercearia Salgada'), ('103', 'Mercearia Doce'), ('104', 'Perecíveis'),
    ('105', 'Hortifrutigranjeiros'), ('106', 'Bebidas'), ('108', 'Açougue'), ('109', 'Padaria Produção Local'),
    ('110', 'Frios e Laticínios'), ('111', 'Sazonal'), ('115', 'Congelados'), ('116', 'Pescados'),
    ('201', 'Perfumaria'), ('202', 'Higiene e Beleza'), ('203', 'Limpeza'), ('204', 'Bazar'),
    ('205', 'Pet Shop'), ('206', 'Infantil'), ('207', 'Farmácia'), ('208', 'Bomboniere'), ('299', 'Diversos'),
]
DEPTO_DA_SECAO = {
    'HIGIENE E BELEZA': ['201', '202'], 'BEBIDAS NÃO ALCOÓLICAS': ['106'], 'BEBIDAS ALCOÓLICAS': ['106'],
    'MERCEARIA': ['102', '103', '101'], 'FRIOS E LATICÍNIOS': ['110', '104'], 'BOMBONIERE': ['208', '103'],
    'HORTIFRÚTI': ['105'], 'LIMPEZA': ['203'], 'AÇOUGUE': ['108'], 'CONGELADOS E RESFRIADOS': ['115', '104'],
    'BAZAR': ['204'], 'PADARIA': ['109'], 'BEM ESTAR': ['202'], 'INFANTIL': ['206'], 'PET SHOP': ['205'],
    'FARMÁCIA/DROGARIA': ['207'], 'PESCADOS': ['116'], 'ECOLOGIA': ['204'],
}
NAO_ENCONTRADO = 'NÃO ENCONTRADO NO RP ÁTOMO'


def reais(centavos):
    return float((Decimal(centavos) * Decimal('1.20') / 100).quantize(Decimal('0.01'), ROUND_HALF_UP))


def descricao_rpinfo(texto):
    # A RPInfo traz "Atum Em Conserva Coqueiro 170G": palavras com inicial maiúscula, medidas em caixa alta.
    return ' '.join(p.capitalize() if p.isalpha() else p.upper() for p in texto.split())


def dd_mm_aaaa(d):
    return d.strftime('%d-%m-%Y')


def manutencao(d):
    instante = datetime(d.year, d.month, d.day, random.randint(7, 21), random.randint(0, 59), random.randint(0, 59))
    return instante.strftime('%d/%m/%Y %H:%M:%S.') + f'{random.randint(0, 999):03d}'


grupos = {}
for p in base:
    grupos.setdefault(p['grupo'], []).append(p)

produtos = []
codigo_interno = 100100
for grupo, linhas in sorted(grupos.items()):
    principal = next((p for p in linhas if p['codigo'] == grupo), linhas[0])
    auxiliares = [p['codigo_origem'] or p['codigo'] for p in linhas if p is not principal]
    codigo_interno += random.choice([8, 16, 24, 32])         # na real os códigos internos pulam
    preco = reais(principal['preco'])
    secao = principal['secao']
    depto = random.choice(DEPTO_DA_SECAO.get(secao, ['299']))
    descricao = descricao_rpinfo(principal['descricao'])
    item = dict(modelo)
    item.update({
        'Codigo': codigo_interno, 'SKU': codigo_interno,
        'CodigoBarras': principal['codigo_origem'] or principal['codigo'],
        'Descricao': descricao, 'DescricaoPDV': principal['descricao'][:20].upper(),
        'DescricaoCliente': descricao[:30],
        'Preco': preco, 'PrecoPDV': preco, 'PrecoLista': preco, 'PrecoEtiqueta': preco, 'PrecoCartaz': preco,
        'Grupo': str(10000 + int(depto)), 'CodigoUnidade': '001', 'CodigoDepartamento': depto,
        'SetorLoja': random.choice([random.choice('ABCDEFGHJKLMV') + f'{random.randint(1, 12):02d}',
                                    f'R{random.randint(1, 60)}', f'ILHA{random.randint(1, 15)}']),
        'Funcao': random.choice(['KG', 'VM;V4;KG', 'VE;KG']) if principal['kg'] else random.choice(['UN', 'UN', 'KG', 'LT']),
        'Balanca': 'P' if principal['kg'] else 'N',
        'TipoEmbalagem': 'KG' if principal['kg'] else random.choice(['CX', 'UN']), 'QuantidadeEmbalagem': 12,
        'codBarrasAlterados': [
            {'codigo': random.randint(1000, 9999), 'codigoBarras': c, 'numPreco': 0, 'fatorEmbalagem': 0,
             'precoVenda': 0, 'unidadeMedida': 0, 'precoVendaUnidadeMedida': 0,
             'data': (hoje - timedelta(days=random.randint(100, 2000))).strftime('%d/%m/%Y')}
            for c in auxiliares],
        'DataHoraManutencao': manutencao(hoje - timedelta(days=random.randint(1, 60))),
    })
    item['_secaoBase'] = secao
    produtos.append(item)

por_codigo = {p['CodigoBarras']: p for p in produtos}
comuns = [p for p in produtos if p['Balanca'] == 'N' and p['Preco'] > 2 and not p['CodigoBarras'].startswith('0000')
          and p['CodigoBarras'] != '7894900011715']
random.shuffle(comuns)


def ofertar(p, preco_oferta, inicio, fim):
    p.update({'Oferta': 'S', 'PrecoNormal': p['Preco'], 'Preco': preco_oferta, 'PrecoPDV': preco_oferta,
              'PrecoEtiqueta': preco_oferta, 'DtIniOferta': dd_mm_aaaa(inicio), 'DataOferta': dd_mm_aaaa(fim)})


# Coca-Cola 1L em oferta válida (cenário L5.1: "de R$ 9,59 por R$ 8,49").
coca = por_codigo.get('7894900011715')
if coca:
    ofertar(coca, 8.49, hoje - timedelta(days=2), hoje + timedelta(days=7))
for p in comuns[0:40]:                                    # ofertas válidas
    ofertar(p, round(p['Preco'] * (1 - random.choice([0.10, 0.15, 0.20])), 2), hoje - timedelta(days=3), hoje + timedelta(days=10))
for p in comuns[40:45]:                                   # VENCIDAS e ainda "S" (defeito real)
    ofertar(p, round(p['Preco'] * 0.75, 2), date(2023, 10, 1), date(2023, 10, 15))
for p in comuns[45:50]:                                   # Preco x PrecoPDV (defeito real: Sazón)
    p['Preco'] = round(p['PrecoPDV'] * 12 + 1.21, 2)
for p in comuns[50:60]:                                   # placeholder no lugar da descrição
    p['Descricao'] = NAO_ENCONTRADO
for p in comuns[60:65]:                                   # inativos (só na rota sem /ativos)
    p['Ativo'] = False
for p in comuns[65:75]:                                   # caixa (DUN-14) entre os auxiliares, sem preço próprio
    p['codBarrasAlterados'].append({'codigo': random.randint(1000, 9999), 'codigoBarras': '1' + p['CodigoBarras'][:12] + '0',
                                    'numPreco': 0, 'fatorEmbalagem': 12, 'precoVenda': 0, 'unidadeMedida': 0,
                                    'precoVendaUnidadeMedida': 0, 'data': '01/01/2024'})
for p in comuns[80:90]:                                   # "*" na frente / Codigo no fim da descrição
    p['Descricao'] = '*' + p['Descricao'][0].lower() + p['Descricao'][1:]
for p in comuns[90:95]:
    p['Descricao'] = f"{p['Descricao']}  {p['Codigo']}"
for p in comuns[95:100]:                                  # Preco 0 e Bloqueado "S" (PrecoPDV preenchido)
    p['Preco'] = 0
    p['Bloqueado'] = 'S'
for p in comuns[75:80]:                                   # auxiliar com preço próprio (ex.: leve 2)
    p['codBarrasAlterados'].append({'codigo': random.randint(1000, 9999), 'codigoBarras': '789' + str(random.randint(10**9, 10**10 - 1)),
                                    'numPreco': 2, 'fatorEmbalagem': 2, 'precoVenda': round(p['PrecoPDV'] * 1.8, 2),
                                    'unidadeMedida': 0, 'precoVendaUnidadeMedida': 0, 'data': '01/01/2024'})

# Etiqueta real do técnico: 2 000266 00680 6 -> 0,170 kg x R$ 39,98 = R$ 6,80. Na RPInfo o código
# interno vem com o dígito verificador (resposta 14): 266 -> 0000000002660.
patinho = dict(modelo)
patinho.update({'Codigo': codigo_interno + 8, 'SKU': codigo_interno + 8, 'CodigoBarras': '0000000002660',
                'Descricao': 'Carne Bovina Patinho', 'DescricaoPDV': 'CARNE BOV PATINHO', 'Preco': 39.98,
                'PrecoPDV': 39.98, 'PrecoLista': 39.98, 'PrecoEtiqueta': 39.98, 'CodigoUnidade': '001',
                'CodigoDepartamento': '108', 'Grupo': '10108', 'SetorLoja': 'R1', 'Funcao': 'KG', 'Balanca': 'P',
                'TipoEmbalagem': 'KG',
                'codBarrasAlterados': [], 'DataHoraManutencao': manutencao(hoje)})
produtos.append(patinho)

for p in produtos:
    p.pop('_secaoBase', None)

dados = {'unidades': [{'codigo': '001', 'nome': 'ALFA ONLINE LABORATORIO LTDA', 'cnpj': '11222333000181',
                       'nomeReduzido': 'ALFA ONLINE', 'identAtividade': 'SM'}],
         'departamentos': [{'codigo': c, 'descricao': d} for c, d in DEPARTAMENTOS],
         'produtos': produtos}
json.dump(dados, open(os.path.join(AQUI, 'dados_rpinfo.json'), 'w', encoding='utf-8'), ensure_ascii=False)
print(f'{len(produtos)} produtos; ofertas "S": {sum(1 for p in produtos if p["Oferta"] == "S")} '
      f'(5 vencidas); inativos: {sum(1 for p in produtos if not p["Ativo"])}; '
      f'"{NAO_ENCONTRADO}": {sum(1 for p in produtos if p["Descricao"] == NAO_ENCONTRADO)}; '
      f'com auxiliares: {sum(1 for p in produtos if p["codBarrasAlterados"])}; '
      f'Coca 1L: {coca and (coca["PrecoNormal"], coca["PrecoPDV"])}')
