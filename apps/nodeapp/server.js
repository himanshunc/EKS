const http = require('http');

const VERSION = process.env.APP_VERSION || 'dev';
const PORT    = process.env.PORT || 3000;

// Exported so unit tests can call it directly without starting the HTTP server
function handler(req, res) {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('ok');
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: 'Hello from Node.js!',
    version: VERSION,
    path:    req.url,
  }, null, 2));
}

const server = http.createServer(handler);

// Only listen when run directly (not when required by tests)
if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`nodeapp v${VERSION} running on port ${PORT}`);
  });
}

module.exports = { handler };
