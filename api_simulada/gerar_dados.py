"""Gera dados.json da API simulada (loja 5 "Alfa Online" do laboratório — regra 14 do multi-loja).

Base: base_loja1.json (produtos ativos da loja 1 do DES, exportados do banco: descrição expandida
pelo dicionário = "descrição completa"; setor do categorizador = "seção"). Preço = PRICE2 + 20%.
Os códigos auxiliares do mesmo produto (mesmo grupo) viram UM produto com vários códigos de barras.

Acrescenta, de propósito, o que uma API real costuma trazer e as armadilhas que o nosso lado tem
de aguentar:
  - promoção válida (inclusive a Coca-Cola 1L), vencida e futura; preço de atacado; condição em
    texto ("Leve 3, pague 2");
  - produtos inativos (ativo=false);
  - código de barras como NÚMERO (perde os zeros da frente) e preço como TEXTO com ponto;
  - o produto da etiqueta real do técnico (CARNE BOVINA PATINHO, código interno 266, R$ 39,98/kg).

Uso: python gerar_dados.py   (gera dados.json ao lado; reexecutável, sempre igual: semente fixa)
"""
import json
import os
import random
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

AQUI = os.path.dirname(os.path.abspath(__file__))
random.seed(20261006)
hoje = date.today()

base = json.load(open(os.path.join(AQUI, 'base_loja1.json'), encoding='utf-8'))
grupos = {}
for p in base:
    grupos.setdefault(p['grupo'], []).append(p)


def reais(centavos):
    return float((Decimal(centavos) * Decimal('1.20') / 100).quantize(Decimal('0.01'), ROUND_HALF_UP))


itens = []
for n, (grupo, produtos) in enumerate(sorted(grupos.items()), start=1):
    principal = next((p for p in produtos if p['codigo'] == grupo), produtos[0])
    codigos = [principal['codigo_origem'] or principal['codigo']] + \
              [p['codigo_origem'] or p['codigo'] for p in produtos if p is not principal]
    itens.append({
        'codigoInterno': str(100000 + n),
        'codigosBarras': codigos,
        'descricao': principal['descricao'],
        'secao': principal['secao'],
        'unidade': 'KG' if principal['kg'] else 'UN',
        'precoVenda': reais(principal['preco']),
        'promocao': None,
        'precoAtacado': None,
        'condicao': None,
        'ativo': True,
        'alteradoEm': (hoje - timedelta(days=random.randint(1, 60))).isoformat(),
    })

por_codigo = {i['codigosBarras'][0]: i for i in itens}
comuns = [i for i in itens if i['unidade'] == 'UN' and i['precoVenda'] > 2]
random.shuffle(comuns)


def promocao(item, desconto, inicio, fim):
    item['promocao'] = {'preco': round(item['precoVenda'] * (1 - desconto), 2),
                        'inicio': inicio.isoformat(), 'fim': fim.isoformat()}


# Coca-Cola 1L em promoção válida (cenário L5.1: "de R$ 9,59 por R$ 8,49").
coca = por_codigo.get('7894900011715')
if coca:
    coca['promocao'] = {'preco': 8.49, 'inicio': (hoje - timedelta(days=2)).isoformat(),
                        'fim': (hoje + timedelta(days=7)).isoformat()}
for item in comuns[0:40]:
    promocao(item, random.choice([0.10, 0.15, 0.20]), hoje - timedelta(days=3), hoje + timedelta(days=10))
for item in comuns[40:45]:   # vencidas: não podem aparecer
    promocao(item, 0.25, hoje - timedelta(days=20), hoje - timedelta(days=1))
for item in comuns[45:50]:   # futuras: ainda não podem aparecer
    promocao(item, 0.25, hoje + timedelta(days=2), hoje + timedelta(days=12))
for item in comuns[50:60]:
    item['precoAtacado'] = {'preco': round(item['precoVenda'] * 0.9, 2), 'quantidadeMinima': random.choice([3, 6, 12])}
for item in comuns[60:70]:
    item['condicao'] = random.choice(['Leve 3, pague 2', '2ª unidade com 15% de desconto', 'Leve 4, pague 3'])
for item in comuns[70:75]:
    item['ativo'] = False
# Armadilhas de formato.
for item in comuns[75:175]:
    item['codigosBarras'][0] = int(item['codigosBarras'][0])            # número: perde os zeros
for item in comuns[175:275]:
    item['precoVenda'] = f"{item['precoVenda']:.2f}"                     # texto com ponto

# Etiqueta real do técnico: 2 000266 00680 6 -> 0,170 kg x R$ 39,98 = R$ 6,80.
itens.append({'codigoInterno': '266', 'codigosBarras': ['0000000000266'], 'descricao': 'CARNE BOVINA PATINHO',
              'secao': 'AÇOUGUE', 'unidade': 'KG', 'precoVenda': 39.98, 'promocao': None, 'precoAtacado': None,
              'condicao': None, 'ativo': True, 'alteradoEm': hoje.isoformat()})

json.dump(itens, open(os.path.join(AQUI, 'dados.json'), 'w', encoding='utf-8'), ensure_ascii=False)
print(f'{len(itens)} produtos; com promoção: {sum(1 for i in itens if i["promocao"])}; inativos: '
      f'{sum(1 for i in itens if not i["ativo"])}; Coca 1L: {coca and coca["precoVenda"]} por {coca and coca["promocao"]["preco"]}')
