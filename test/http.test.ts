import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { WebSocket, WebSocketServer } from 'ws';
import { createApp } from '../src/app.js';
import { readConfig } from '../src/config.js';

async function listen(server: Server) {
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  return 'http://127.0.0.1:' + (server.address() as AddressInfo).port;
}

test('standalone API forwards auth, protects data and routes websocket upgrades', async t => {
  const received: Array<{ path: string; key?: string; auth?: string; body: string }> = [];
  const upstream = createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    received.push({ path: req.url!, key: req.headers.apikey as string, auth: req.headers.authorization, body });
    res.setHeader('Content-Type', 'application/json');
    if (req.url?.startsWith('/auth/v1/token')) res.end(JSON.stringify({ access_token: 'user.jwt.token', token_type: 'bearer' }));
    else if (req.url?.startsWith('/auth/v1/user')) res.end(JSON.stringify({ id: '00000000-0000-4000-8000-000000000001' }));
    else if (req.url?.startsWith('/rest/v1/profiles')) res.end(JSON.stringify({ id: '00000000-0000-4000-8000-000000000001', name: 'Test', banned: false }));
    else if (req.url?.startsWith('/rest/v1/user_roles')) res.end(JSON.stringify({ role: 'user' }));
    else res.end(JSON.stringify([{ id: 'task-1' }]));
  });
  const sockets = new WebSocketServer({ server: upstream });
  sockets.on('connection', (socket, req) => socket.send(JSON.stringify({ path: req.url, key: req.headers.apikey })));
  const config = readConfig({ SUPABASE_URL: await listen(upstream), SUPABASE_ANON_KEY: 'anon-test-key',
    SUPABASE_SERVICE_ROLE_KEY: 'service-test-key', APP_URL: 'http://localhost:8080' });
  const { app, upgrade } = createApp(config);
  const server = createServer(app); server.on('upgrade', upgrade);
  const base = await listen(server);
  t.after(() => { server.closeAllConnections(); server.close(); for (const ws of sockets.clients) ws.terminate(); sockets.close(); upstream.closeAllConnections(); upstream.close(); });
  const headers = { origin: config.appUrl, 'content-type': 'application/json' };
  assert.equal((await fetch(base + '/api/health')).status, 200);
  assert.equal((await fetch(base + '/auth')).status, 404); // API never serves a frontend.
  assert.equal((await fetch(base + '/api/projects')).status, 401);
  assert.equal((await fetch(base + '/api/supabase/rest/v1/tasks')).status, 401);
  assert.equal((await fetch(base + '/api/supabase/auth/v1/token', { method: 'POST', headers: { ...headers, origin: 'https://untrusted.test' }, body: '{}' })).status, 403);
  const login = await fetch(base + '/api/supabase/auth/v1/token?grant_type=password', { method: 'POST', headers, body: JSON.stringify({ email: 'a@test.invalid', password: 'test-password' }) });
  assert.equal(login.status, 200);
  const authRequest = received.at(-1)!;
  assert.equal(authRequest.path, '/auth/v1/token?grant_type=password');
  assert.equal(authRequest.key, 'anon-test-key');
  assert.equal(authRequest.auth, 'Bearer anon-test-key');
  assert.equal(JSON.parse(authRequest.body).email, 'a@test.invalid');
  assert.equal((await fetch(base + '/api/supabase/auth/v1/signup', { method: 'POST', headers, body: '{}' })).status, 403);
  assert.equal((await fetch(base + '/api/supabase/auth/v1/recover?redirect_to=https://untrusted.test', { method: 'POST', headers, body: '{}' })).status, 400);
  const userHeaders = { ...headers, authorization: 'Bearer user.jwt.token' };
  assert.equal((await fetch(base + '/api/supabase/rest/v1/tasks?select=id', { headers: userHeaders })).status, 200);
  const dataRequest = received.at(-1)!;
  assert.equal(dataRequest.auth, 'Bearer user.jwt.token');
  assert.equal(dataRequest.key, 'anon-test-key');
  assert.equal((await fetch(base + '/api/supabase/functions/v1/admin-manage-user', { method: 'POST', headers: userHeaders, body: '{"action":"delete"}' })).status, 403);
  assert.equal((await fetch(base + '/api/supabase/rest/v1/rpc/cleanup_old_tasks', { method: 'POST', headers: userHeaders, body: '{}' })).status, 404);
  const ws = new WebSocket(base.replace('http:', 'ws:') + '/api/supabase/realtime/v1/websocket?apikey=railway-browser-client&vsn=1.0.0', { origin: config.appUrl });
  const message = await new Promise<string>((resolve, reject) => { ws.once('message', data => resolve(String(data))); ws.once('error', reject); });
  ws.terminate();
  const socketRequest = JSON.parse(message);
  assert.equal(socketRequest.key, 'anon-test-key');
  assert.match(socketRequest.path, /^\/realtime\/v1\/websocket\?/);
  assert.match(socketRequest.path, /apikey=anon-test-key/);
  assert.ok(!socketRequest.path.includes('service-test-key'));
});
