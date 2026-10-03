import express from 'express';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { createProxyMiddleware, fixRequestBody } from 'http-proxy-middleware';
import type { Config } from './config.js';
import { clients } from './access.js';
import { allowedPath, bearer, isPublic, safeOrigin, HttpError } from './policy.js';
import { runFunction } from './functions.js';
import { projectRequest } from './projects.js';

export function createApp(config: Config) {
  const app = express();
  const { authenticate, admin } = clients(config);
  app.disable('x-powered-by');
  // Railway has one trusted reverse-proxy hop. Do not set trust proxy=true.
  app.set('trust proxy', 1);
  app.use(helmet({
    contentSecurityPolicy: { directives: {
      defaultSrc: ["'self'"], scriptSrc: ["'self'"], styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
      fontSrc: ["'self'", 'https://fonts.gstatic.com', 'data:'],
      imgSrc: ["'self'", 'data:', 'blob:', 'https:'], mediaSrc: ["'self'", 'blob:', 'https:'],
      connectSrc: ["'self'", 'https:', 'wss:'], frameSrc: ["'self'", 'https:'],
      objectSrc: ["'none'"], frameAncestors: ["'none'"], upgradeInsecureRequests: config.production ? [] : null,
    } }, crossOriginResourcePolicy: { policy: 'cross-origin' },
  }));
  app.get('/api/health', (_req, res) => res.json({ ok: true }));
  app.use('/api', rateLimit({ windowMs: 60_000, limit: 600, standardHeaders: 'draft-8', legacyHeaders: false }));
  app.use('/api', (req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.headers.origin && !safeOrigin(req.headers.origin, config.appUrl)) {
      res.status(403).json({ error: 'Origin not allowed' }); return;
    }
    if (req.headers['sec-fetch-site'] === 'cross-site') {
      res.status(403).json({ error: 'Cross-site request not allowed' }); return;
    }
    next();
  });
  app.use('/api/supabase/auth', rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: 'draft-8', legacyHeaders: false }));
  app.use('/api/supabase/functions', rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: 'draft-8', legacyHeaders: false }));
  app.use('/api/supabase', express.json({ limit: '1mb' }));
  app.use('/api/projects', express.json({ limit: '2mb' }));
  app.use('/api/projects', async (req, res, next) => {
    try {
      const token = bearer(req.headers.authorization);
      if (!token) throw new HttpError(401, 'Требуется вход');
      const access = await authenticate(token);
      const projectId = req.path === '/' ? undefined : req.path.slice(1);
      res.json(await projectRequest(req.method, projectId, req.body ?? {}, access, admin));
    } catch (error) { next(error); }
  });
  app.use('/api/supabase', async (req, res, next) => {
    try {
      const token = bearer(req.headers.authorization);
      // The login page only needs the public logo, not arbitrary site_settings.
      if (req.path === '/rest/v1/site_settings' && req.method === 'GET' && !token &&
          req.query.key === 'eq.company_logo' && req.query.select === 'value') {
        const { data, error } = await admin.from('site_settings').select('value').eq('key', 'company_logo').maybeSingle();
        if (error) throw new HttpError(503, 'Logo unavailable');
        res.json(req.headers.accept?.includes('pgrst.object') ? data : data ? [data] : []); return;
      }
      const functionMatch = req.path.match(/^\/functions\/v1\/([a-z-]+)$/);
      if (!functionMatch && !allowedPath(req.path, req.method)) throw new HttpError(404, 'Endpoint not found');
      const publicRequest = !functionMatch && isPublic(req.path, req.method);
      if (req.path === '/auth/v1/signup' && !config.signup) throw new HttpError(403, 'Регистрация отключена. Обратитесь к администратору.');
      // Restrict auth email redirect destinations server-side, including encoded URLs.
      const redirect = req.query.redirect_to;
      if (redirect && (typeof redirect !== 'string' || !safeOrigin(redirect, config.appUrl))) throw new HttpError(400, 'Invalid redirect');
      if (!publicRequest) {
        if (!token) throw new HttpError(401, 'Требуется вход');
        const access = await authenticate(token);
        if (functionMatch) {
          if (req.method !== 'POST') throw new HttpError(405, 'POST required');
          const result = await runFunction(functionMatch[1], req.body ?? {}, access, config);
          // Internal errors are not allowed to disclose keys or upstream details.
          if (result.status >= 500) throw new HttpError(502, 'Серверная операция не выполнена');
          res.status(result.status).type('json').send(await result.text()); return;
        }
        const table = req.path.split('/')[3];
        const writing = !['GET','HEAD'].includes(req.method);
        const adminOnly = ['telegram_group_chats','buyer_real_names','user_last_visits'];
        if (adminOnly.includes(table) && access.role !== 'admin') throw new HttpError(403, 'Admin only');
        if (writing && ['user_roles','team_memberships','site_settings','boards'].includes(table) && access.role !== 'admin') throw new HttpError(403, 'Admin only');
        if (writing && table === 'profiles' && access.role !== 'admin') {
          if (req.method !== 'PATCH' || !req.body || Array.isArray(req.body) ||
              Object.keys(req.body).some(k => !['name','avatar_url'].includes(k))) throw new HttpError(403, 'Profile fields not allowed');
        }
      }
      // Ignore browser API keys and never forward the service-role key.
      req.headers.apikey = config.anonKey;
      req.headers.authorization = token ? 'Bearer ' + token : 'Bearer ' + config.anonKey;
      delete req.headers.cookie;
      delete req.headers['x-forwarded-host'];
      delete req.headers['x-forwarded-for'];
      delete req.headers['cf-ipcountry'];
      next();
    } catch (error) { next(error); }
  });
  const proxy = createProxyMiddleware({
    target: config.supabaseUrl, changeOrigin: true,
    proxyTimeout: 120_000, timeout: 120_000,
    on: {
      proxyReq: fixRequestBody,
      error: (_err, _req, res: any) => {
        if (res.writeHead && !res.headersSent) res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end?.('{"error":"Upstream unavailable"}');
      },
    },
  });
  app.use('/api/supabase', proxy);
  app.use('/api', (_req, res) => res.status(404).json({ error: 'Endpoint not found' }));
  app.use((_req, res) => res.status(404).json({ error: 'Endpoint not found' }));
  app.use((error: any, _req: any, res: any, _next: any) => {
    const status = error instanceof HttpError ? error.status : error.status === 413 ? 413 : error instanceof SyntaxError ? 400 : 500;
    res.status(status).json({ error: error instanceof HttpError ? error.message : status === 400 ? 'Invalid JSON' : 'Request failed' });
  });
  // Separate upgrade proxy; never register an unguarded ws:true handler.
  const socketProxy = createProxyMiddleware({
    target: config.supabaseUrl, changeOrigin: true,
    on: { error: (_err, _req, socket: any) => socket.destroy?.() },
  });
  const upgrade = (req: any, socket: any, head: any) => {
    try {
      const url = new URL(req.url, config.appUrl);
      if (url.pathname !== '/api/supabase/realtime/v1/websocket' ||
          !req.headers.origin || !safeOrigin(req.headers.origin, config.appUrl)) { socket.destroy(); return; }
      // Actual per-channel user JWT is handled and checked by Supabase Realtime/RLS.
      url.pathname = '/realtime/v1/websocket';
      url.searchParams.set('apikey', config.anonKey);
      req.url = url.pathname + url.search;
      delete req.headers.cookie;
      req.headers.apikey = config.anonKey;
      socketProxy.upgrade(req, socket, head);
    } catch { socket.destroy(); }
  };
  return { app, upgrade };
}
