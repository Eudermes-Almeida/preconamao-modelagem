// API SIMULADA no formato REAL da RPInfo ("RP Services", servidor 5.0.6.117) — SÓ LABORATÓRIO
// (loja 5 do multi-loja). Copia o que foi visto na homologação em 07/10/2026 (respostas em
// laboratorio/loja5_api_rpinfo/respostas): rotas, envelope { response: { status, appVersion,
// messages, ... } }, token no cabeçalho "token" (não Bearer), 401 SEM envelope, paginação pelo
// último Codigo (100 por página), produtos em PascalCase e o resto em camelCase.
//
// Confirmado na homologação em 08/10 (respostas 09 a 15): fim da paginação = lista vazia com
// status ok; produto inexistente = status "error" com a mensagem abaixo; carga incremental por
// dataHoraManutencao; erro interno = status "error" com "Falha ao carregar dados", a exceção e o
// StackTrace; excluídos em response.excluidos (itens com "usuarioExclusão", com acento); ofertas
// paginadas por ?lastId= (código do último item); pesável = Balanca "P"; senha errada = HTTP 500
// com {"error", "stackTrace"}. Pontos marcados "HIPÓTESE" ainda não foram vistos (código HTTP dos
// erros "de negócio").
//
// Sem dependências (só Node). Uso: node servidor_rpinfo.js   (porta 18091; dados em
// dados_rpinfo.json, gerados por gerar_dados_rpinfo.py; usuário e senha em credenciais.json).
// No laboratório roda no container "api-rpinfo" (sobe sozinho com o Docker):
//   docker run -d --name api-rpinfo --restart unless-stopped -p 18091:18091
//     -v <esta pasta>:/app -w /app node:20-alpine node servidor_rpinfo.js
// Depois de mudar este arquivo ou os dados: docker restart api-rpinfo.
//
// Rotas (as mesmas da RPInfo):
//   POST /v1.2/auth                                     {"usuario","senha"} -> content.token (vence em 1 h)
//   GET  /v1.6/unidades
//   GET  /v1.1/departamentos
//   GET  /v3.2/produtounidade/listaprodutos/{lastID}/unidade/{CNPJ}/detalhado[/ativos][/dataHoraManutencao/{dd-MM-yyyy HH:mm:ss}]?limit=100
//   GET  /v3.2/produtounidade/{codigoBarras}/unidade/{CNPJ}/detalhado/consultarcodigobarras
//   GET  /v1.0/produtounidade/ofertas?unidade=001&lastId=&limit=
//   GET  /v1.1/produto/excluidos/lastid/{lastid}/dataexclusao/{dd-MM-yyyy}
// Botões de laboratório (para provocar situações sem editar arquivos):
//   POST /lab/fora-do-ar     {"ativo": true|false}   API responde 503 em tudo
//   POST /lab/mudar-precos   {"quantidade": 20}      +5% no preço de N produtos ativos
//   POST /lab/mudar-preco    {"codigoBarras", "preco"}  preço de UM produto (roteiro manual)
//   POST /lab/excluir        {"quantidade": 5}       some com N produtos (vão para "excluidos")
//   POST /lab/token-curto    {"segundos": 2}         tokens novos vencem rápido (teste do token vencido)
//   POST /lab/lento          {"ms": 3000}            atraso em cada resposta (teste de tempo)
//   POST /lab/reiniciar                              volta ao dados_rpinfo.json original
//   GET  /lab/estado
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORTA = Number(process.env.PORTA || 18091);
const VERSAO = '5.0.6.117';
const LIMITE_PADRAO = 100;
const credenciais = JSON.parse(fs.readFileSync(path.join(__dirname, 'credenciais.json'), 'utf8'));
const original = () => JSON.parse(fs.readFileSync(path.join(__dirname, 'dados_rpinfo.json'), 'utf8'));

let dados = original();
let excluidos = [];
let foraDoAr = false;
let atrasoMs = 0;
let validadeTokenS = 3600;
const tokens = new Map(); // token -> vence em (ms)

// A RPInfo devolve JSON indentado (por isso ~6 KB por produto): o tamanho conta no teste de tempo.
function responder(res, status, corpo) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(corpo, null, 2));
}

