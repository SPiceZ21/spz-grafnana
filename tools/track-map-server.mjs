import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(process.env.TRACK_MAP_ROOT || path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public'));
const port = Number(process.env.TRACK_MAP_PORT);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('TRACK_MAP_PORT must be a valid TCP port');
const mime = { '.html': 'text/html; charset=utf-8', '.json': 'application/json; charset=utf-8', '.geojson': 'application/geo+json; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };

const server = createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method === 'OPTIONS') { res.writeHead(204).end(); return; }
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { Allow: 'GET, HEAD, OPTIONS' }).end(); return; }

  let requestPath;
  try { requestPath = decodeURIComponent(new URL(req.url || '/', 'http://track-map.local').pathname); }
  catch { res.writeHead(400).end('Bad request'); return; }
  if (requestPath === '/') requestPath = '/index.html';
  const filename = path.resolve(root, `.${requestPath}`);
  if (filename !== root && !filename.startsWith(root + path.sep)) { res.writeHead(403).end('Forbidden'); return; }

  let info;
  try { info = statSync(filename); }
  catch { res.writeHead(404).end('Not found'); return; }
  if (!info.isFile()) { res.writeHead(404).end('Not found'); return; }

  res.writeHead(200, { 'Content-Type': mime[path.extname(filename).toLowerCase()] || 'application/octet-stream', 'Content-Length': info.size, 'Cache-Control': 'public, max-age=60' });
  console.log(`[spz-track-map] ${req.method} ${requestPath} 200`);
  if (req.method === 'HEAD') { res.end(); return; }
  const stream = createReadStream(filename);
  stream.on('error', (error) => { console.error(`[spz-track-map] Read failed for ${requestPath}: ${error.message}`); if (!res.headersSent) res.writeHead(500); res.end('Internal server error'); });
  stream.pipe(res);
});

server.on('error', (error) => { console.error(`[spz-track-map] Server failed: ${error.message}`); process.exitCode = 1; });
server.listen(port, '0.0.0.0', () => console.log(`[spz-track-map] Listening on 0.0.0.0:${port}; serving ${root}`));

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    console.log(`[spz-track-map] Received ${signal}; closing HTTP server`);
    server.close((error) => {
      if (error) { console.error(`[spz-track-map] Shutdown failed: ${error.message}`); process.exitCode = 1; }
      else console.log('[spz-track-map] Stopped cleanly');
    });
  });
}
