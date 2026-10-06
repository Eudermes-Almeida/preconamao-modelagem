// API SIMULADA de um sistema de gestão (ERP) de supermercado — SÓ LABORATÓRIO (regras 13 e 14 do
// multi-loja). Imita o jeito comum das APIs de ERP: pede um token com usuário e senha (vence em 1 h)
// e lista os produtos em páginas. O nosso servidor (ColetaApiService) consulta "de fora", com
// credencial, como faria com o sistema de uma loja real.
//
// Sem dependências (só Node). Uso: node servidor.js   (porta 18090; dados em dados.json, gerados
// por gerar_dados.py; usuário e senha em credenciais.json, fora do git).
//
// Endpoints:
//   POST /auth/token              {"usuario","senha"} -> {"access_token","token_type","expires_in"}
//   GET  /v1/produtos?pagina=1&tamanho=500   (Authorization: Bearer <token>)
// Botões de laboratório (para provocar situações sem editar arquivos):
//   POST /lab/fora-do-ar          {"ativo": true|false}   API responde 503 em tudo
//   POST /lab/mudar-precos        {"quantidade": 20}      +5% no preço de N produtos ativos
//   POST /lab/excluir             {"quantidade": 5}       some com N produtos
//   POST /lab/token-curto         {"segundos": 2}         tokens novos vencem rápido (teste do token vencido)
//   POST /lab/reiniciar                                   volta ao dados.json original
//   GET  /lab/estado
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORTA = Number(process.env.PORTA || 18090);
const credenciais = JSON.parse(fs.readFileSync(path.join(__dirname, 'credenciais.json'), 'utf8'));
const original = () => JSON.parse(fs.readFileSync(path.join(__dirname, 'dados.json'), 'utf8'));

let produtos = original();
let foraDoAr = false;
let validadeTokenS = 3600;
const tokens = new Map(); // token -> vence em (ms)

function responder(res, status, corpo) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(corpo));
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

const servidor = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const corpo = req.method === 'POST' ? await lerCorpo(req) : {};
  console.log(new Date().toISOString(), req.method, url.pathname + url.search);

  // ---------- laboratório ----------
  if (url.pathname.startsWith('/lab/')) {
    switch (url.pathname) {
      case '/lab/fora-do-ar':
        foraDoAr = !!(corpo && corpo.ativo);
        return responder(res, 200, { foraDoAr });
      case '/lab/mudar-precos': {
        const alvo = sorteia(produtos.filter((p) => p.ativo), (corpo && corpo.quantidade) || 20);
        for (const p of alvo) {
          p.precoVenda = Math.round(Number(p.precoVenda) * 105) / 100;
          p.alteradoEm = new Date().toISOString().slice(0, 10);
        }
        return responder(res, 200, { alterados: alvo.map((p) => ({ codigo: p.codigosBarras[0], novoPreco: p.precoVenda })) });
      }
      case '/lab/excluir': {
        const alvo = new Set(sorteia(produtos, (corpo && corpo.quantidade) || 5));
        produtos = produtos.filter((p) => !alvo.has(p));
        return responder(res, 200, { excluidos: [...alvo].map((p) => p.codigosBarras[0]) });
      }
      case '/lab/token-curto':
        validadeTokenS = (corpo && corpo.segundos) || 3600;
        return responder(res, 200, { validadeTokenS });
      case '/lab/reiniciar':
        produtos = original(); foraDoAr = false; validadeTokenS = 3600; tokens.clear();
        return responder(res, 200, { produtos: produtos.length });
      case '/lab/estado':
        return responder(res, 200, { produtos: produtos.length, foraDoAr, validadeTokenS, tokensAtivos: tokens.size });
      default:
        return responder(res, 404, { erro: 'botão de laboratório desconhecido' });
    }
  }

  if (foraDoAr) {
    return responder(res, 503, { erro: 'Sistema indisponível (simulado)' });
  }

  // ---------- autenticação ----------
  if (req.method === 'POST' && url.pathname === '/auth/token') {
    if (!corpo || corpo.usuario !== credenciais.usuario || corpo.senha !== credenciais.senha) {
      return responder(res, 401, { erro: 'Usuário ou senha inválidos' });
    }
    const token = crypto.randomBytes(24).toString('hex');
    tokens.set(token, Date.now() + validadeTokenS * 1000);
    return responder(res, 200, { access_token: token, token_type: 'Bearer', expires_in: validadeTokenS });
  }

  // ---------- produtos ----------
  if (req.method === 'GET' && url.pathname === '/v1/produtos') {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const vence = tokens.get(token);
    if (!vence || vence < Date.now()) {
      tokens.delete(token);
      return responder(res, 401, { erro: 'Token ausente ou vencido' });
    }
    const tamanho = Math.min(Number(url.searchParams.get('tamanho')) || 500, 1000);
    const pagina = Math.max(Number(url.searchParams.get('pagina')) || 1, 1);
    const totalPaginas = Math.max(Math.ceil(produtos.length / tamanho), 1);
    return responder(res, 200, {
      pagina, tamanhoPagina: tamanho, totalPaginas, totalItens: produtos.length,
      itens: produtos.slice((pagina - 1) * tamanho, pagina * tamanho),
    });
  }

  return responder(res, 404, { erro: 'não encontrado' });
});

servidor.listen(PORTA, () => console.log(`API simulada no ar: http://localhost:${PORTA} (${produtos.length} produtos)`));