function ok(res, mensagem, conteudo) {
  return responder(res, 200, { response: { status: 'ok', appVersion: VERSAO, messages: [{ message: mensagem }], ...conteudo } });
}

// Erro "de negócio" no formato real: status "error" e as mensagens. HIPÓTESE: o código HTTP.
function erro(res, status, ...mensagens) {
  return responder(res, status, { response: { status: 'error', appVersion: VERSAO, messages: mensagens.map((message) => ({ message })) } });
}

// Erro interno como a RPInfo devolve (ex. real: data fora do formato na rota de excluídos).
function falha(res, excecao) {
  return erro(res, 500, 'Falha ao carregar dados', `Exception: ${excecao}`,
    `StackTrace: java.text.ParseException: ${excecao}\n\tat br.framework.classes.helpers.StringFunctions.parseToDate(simulado)`);
}

function lerCorpo(req) {
  return new Promise((resolve) => {
    let texto = '';
    req.on('data', (parte) => (texto += parte));
    req.on('end', () => {
      try { resolve(texto ? JSON.parse(texto) : {}); } catch { resolve(null); }
    });
  });
}

function sorteia(lista, quantidade) {
  return [...lista].sort(() => Math.random() - 0.5).slice(0, quantidade);
}

function agoraManutencao() {
  const d = new Date();
  const dois = (n) => String(n).padStart(2, '0');
  return `${dois(d.getDate())}/${dois(d.getMonth() + 1)}/${d.getFullYear()} ${dois(d.getHours())}:${dois(d.getMinutes())}:${dois(d.getSeconds())}.${String(d.getMilliseconds()).padStart(3, '0')}`;
}

// "dd/MM/yyyy HH:mm:ss.SSS" ou "dd-MM-yyyy HH:mm:ss" -> Date
function lerDataHora(texto) {
  const m = /^(\d{2})[-/](\d{2})[-/](\d{4})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(texto || '');
  return m ? new Date(+m[3], +m[2] - 1, +m[1], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0)) : null;
}

