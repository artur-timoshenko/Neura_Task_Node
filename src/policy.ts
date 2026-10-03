export const CLIENT_ID = 'railway-browser-client';
const tables = new Set(['action_logs','boards','buyer_chat_messages','buyer_real_names',
  'guide_files','guides','profiles','site_settings','task_attachments','task_chat_messages',
  'task_comments','tasks','team_memberships','telegram_group_chats','user_last_visits','user_roles']);
const rpc = new Set(['log_actions_batch','get_user_stats']);
export function allowedPath(path: string, method: string): boolean {
  if (!['GET','HEAD','POST','PUT','PATCH','DELETE'].includes(method)) return false;
  if (/%2f|%5c|%2e|\\|\.\./i.test(path)) return false;
  if (/^\/auth\/v1\/(token|signup|recover|resend|verify|logout|user)$/.test(path)) return true;
  const rest = path.match(/^\/rest\/v1\/([a-z_]+)$/);
  if (rest) return tables.has(rest[1]);
  const fn = path.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
  if (fn) return method === 'POST' && rpc.has(fn[1]);
  return /^\/storage\/v1\/object\/(?:public\/|sign\/|authenticated\/|list\/)?(?:task-files|guide-files|company-assets|avatars)(?:\/|$)/.test(path);
}
export function isPublic(path: string, method: string): boolean {
  if (method === 'POST' && /^\/auth\/v1\/(token|signup|recover|resend|verify)$/.test(path)) return true;
  return ['GET','HEAD'].includes(method) &&
    /^\/storage\/v1\/object\/(public|sign)\//.test(path);
}
export function bearer(value?: string): string | null {
  const match = value?.match(/^Bearer ([A-Za-z0-9_.-]+)$/);
  return match && match[1] !== CLIENT_ID ? match[1] : null;
}
export function safeOrigin(value: string, expected: string): boolean {
  try { return new URL(value).origin === new URL(expected).origin; } catch { return false; }
}
export const uuid = (value: unknown): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
