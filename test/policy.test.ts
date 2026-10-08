import { test } from 'node:test';
import assert from 'node:assert/strict';
import { allowedPath, bearer, safeOrigin, isPublic, uuid } from '../src/policy.js';
import { readConfig } from '../src/config.js';
import { authorizeProjectChange, validateTree } from '../src/projects.js';
test('user queries allowed, privileged/unknown APIs denied', () => {
  assert.equal(allowedPath('/rest/v1/tasks', 'GET'), true);
  assert.equal(allowedPath('/rest/v1/tasks', 'PATCH'), true);
  for (const path of ['/auth/v1/admin/users','/rest/v1/telegram_bot_state','/rest/v1/rpc/cleanup_old_tasks','/rest/v1/rpc/enqueue_email','/rest/v1/../tasks','/rest/v1/%2e%2e/tasks']) {
    assert.equal(allowedPath(path, 'POST'), false, path);
  }
  assert.equal(allowedPath('/rest/v1/rpc/get_user_stats', 'POST'), true);
  assert.equal(allowedPath('/rest/v1/rpc/get_user_stats', 'GET'), false);
});
test('placeholder is never considered an authenticated identity', () => {
  assert.equal(bearer('Bearer railway-browser-client'), null);
  assert.equal(bearer(undefined), null);
  assert.equal(bearer('Bearer undefined'), 'undefined'); // getUser must subsequently reject this.
  assert.equal(bearer('Bearer a.b.c'), 'a.b.c');
});
test('private data and storage signing require authentication', () => {
  assert.equal(isPublic('/rest/v1/tasks', 'GET'), false);
  assert.equal(isPublic('/storage/v1/object/sign/task-files/a', 'POST'), false);
  assert.equal(isPublic('/storage/v1/object/sign/task-files/a', 'GET'), true);
  assert.equal(isPublic('/storage/v1/object/public/avatars/a', 'DELETE'), false);
  assert.equal(isPublic('/auth/v1/user', 'PUT'), false);
});
test('storage operations and allowed bucket boundaries', () => {
  assert.equal(allowedPath('/storage/v1/object/task-files/a.png', 'POST'), true);
  assert.equal(allowedPath('/storage/v1/object/sign/guide-files/a.pdf', 'POST'), true);
  assert.equal(allowedPath('/storage/v1/bucket', 'POST'), false);
  assert.equal(allowedPath('/storage/v1/object/unknown/a', 'GET'), false);
});
test('same-origin redirects only', () => {
  assert.equal(safeOrigin('https://hub.test/reset-password', 'https://hub.test'), true);
  assert.equal(safeOrigin('https://hub.test.evil.test', 'https://hub.test'), false);
  assert.equal(safeOrigin('javascript:alert(1)', 'https://hub.test'), false);
  assert.equal(safeOrigin('https://hub.test@evil.test', 'https://hub.test'), false);
});
test('server must fail closed without credentials', () => {
  assert.throws(() => readConfig({}), /Missing server/);
  const env = { SUPABASE_URL: 'https://db.test', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'secret', APP_URL: 'https://hub.test' };
  assert.equal(readConfig(env).signup, false);
  assert.equal(readConfig({ ...env, ALLOW_SIGNUP: 'true' }).signup, true);
  assert.throws(() => readConfig({ ...env, NODE_ENV: 'production', APP_URL: 'http://hub.test' }), /HTTPS/);
  assert.throws(() => readConfig({ ...env, BUCKET: 'files' }), /incomplete/);
  const bucketConfig = readConfig({
    ...env,
    AWS_ENDPOINT_URL: 'https://storage.example.test',
    AWS_ACCESS_KEY_ID: 'access',
    AWS_SECRET_ACCESS_KEY: 'secret',
    AWS_S3_BUCKET_NAME: 'files',
    AWS_DEFAULT_REGION: 'auto',
    AWS_S3_URL_STYLE: 'path',
  });
  assert.equal(bucketConfig.bucket?.name, 'files');
  assert.equal(bucketConfig.bucket?.forcePathStyle, true);
});
test('UUID input validation', () => {
  assert.equal(uuid('d23ae004-c80a-4c52-88a2-3887b966d7bc'), true);
  assert.equal(uuid('x),id.not.is.null'), false);
});
const access: any = { user: { id: 'member' }, role: 'user', profile: { name: 'Member' } };
const sample = () => ({
  id: 'project', createdBy: 'owner', createdAt: 'date', name: 'Project', members: [{ userId: 'member' }],
  tasks: [{ id: 'a', parentId: null, title: 'Task', assignedUserIds: ['member'], comments: [], status: 'todo' }],
});
test('assignee can update task status even when JSONB reorders keys', () => {
  const old = sample();
  const changed = structuredClone(old);
  changed.tasks[0].status = 'done';
  const reordered = Object.fromEntries(Object.entries(old).reverse());
  assert.doesNotThrow(() => authorizeProjectChange(changed, reordered, access));
});
test('assignee cannot grant project or task privileges', () => {
  const old = sample();
  const next = structuredClone(old);
  next.createdBy = 'member';
  assert.throws(() => authorizeProjectChange(next, old, access), /ownership/);
  const reassigned = structuredClone(old);
  reassigned.tasks[0].assignedUserIds = ['attacker'];
  assert.throws(() => authorizeProjectChange(reassigned, old, access), /manager/);
  const outsider = { ...access, user: { id: 'outsider' } };
  const changed = structuredClone(old); changed.tasks[0].status = 'done';
  assert.throws(() => authorizeProjectChange(changed, old, outsider), /not assigned/);
});
test('reject cyclic, orphaned, duplicate task trees', () => {
  assert.throws(() => validateTree([{ id: 'a', parentId: 'a' }]), /cycle/);
  assert.throws(() => validateTree([{ id: 'a', parentId: 'missing' }]), /not found/);
  assert.throws(() => validateTree([{ id: 'a', parentId: null }, { id: 'a', parentId: null }]), /Duplicate/);
  assert.doesNotThrow(() => validateTree([{ id: 'a', parentId: null }, { id: 'b', parentId: 'a' }]));
});
