// Unit tests for nodeapp — uses Node.js built-in test runner (no extra packages).
// Run with: npm test
// Each test calls the handler function directly — no HTTP server needed.

const { test } = require('node:test');
const assert   = require('node:assert/strict');
const { handler } = require('./server');

// Minimal mock of the Node.js http.ServerResponse object
function mockResponse() {
  const res = {
    statusCode: null,
    body: null,
    writeHead(code) { this.statusCode = code; },
    end(data)       { this.body = data; },
  };
  return res;
}

test('GET /health returns 200 and "ok"', () => {
  const req = { url: '/health' };
  const res = mockResponse();
  handler(req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body, 'ok');
});

test('GET / returns 200 with JSON body', () => {
  const req = { url: '/' };
  const res = mockResponse();
  handler(req, res);

  assert.equal(res.statusCode, 200);
  const json = JSON.parse(res.body);
  assert.ok(json.message, 'response has a message field');
  assert.ok(json.version, 'response has a version field');
  assert.equal(json.path, '/');
});

test('GET /any-path echoes path in response', () => {
  const req = { url: '/foo/bar' };
  const res = mockResponse();
  handler(req, res);

  assert.equal(res.statusCode, 200);
  const json = JSON.parse(res.body);
  assert.equal(json.path, '/foo/bar');
});
