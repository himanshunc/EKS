const http = require('http');

const VERSION  = process.env.APP_VERSION  || 'dev';
const APP_NAME = process.env.APP_NAME     || 'myapp';
const PORT     = process.env.PORT         || 3000;

function handler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('ok');
    return;
  }

  if (req.url === '/info') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      app:     APP_NAME,
      version: VERSION,
      node:    process.version,
    }, null, 2));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: `Hello from ${APP_NAME} - v2!`,
    version: VERSION,
    path:    req.url,
  }, null, 2));
}

const server = http.createServer(handler);

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`${APP_NAME} v${VERSION} running on port ${PORT}`);
  });
}

module.exports = { handler };
