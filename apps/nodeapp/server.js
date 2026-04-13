const http = require('http');

const VERSION = process.env.APP_VERSION || 'dev';
const PORT    = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('ok');
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: 'Hello from Node.js - v2!',
    version: VERSION,
    path:    req.url,
  }, null, 2));
});

server.listen(PORT, () => {
  console.log(`nodeapp v${VERSION} running on port ${PORT}`);
});
