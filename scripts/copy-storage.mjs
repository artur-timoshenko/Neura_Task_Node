// Explicit migration tool: copies objects, never removes source objects.
import { createClient } from '@supabase/supabase-js';
const names = ['SOURCE_SUPABASE_URL', 'SOURCE_SERVICE_ROLE_KEY', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];
for (const name of names) if (!process.env[name]) throw new Error('Missing variable: ' + name);
if (new URL(process.env.SOURCE_SUPABASE_URL).origin === new URL(process.env.SUPABASE_URL).origin) {
  throw new Error('Source and destination must be different projects');
}
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const source = createClient(process.env.SOURCE_SUPABASE_URL, process.env.SOURCE_SERVICE_ROLE_KEY, options);
const target = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, options);
const apply = process.argv.includes('--copy');
let count = 0;
for (const bucket of ['task-files', 'guide-files', 'avatars', 'company-assets']) {
  async function visit(prefix = '') {
    for (let offset = 0; ; offset += 100) {
      const { data, error } = await source.storage.from(bucket).list(prefix, { limit: 100, offset, sortBy: { column: 'name', order: 'asc' } });
      if (error) throw new Error('Could not list source bucket: ' + bucket);
      for (const entry of data) {
        const name = prefix ? prefix + '/' + entry.name : entry.name;
        if (!entry.id) { await visit(name); continue; }
        if (apply) {
          const object = await source.storage.from(bucket).download(name);
          if (object.error) throw new Error('Could not download object in bucket: ' + bucket);
          const saved = await target.storage.from(bucket).upload(name, object.data, {
            contentType: entry.metadata?.mimetype || object.data.type || 'application/octet-stream',
            upsert: false,
          });
          if (saved.error) throw new Error('Could not upload object in bucket: ' + bucket + '. Destination must not contain a conflicting path; no objects are overwritten.');
        }
        count++;
      }
      if (data.length < 100) break;
    }
  }
  await visit();
  console.log('Processed bucket: ' + bucket);
}
console.log(apply ? `Copied ${count} objects.` : `Found ${count} objects. Run again with --copy to copy them.`);
