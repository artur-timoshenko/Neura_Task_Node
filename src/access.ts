import { createClient } from '@supabase/supabase-js';
import type { Config } from './config.js';
import { HttpError } from './policy.js';

export function clients(config: Config) {
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const admin = createClient(config.supabaseUrl, config.serviceKey, options);
  const forUser = (token: string) => createClient(config.supabaseUrl, config.anonKey, {
    ...options, global: { headers: { Authorization: 'Bearer ' + token } },
  });
  // Never use the service-role client for user-selected data queries.
  async function authenticate(token: string) {
    const db = forUser(token);
    const { data, error } = await db.auth.getUser(token);
    if (error || !data.user) throw new HttpError(401, 'Сессия недействительна. Войдите снова.');
    const [profile, roles] = await Promise.all([
      admin.from('profiles').select('id,name,banned').eq('id', data.user.id).maybeSingle(),
      admin.from('user_roles').select('role').eq('user_id', data.user.id).maybeSingle(),
    ]);
    if (profile.error || roles.error) throw new HttpError(503, 'Не удалось проверить права');
    if (!profile.data || profile.data.banned) throw new HttpError(403, 'Доступ заблокирован');
    return { user: data.user, role: roles.data?.role ?? 'user', profile: profile.data, db, token };
  }
  return { admin, forUser, authenticate };
}
export type Access = Awaited<ReturnType<ReturnType<typeof clients>['authenticate']>>;
