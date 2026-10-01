import http from 'node:http';
import mysql from 'mysql2/promise';

const host = required('FIVEM_HOST');
const port = Number(process.env.FIVEM_PORT || 30120);
const intervalMs = Math.max(5, Number(process.env.HEALTH_POLL_SECONDS || 30)) * 1000;
const healthDb = resolveHealthDatabase();
const pool = mysql.createPool({
  host: healthDb.host,
  port: healthDb.port,
  database: healthDb.name,
  user: healthDb.user,
  password: healthDb.password,
  waitForConnections: true,
  connectionLimit: 2,
  connectTimeout: 10000,
});

console.log(`[spz-server-monitor] Monitoring ${host}:${port}/dynamic.json every ${intervalMs / 1000}s; health DB ${healthDb.host}:${healthDb.port}/${healthDb.name}`);
let stopping = false;
let wakeDelay;
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    console.log(`[spz-server-monitor] Received ${signal}; stopping after the active check`);
    stopping = true;
    wakeDelay?.();
  });
}

while (!stopping) {
  try {
    await ensureSchema();
    const { isUp, latency, players, maxPlayers, error } = await probe(host, port);
    await pool.execute(
      'INSERT INTO server_health_checks (checked_at, interval_seconds, is_up, latency_ms, players_online, max_players, error_text) VALUES (UTC_TIMESTAMP(3), ?, ?, ?, ?, ?, ?)',
      [intervalMs / 1000, isUp ? 1 : 0, latency, players, maxPlayers, error],
    );
    console.log(`${new Date().toISOString()} ${isUp ? `reachable · ${players ?? '?'} players` : 'unreachable'}${latency == null ? '' : ` ${latency}ms`}${error ? ` (${error})` : ''}`);
  } catch (error) {
    console.error(`[spz-server-monitor] Health DB/schema write failed; retrying in ${intervalMs / 1000}s: ${error.message}`);
  }
  if (!stopping) await delay(intervalMs);
}
await pool.end();
console.log('[spz-server-monitor] Stopped cleanly');

async function ensureSchema() {
  await pool.query(`CREATE TABLE IF NOT EXISTS server_health_checks (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    checked_at DATETIME(3) NOT NULL,
    interval_seconds SMALLINT UNSIGNED NOT NULL DEFAULT 30,
    is_up TINYINT(1) NOT NULL,
    latency_ms INT UNSIGNED NULL,
    players_online SMALLINT UNSIGNED NULL,
    max_players SMALLINT UNSIGNED NULL,
    error_text VARCHAR(255) NULL,
    INDEX idx_health_checked_at (checked_at),
    INDEX idx_health_state_time (is_up, checked_at)
  ) ENGINE=InnoDB`);
  await pool.query('ALTER TABLE server_health_checks ADD COLUMN IF NOT EXISTS interval_seconds SMALLINT UNSIGNED NOT NULL DEFAULT 30');
}

function delay(ms) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => { wakeDelay = undefined; resolve(); }, ms);
    wakeDelay = () => { clearTimeout(timer); wakeDelay = undefined; resolve(); };
  });
}

function probe(targetHost, targetPort) {
  return new Promise((resolve) => {
    const started = performance.now();
    const request = http.get({ host: targetHost, port: targetPort, path: '/dynamic.json', timeout: 4000, headers: { accept: 'application/json' } }, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { body += chunk; if (body.length > 1_000_000) request.destroy(new Error('response too large')); });
      response.on('end', () => {
        const latency = Math.max(0, Math.round(performance.now() - started));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          resolve({ isUp: false, latency: null, players: null, maxPlayers: null, error: `HTTP ${response.statusCode}` });
          return;
        }
        try {
          const data = JSON.parse(body);
          const players = Number(data.clients);
          const maxPlayers = Number(data.sv_maxclients);
          resolve({ isUp: true, latency, players: Number.isFinite(players) ? players : null, maxPlayers: Number.isFinite(maxPlayers) ? maxPlayers : null, error: null });
        } catch {
          resolve({ isUp: false, latency: null, players: null, maxPlayers: null, error: 'Invalid /dynamic.json response' });
        }
      });
    });
    request.on('timeout', () => request.destroy(new Error('timeout')));
    request.on('error', (err) => resolve({ isUp: false, latency: null, players: null, maxPlayers: null, error: String(err.message).slice(0, 255) }));
  });
}

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

function resolveHealthDatabase() {
  const fallbackAddress = process.env.GF_DATABASE_HEALTH_HOST || '';
  const configuredHost = process.env.HEALTH_DB_HOST || fallbackAddress;
  const explicitPort = process.env.HEALTH_DB_PORT;
  let host = configuredHost;
  let port = Number(explicitPort || 3306);
  const ipv6 = configuredHost.match(/^\[([^\]]+)\]:(\d+)$/);
  const hostPort = configuredHost.match(/^([^:]+):(\d+)$/);
  if (!explicitPort && ipv6) { host = ipv6[1]; port = Number(ipv6[2]); }
  else if (!explicitPort && hostPort) { host = hostPort[1]; port = Number(hostPort[2]); }

  const name = process.env.HEALTH_DB_NAME || process.env.GF_DATABASE_HEALTH_NAME;
  const user = process.env.HEALTH_DB_USER || process.env.GF_DATABASE_HEALTH_USER;
  const password = process.env.HEALTH_DB_PASSWORD || process.env.GF_DATABASE_HEALTH_PASSWORD;
  if (!host) throw new Error('Set HEALTH_DB_HOST or GF_DATABASE_HEALTH_HOST');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('HEALTH_DB_PORT must be a valid TCP port');
  return { host, port, name: requiredValue('HEALTH_DB_NAME', name), user: requiredValue('HEALTH_DB_USER', user), password: requiredValue('HEALTH_DB_PASSWORD', password) };
}

function requiredValue(label, value) {
  if (!value) throw new Error(`Missing required ${label} (or its GF_DATABASE_HEALTH_* alias)`);
  return value;
}
