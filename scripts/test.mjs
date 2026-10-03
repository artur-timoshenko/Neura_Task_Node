import { build } from 'esbuild';
import { readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
const files = (await readdir('test')).filter(f => f.endsWith('.test.ts'));
await build({
  entryPoints: files.map(f => 'test/' + f), outdir: '.test-build', bundle: true,
  platform: 'node', target: 'node22', format: 'esm', packages: 'external', outExtension: { '.js': '.mjs' },
});
const result = spawnSync(process.execPath, ['--test', ...files.map(f => '.test-build/' + f.replace(/\.ts$/, '.mjs'))], { stdio: 'inherit' });
process.exit(result.status ?? 1);
