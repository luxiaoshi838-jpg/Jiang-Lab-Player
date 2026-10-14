// Suibo public read/match gateway for a pinned upstream danmu_api process.
// Never forward the private upstream admin token or expose management routes.
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';

const secret = process.env.SUIBO_BACKEND_SECRET ?? '';
if (secret.length < 24) {
  throw new Error('SUIBO_BACKEND_SECRET must be configured as a strong private value');
}
const token = createHash('sha256').update(secret).digest('hex');
const upstreamDir = process.env.SUIBO_UPSTREAM_DIR || '/srv/upstream';
const listenPort = Number(process.env.PORT || '10000');
const upstreamPort = 9321;
const child = spawn(process.execPath, ['danmu_api/server.js'], {
  cwd: upstreamDir,
  stdio: 'inherit',
  env: { ...process.env, TOKEN: token, DANMU_API_PORT: String(upstreamPort) },
});
child.on('exit', (code) => {
  console.error('Upstream danmaku server exited', code);
  process.exit(1);
});

const getPaths = [
  /^\/api\/v2\/search\/(anime|episodes)$/,
  /^\/api\/v2\/bangumi\/(?:[0-9]+|bgmtv\/[0-9]+)$/,
  /^\/api\/v2\/comment(?:\/[0-9]+)?$/,
];
const postPaths = [/^\/api\/v2\/match$/];

function health(response) {
  const socket = net.connect({host: '127.0.0.1', port: upstreamPort});
  let finished = false;
  const finish = (code) => {
    if (finished) return;
    finished = true;
    socket.destroy();
    response.writeHead(code, {'content-type': 'text/plain; charset=utf-8'});
    response.end(code === 200 ? 'ok' : 'backend unavailable');
  };
  socket.once('connect', () => finish(200));
  socket.once('error', () => finish(503));
  socket.setTimeout(1500, () => finish(503));
}

const server = http.createServer((request, response) => {
  let incoming;
  try {
    incoming = new URL(request.url || '/', 'http://localhost');
  } catch {
    response.writeHead(400); response.end('invalid URL'); return;
  }
  if (request.method === 'GET' && incoming.pathname === '/healthz') {
    health(response); return;
  }
  const isGet = request.method === 'GET' &&
    getPaths.some(pattern => pattern.test(incoming.pathname));
  const isPost = request.method === 'POST' &&
    postPaths.some(pattern => pattern.test(incoming.pathname));
  if ((!isGet && !isPost) || incoming.search.length > 8192) {
    response.writeHead(404); response.end('not found'); return;
  }

  let sent = false;
  const fail = (code) => {
    if (sent) return;
    sent = true;
    if (!response.headersSent) response.writeHead(code);
    response.end();
  };
  const targetPath = '/' + token + incoming.pathname + incoming.search;
  const upstreamRequest = http.request({
    hostname: '127.0.0.1', port: upstreamPort,
    path: targetPath, method: request.method,
    headers: {
      'accept': 'application/json',
      'accept-encoding': 'identity',
      ...(isPost ? {'content-type': 'application/json'} : {}),
    },
    timeout: 90000,
  }, (upstreamResponse) => {
    if (sent) return;
    sent = true;
    response.writeHead(upstreamResponse.statusCode || 502, {
      'content-type': upstreamResponse.headers['content-type'] || 'application/json',
      'cache-control': 'no-store',
    });
    upstreamResponse.pipe(response);
  });
  upstreamRequest.on('timeout', () => upstreamRequest.destroy());
  upstreamRequest.on('error', () => fail(502));
  if (isPost) {
    let bytes = 0;
    request.on('data', (chunk) => {
      bytes += chunk.length;
      if (bytes > 16384) { upstreamRequest.destroy(); fail(413); }
      else upstreamRequest.write(chunk);
    });
    request.on('end', () => { if (bytes <= 16384) upstreamRequest.end(); });
    request.on('error', () => upstreamRequest.destroy());
  } else {
    upstreamRequest.end();
  }
});

server.listen(listenPort, '0.0.0.0', () => {
  console.log('Suibo read/match gateway listening on', listenPort);
});
process.on('SIGTERM', () => {
  child.kill('SIGTERM');
  server.close();
});
