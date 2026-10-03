import { readdir, readFile, writeFile } from 'node:fs/promises';
const files = (await readdir('database/migrations')).filter(f => f.endsWith('.sql')).sort();
let sql = `-- FRESH EMPTY SUPABASE PROJECT ONLY. Existing databases: use upgrade-existing.sql.
-- Each migration commits separately so PostgreSQL enum additions can be used safely.
DO $$ BEGIN
  IF to_regclass('public.profiles') IS NOT NULL THEN
    RAISE EXCEPTION 'Database already initialized. Use upgrade-existing.sql instead.';
  END IF;
END $$;
`;
for (const file of files) {
  let content = (await readFile('database/migrations/' + file, 'utf8')).trim();
  content = content.replace(/^BEGIN;\s*/i, '').replace(/\s*COMMIT;$/i, '');
  sql += `\n-- ${file}\nBEGIN;\n${content}\nCOMMIT;\n`;
}
await writeFile('database/install-new.sql', sql);
console.log(`Generated install-new.sql from ${files.length} migrations.`);
