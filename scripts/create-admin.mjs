// Explicit one-time CLI operation. Never called by the application on startup.
import { createClient } from '@supabase/supabase-js';
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, INITIAL_ADMIN_EMAIL, INITIAL_ADMIN_PASSWORD } = process.env;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !INITIAL_ADMIN_EMAIL || !INITIAL_ADMIN_PASSWORD) {
  throw new Error('Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, INITIAL_ADMIN_EMAIL and INITIAL_ADMIN_PASSWORD in your local .env');
}
if (INITIAL_ADMIN_PASSWORD.length < 12) throw new Error('Use an admin password with at least 12 characters');
const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const created = await db.auth.admin.createUser({
  email: INITIAL_ADMIN_EMAIL, password: INITIAL_ADMIN_PASSWORD, email_confirm: true,
  user_metadata: { name: process.env.INITIAL_ADMIN_NAME || 'Administrator' },
});
if (created.error || !created.data.user) throw new Error('Could not create admin. Check the database setup and whether this email already exists. Existing accounts are not modified.');
const { error } = await db.from('user_roles').upsert({ user_id: created.data.user.id, role: 'admin' }, { onConflict: 'user_id' });
if (error) {
  throw new Error('Account created but assigning admin role failed. Apply database migrations and assign the role in Supabase SQL Editor; do not create the account again.');
}
console.log('Administrator created. Remove INITIAL_ADMIN_PASSWORD from .env.');
