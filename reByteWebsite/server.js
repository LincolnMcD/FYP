const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 5173;
const ROOT_DIR = __dirname;

const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
  '.ico': 'image/x-icon'
};

const server = http.createServer((req, res) => {
  let reqPath = req.url.split('?')[0];

  // Default root redirect to customer home page
  if (reqPath === '/' || reqPath === '') {
    res.writeHead(302, { 'Location': '/accountManagementModule/home.html' });
    return res.end();
  }

  // If top-level shortcut requested (e.g., /home.html or /welcome.html), route to accountManagementModule
  const directShortcuts = ['/home.html', '/welcome.html', '/login.html', '/register.html'];
  if (directShortcuts.includes(reqPath)) {
    res.writeHead(302, { 'Location': `/accountManagementModule${reqPath}` });
    return res.end();
  }

  let filePath = path.join(ROOT_DIR, reqPath);

  // Fallback to check inside accountManagementModule if not found at root
  if (!fs.existsSync(filePath)) {
    const fallbackPath = path.join(ROOT_DIR, 'accountManagementModule', reqPath);
    if (fs.existsSync(fallbackPath) && !fs.statSync(fallbackPath).isDirectory()) {
      filePath = fallbackPath;
    }
  }

  fs.stat(filePath, (err, stats) => {
    if (err || stats.isDirectory()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      return res.end('404 Not Found');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, { 'Content-Type': contentType });
    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n======================================================`);
  console.log(`  ReByte Web Server running successfully!`);
  console.log(`  Local URL: http://localhost:${PORT}/accountManagementModule/home.html`);
  console.log(`======================================================\n`);
});
