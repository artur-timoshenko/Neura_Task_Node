// Explicit manual import; never executed at server startup.
import { readFile } from 'node:fs/promises';
const filename = process.argv[2];
const appUrl = process.env.APP_URL;
const token = process.env.IMPORT_ACCESS_TOKEN;
if (!filename || !appUrl || !token) throw new Error('Usage: set APP_URL and IMPORT_ACCESS_TOKEN, then node scripts/import-project.mjs project.json');
const url = new URL(appUrl);
if (url.protocol !== 'https:' && !['localhost','127.0.0.1'].includes(url.hostname)) throw new Error('HTTPS required');
const data = JSON.parse(await readFile(filename, 'utf8'));
const flat = [];
function flatten(nodes, parentId = null) {
  if (!Array.isArray(nodes)) return;
  for (const node of nodes) {
    const { children, progress, ...task } = node;
    flat.push({ ...task, parentId });
    flatten(children, node.id);
  }
}
if (data.roots) flatten(data.roots);
else if (Array.isArray(data.tasks)) flat.push(...data.tasks);
else throw new Error('Expected exported project roots or tasks');
const project = {
  ...data, tasks: flat, members: data.members || [],
  createdAt: data.createdAt || new Date().toISOString(),
  updatedAt: data.updatedAt || new Date().toISOString(),
};
const response = await fetch(url.origin + '/api/projects', {
  method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify(project),
});
const result = await response.json();
if (!response.ok) throw new Error(result.error || 'Import failed');
console.log('Imported project: ' + result.id);
