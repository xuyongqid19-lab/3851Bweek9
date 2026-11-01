import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../build/web/', import.meta.url));
const projectRoot = path.resolve(root, '../..');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript',
  '.json': 'application/json', '.css': 'text/css', '.wasm': 'application/wasm',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
await stat(path.join(root, 'index.html'));
http.createServer(async (req, res) => {
  try {
    if (req.url === '/__project_health') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ projectRoot })); return;
    }
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const filename = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!filename.startsWith(root) || /(^|[/\\])\./.test(pathname)) {
      res.writeHead(403).end(); return;
    }
    const content = await readFile(filename);
    res.writeHead(200, { 'Content-Type': types[path.extname(filename)] || 'application/octet-stream',
      'Cache-Control': 'no-cache' });
    res.end(content);
  } catch { res.writeHead(404).end('Not found'); }
}).listen(Number(process.env.PREVIEW_PORT || 7357), '127.0.0.1', () => console.log('Login preview listening'));
