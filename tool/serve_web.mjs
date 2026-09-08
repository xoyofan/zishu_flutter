// 临时静态服务器（仅冒烟验证用）：node tool/serve_web.mjs [port] [dir]
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { fileURLToPath } from 'node:url';const port = Number(process.argv[2] ?? 8090);
const root = path.resolve(process.argv[3] ?? path.dirname(fileURLToPath(new URL('../build/web/index.html', import.meta.url))));
const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.otf': 'font/otf',
};

http.createServer(async (req, res) => {
  try {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(root, p);
    const data = await readFile(file);
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] ?? 'application/octet-stream' });
    res.end(data);
  } catch {
    // SPA fallback：未命中文件回 index.html（history 路由形态需要）
    try {
      const data = await readFile(path.join(root, 'index.html'));
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(data);
    } catch {
      res.writeHead(404);
      res.end('not found');
    }
  }
}).listen(port, '127.0.0.1', () => console.log(`serving ${root} at http://127.0.0.1:${port}`));