// Parece um JWT (eyJ...), como o da RPInfo; aqui é só um sorteio.
function novoToken() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${b64({ alg: 'HS256' })}.${b64({ sub: credenciais.usuario, jti: crypto.randomUUID() })}.${crypto.randomBytes(24).toString('base64url')}`;
}

function autorizado(req) {
  const token = req.headers.token || '';
  const vence = tokens.get(token);
  if (!vence || vence < Date.now()) {
    tokens.delete(token);
    return false;
  }
  return true;
}

const unidadeValida = (cnpj) => dados.unidades.some((u) => u.cnpj === cnpj);

const servidor = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const caminho = decodeURIComponent(url.pathname);
  const corpo = req.method === 'POST' ? await lerCorpo(req) : {};
  console.log(new Date().toISOString(), req.method, url.pathname + url.search);

  // ---------- laboratório ----------
  if (caminho.startsWith('/lab/')) {
    switch (caminho) {
      case '/lab/fora-do-ar':
        foraDoAr = !!(corpo && corpo.ativo);
        return responder(res, 200, { foraDoAr });
      case '/lab/mudar-precos': {
        const alvo = sorteia(dados.produtos.filter((p) => p.Ativo && p.Oferta !== 'S'), (corpo && corpo.quantidade) || 20);
        for (const p of alvo) {
          p.Preco = p.PrecoPDV = p.PrecoEtiqueta = Math.round(p.PrecoPDV * 105) / 100;
          p.DataHoraManutencao = agoraManutencao();
        }
        return responder(res, 200, { alterados: alvo.map((p) => ({ codigo: p.CodigoBarras, novoPreco: p.PrecoPDV })) });
      }
      case '/lab/mudar-preco': {
        const p = dados.produtos.find((x) => x.CodigoBarras === (corpo && corpo.codigoBarras));
        if (!p || !(Number(corpo.preco) > 0)) {
          return responder(res, 404, { erro: 'informe codigoBarras de um produto e preco > 0' });
        }
        p.Preco = p.PrecoPDV = p.PrecoEtiqueta = Number(corpo.preco);
        p.DataHoraManutencao = agoraManutencao();
        return responder(res, 200, { codigo: p.CodigoBarras, descricao: p.Descricao, novoPreco: p.PrecoPDV });
      }
      case '/lab/excluir': {
        const alvo = new Set(sorteia(dados.produtos, (corpo && corpo.quantidade) || 5));
        dados.produtos = dados.produtos.filter((p) => !alvo.has(p));
        const hoje = new Date();
        for (const p of alvo) {
          excluidos.push({ codigo: p.Codigo, codigoBarras: p.CodigoBarras, descricao: p.Descricao, dataExclusao: hoje });
        }
        return responder(res, 200, { excluidos: [...alvo].map((p) => p.CodigoBarras) });
      }
      case '/lab/token-curto':
        validadeTokenS = (corpo && corpo.segundos) || 3600;
        return responder(res, 200, { validadeTokenS });
      case '/lab/lento':
        atrasoMs = (corpo && corpo.ms) || 0;
        return responder(res, 200, { atrasoMs });
      case '/lab/reiniciar':
        dados = original(); excluidos = []; foraDoAr = false; atrasoMs = 0; validadeTokenS = 3600; tokens.clear();
        return responder(res, 200, { produtos: dados.produtos.length });
      case '/lab/estado':
        return responder(res, 200, {
          produtos: dados.produtos.length, ativos: dados.produtos.filter((p) => p.Ativo).length,
          excluidos: excluidos.length, foraDoAr, atrasoMs, validadeTokenS, tokensAtivos: tokens.size,
        });
      default:
        return responder(res, 404, { erro: 'botão de laboratório desconhecido' });
    }
  }

  if (atrasoMs) {
    await new Promise((r) => setTimeout(r, atrasoMs));
  }
  if (foraDoAr) {
    return responder(res, 503, { erro: 'Sistema indisponível (simulado)' });
  }

  // ---------- autenticação ----------
  if (req.method === 'POST' && /^\/v1\.[12]\/auth$/.test(caminho)) {
    if (!corpo || corpo.usuario !== credenciais.usuario || corpo.senha !== credenciais.senha) {
      // Igual à real (resposta 16): HTTP 500 (não 401), sem envelope, com "error" e "stackTrace".
      return responder(res, 500, { error: 'Não foi possível autenticar o usuário',
        stackTrace: 'br.com.rpinfo.LibErp.core.model.classes.exceptions.ValidationException: Não foi possível autenticar o usuário\n\tat (simulado)' });
    }
    const token = novoToken();
    const vence = Date.now() + validadeTokenS * 1000;
    tokens.set(token, vence);
    return ok(res, 'Requisição processada com sucesso',
      { content: { token, tokenExpiration: new Date(vence).toISOString(), expiresIn: validadeTokenS } });
  }

  // Sem token ou vencido: 401 SEM o envelope "response" (igual à real).
  if (!autorizado(req)) {
    return responder(res, 401, { appVersion: VERSAO, content: 'Não autorizado' });
  }

  if (req.method !== 'GET') {
    return erro(res, 404, 'Rota não encontrada');
  }

  // ---------- cadastros ----------
  if (caminho === '/v1.6/unidades') {
    return ok(res, 'Requisição processada com sucesso', { content: dados.unidades });
  }
  if (caminho === '/v1.1/departamentos') {
    return ok(res, 'Requisição processada com sucesso', { content: dados.departamentos });
  }

  // ---------- lista de produtos (paginação pelo último Codigo) ----------
  let m = /^\/v3\.2\/produtounidade\/listaprodutos\/(\d+)\/unidade\/(\d+)\/detalhado(\/ativos)?(?:\/dataHoraManutencao\/(.+))?$/.exec(caminho);
  if (m) {
    const [, lastId, cnpj, soAtivos, desde] = m;
    if (!unidadeValida(cnpj)) {
      return erro(res, 400, 'Unidade não encontrada'); // HIPÓTESE
    }
    const limite = Math.min(Number(url.searchParams.get('limit')) || LIMITE_PADRAO, 1000);
    const corte = desde ? lerDataHora(desde) : null;
    if (desde && !corte) {
      return falha(res, `Unparseable date: "${desde}"`);
    }
    const pagina = dados.produtos
      .filter((p) => p.Codigo > Number(lastId) && (!soAtivos || p.Ativo) && (!corte || lerDataHora(p.DataHoraManutencao) >= corte))
      .slice(0, limite);
    // Depois da última página: lista vazia com status ok (confirmado na homologação).
    return ok(res, 'Dados carregados', { produtos: pagina });
  }

  // ---------- consulta por código de barras ----------
  m = /^\/v3\.2\/produtounidade\/(\d+)\/unidade\/(\d+)\/detalhado\/consultarcodigobarras$/.exec(caminho);
  if (m) {
    const [, codigo, cnpj] = m;
    if (!unidadeValida(cnpj)) {
      return erro(res, 400, 'Unidade não encontrada'); // HIPÓTESE
    }
    const produto = dados.produtos.find((p) => p.CodigoBarras === codigo
      || p.codBarrasAlterados.some((a) => a.codigoBarras === codigo));
    if (!produto) {
      // Texto real (homologação 08/10); o código HTTP ainda é HIPÓTESE.
      return erro(res, 404, `Produto código '${codigo}' para a unidade com CNPJ '${cnpj}', não foi encontrado na base de dados.`);
    }
    return ok(res, 'Dados carregados', { produto });
  }

  // ---------- ofertas (NÃO filtra validade; paginação por ?lastId= confirmada — como a real) ----------
  if (caminho === '/v1.0/produtounidade/ofertas') {
    const limite = Number(url.searchParams.get('limit')) || LIMITE_PADRAO;
    const lastId = Number(url.searchParams.get('lastId')) || 0;
    const content = dados.produtos
      .filter((p) => p.Ativo && p.Oferta === 'S' && p.Codigo > lastId)
      .slice(0, limite)
      .map((p) => ({
        codigoProduto: p.Codigo, nomeProduto: p.Descricao, marca: p.Marca, precoAnterior: p.PrecoNormal,
        precoAtual: p.PrecoPDV, preco2: 0, preco3: 0, preco4: 0, preco5: 0, codigoBarras: p.CodigoBarras,
        codigosAlternativos: p.codBarrasAlterados.map((a) => a.codigoBarras), caminhoImagem: null,
      }));
    return ok(res, 'Requisição processada com sucesso', { content });
  }

  // ---------- excluídos ----------
  // Igual à REAL (homologação 08/10, respostas 12 e 15): "excluidos" no lugar de "produtos", um
  // "message" solto além de "messages", 100 por página ordenados por codigoProduto (próxima página =
  // lastid do último). Item: codigoProduto, codigoBarras, dataExclusao "dd/MM/yyyy" e
  // "usuarioExclusão" (COM acento; o OpenAPI diz usuarioExclusao e um "status" que não vem).
  // Data fora de dd-MM-yyyy = erro real.
  m = /^\/v1\.1\/produto\/excluidos\/lastid\/(\d+)\/dataexclusao\/(.+)$/.exec(caminho);
  if (m) {
    if (!/^\d{2}-\d{2}-\d{4}$/.test(m[2])) {
      return falha(res, `Unparseable date: "${m[2]}"`);
    }
    const corte = lerDataHora(m[2]);
    const lista = excluidos
      .filter((e) => e.codigo > Number(m[1]) && e.dataExclusao >= corte)
      .sort((a, b) => a.codigo - b.codigo)
      .slice(0, LIMITE_PADRAO)
      .map((e) => ({ codigoProduto: e.codigo, codigoBarras: e.codigoBarras,
        dataExclusao: e.dataExclusao.toLocaleDateString('pt-BR'), 'usuarioExclusão': 900 }));
    return responder(res, 200, { response: { status: 'ok', appVersion: VERSAO, message: 'Dados carregados com sucesso',
      messages: [{ message: 'Dados carregados com sucesso' }], excluidos: lista } });
  }

  return erro(res, 404, 'Rota não encontrada');
});

servidor.listen(PORTA, () => console.log(`API simulada RPInfo no ar: http://localhost:${PORTA} (${dados.produtos.length} produtos)`));
