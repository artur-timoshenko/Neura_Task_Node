export function readConfig(env = process.env) {
  for (const name of ['SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','APP_URL']) {
    if (!env[name]) throw new Error('Missing server environment variable: ' + name);
  }
  const url = new URL(env.SUPABASE_URL!);
  const app = new URL(env.APP_URL!);
  if (url.protocol !== 'https:' && url.hostname !== '127.0.0.1' && url.hostname !== 'localhost') {
    throw new Error('SUPABASE_URL must use HTTPS');
  }
  if (env.NODE_ENV === 'production' && app.protocol !== 'https:') throw new Error('APP_URL must use HTTPS');
  return {
    supabaseUrl: url.origin, anonKey: env.SUPABASE_ANON_KEY!, serviceKey: env.SUPABASE_SERVICE_ROLE_KEY!,
    appUrl: app.origin, signup: env.ALLOW_SIGNUP === 'true',
    port: Number(env.PORT || 3001), production: env.NODE_ENV === 'production',
  };
}
export type Config = ReturnType<typeof readConfig>;
