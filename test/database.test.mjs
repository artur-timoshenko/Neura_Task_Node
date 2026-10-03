import { PGlite } from '@electric-sql/pglite';
import { readdir, readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

// In-memory PostgreSQL with only the managed platform schemas stubbed.
// Application migrations, functions, constraints and RLS run as real SQL.
const db = new PGlite();
try {
  await db.exec(`
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role BYPASSRLS;
    CREATE SCHEMA auth;
    CREATE SCHEMA storage;
    CREATE SCHEMA realtime;
    CREATE TABLE realtime.messages (id bigint);
    CREATE TABLE auth.users (id uuid PRIMARY KEY, email text, raw_user_meta_data jsonb DEFAULT '{}');
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.role', true), '') $$;
    GRANT USAGE ON SCHEMA auth, public, storage TO anon, authenticated, service_role;
    CREATE TABLE storage.buckets (id text PRIMARY KEY, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    CREATE TABLE storage.objects (id uuid DEFAULT gen_random_uuid() PRIMARY KEY, bucket_id text, name text, owner uuid,
      owner_id text, metadata jsonb, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql IMMUTABLE AS
      $$ SELECT (string_to_array($1, '/'))[1:array_length(string_to_array($1, '/'), 1)-1] $$;
    CREATE PUBLICATION supabase_realtime;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
    GRANT ALL ON storage.objects TO anon, authenticated, service_role;
  `);
  const files = (await readdir('database/migrations')).filter(f => f.endsWith('.sql')).sort();
  await db.exec(await readFile('database/install-new.sql', 'utf8'));
  assert.equal((await db.query("SELECT count(*)::int AS n FROM storage.buckets")).rows[0].n, 4);
  assert.equal((await db.query("SELECT public FROM storage.buckets WHERE id='guide-files'")).rows[0].public, false);
  await db.exec(await readFile('database/upgrade-existing.sql', 'utf8'));
  await db.exec(await readFile('database/upgrade-existing.sql', 'utf8'));
  const ids = {
    admin: '00000000-0000-4000-8000-000000000001',
    a: '00000000-0000-4000-8000-000000000002',
    b: '00000000-0000-4000-8000-000000000003',
  };
  for (const [name, id] of Object.entries(ids)) {
    await db.query(`INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES ($1,$2,$3)`, [id, name + '@test.invalid', JSON.stringify({ name })]);
    await db.query(`INSERT INTO user_roles (user_id,role) VALUES ($1,$2) ON CONFLICT (user_id) DO UPDATE SET role=excluded.role`, [id, name === 'admin' ? 'admin' : 'user']);
  }
  await db.query('INSERT INTO tasks (title,user_id,created_by) VALUES ($1,$2,$3)', ['Private A', ids.a, ids.admin]);
  await db.query('INSERT INTO tasks (title,user_id,created_by) VALUES ($1,$2,$3)', ['Private B', ids.b, ids.admin]);
  async function asUser(id) {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub',$1,false), set_config('request.jwt.claim.role','authenticated',false)", [id]);
    await db.exec('SET ROLE authenticated');
  }
  await asUser(ids.a);
  assert.deepEqual((await db.query('SELECT title FROM tasks ORDER BY title')).rows, [{ title: 'Private A' }]);
  await assert.rejects(db.query("UPDATE profiles SET banned=true WHERE id=$1", [ids.a]), /Protected profile fields/);
  await db.query("UPDATE profiles SET name='Renamed' WHERE id=$1", [ids.a]);
  await assert.rejects(db.query("UPDATE user_roles SET role='admin' WHERE user_id=$1 RETURNING *", [ids.a]).then(r => {
    if (r.rows.length === 0) throw new Error('role update denied');
  }), /denied|permission/);
  await assert.rejects(db.query('SELECT * FROM hub_projects'), /permission denied/);
  await asUser(ids.admin);
  assert.equal((await db.query('SELECT * FROM tasks')).rows.length, 2);
  await db.query('UPDATE profiles SET banned=true WHERE id=$1', [ids.b]);
  await asUser(ids.b);
  assert.equal((await db.query('SELECT * FROM tasks')).rows.length, 0);
  console.log(`PASS: ${files.length} migrations; user isolation, admin access, blocked users, profile protection and project permissions.`);
} finally { await db.close(); }
