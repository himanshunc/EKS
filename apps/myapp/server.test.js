const { test } = require('node:test');
const assert   = require('node:assert/strict');
const { handler } = require('./server');

function makeReq(url) {
  return { url };
}

function makeRes() {
  const res = { statusCode: null, headers: {}, body: '' };
  res.writeHead = (code, headers) => { res.statusCode = code; Object.assign(res.headers, headers || {}); };
  res.end = (data) => { res.body = data || ''; };
  return res;
}

test('GET / returns 200 with message', () => {
  const res = makeRes();
  handler(makeReq('/'), res);
  assert.equal(res.statusCode, 200);
  const body = JSON.parse(res.body);
  assert.ok(body.message);
  assert.ok(body.version);
});

test('GET /health returns ok', () => {
  const res = makeRes();
  handler(makeReq('/health'), res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body, 'ok');
});

test('GET /info returns app info', () => {
  const res = makeRes();
  handler(makeReq('/info'), res);
  assert.equal(res.statusCode, 200);
  const body = JSON.parse(res.body);
  assert.ok(body.app);
  assert.ok(body.version);
  assert.ok(body.node);
});
