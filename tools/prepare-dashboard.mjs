import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const [source, destination, mapBase] = process.argv.slice(2);
if (!source || !destination || !mapBase) throw new Error('Usage: node prepare-dashboard.mjs SOURCE DESTINATION TRACK_MAP_PUBLIC_URL');
const url = new URL(mapBase);
if (!['http:', 'https:'].includes(url.protocol) || url.pathname !== '/' || url.search || url.hash) {
  throw new Error('TRACK_MAP_PUBLIC_URL must be an HTTP(S) origin with optional port and no path, query, or fragment');
}

const dashboard = JSON.parse(await readFile(source, 'utf8'));
const publicUrl = url.origin;
let replacements = 0;
function replaceUrls(value) {
  if (Array.isArray(value)) { for (const entry of value) replaceUrls(entry); return; }
  if (!value || typeof value !== 'object') return;
  for (const [key, entry] of Object.entries(value)) {
    if (typeof entry === 'string' && entry.startsWith('http://localhost:8090')) {
      value[key] = entry.replace('http://localhost:8090', publicUrl);
      replacements += 1;
    } else replaceUrls(entry);
  }
}
replaceUrls(dashboard);
await mkdir(path.dirname(destination), { recursive: true });
await writeFile(destination, `${JSON.stringify(dashboard, null, 2)}\n`, 'utf8');
console.log(`[spz-grafana] Installed dashboard at ${destination}; mapped ${replacements} track-map URL(s) to ${publicUrl}`);
