import { z } from 'zod';
import { isDeepStrictEqual as equal } from 'node:util';
import type { Access } from './access.js';
import type { SupabaseClient } from '@supabase/supabase-js';
import { HttpError } from './policy.js';
const id = z.string().regex(/^[a-zA-Z0-9-]{1,80}$/);
const comment = z.object({ id, authorId: z.string().uuid(), authorName: z.string().max(150), content: z.string().min(1).max(20000), createdAt: z.string() });
const taskSchema = z.object({
  id, parentId: id.nullable(), title: z.string().min(1).max(300), description: z.string().max(100000).optional(),
  type: z.enum(['epic','feature','task','subtask']), status: z.enum(['todo','in-progress','done','blocked']),
  estimate: z.number().finite().min(0).max(1000000), assignedUserIds: z.array(z.string().uuid()).max(500).default([]),
  dueDate: z.string().optional(), comments: z.array(comment).max(1000).default([]),
  createdAt: z.string(), updatedAt: z.string(), createdBy: z.string().uuid().optional(), collapsed: z.boolean().optional(),
});
export const projectSchema = z.object({
  id, name: z.string().min(1).max(300), description: z.string().max(20000).optional(),
  tasks: z.array(taskSchema).max(2000), teamleadId: z.string().uuid().optional(),
  members: z.array(z.object({ userId: z.string().uuid(), name: z.string().max(150), email: z.string().max(254).optional() })).max(500),
  createdAt: z.string(), updatedAt: z.string(), createdBy: z.string().uuid().optional(),
});
export function validateTree(tasks: any[]) {
  const map = new Map(tasks.map(t => [t.id, t]));
  if (map.size !== tasks.length) throw new HttpError(400, 'Duplicate task ID');
  for (const task of tasks) {
    const seen = new Set<string>();
    let current = task;
    while (current?.parentId) {
      if (seen.has(current.id)) throw new HttpError(400, 'Task tree contains a cycle');
      seen.add(current.id);
      current = map.get(current.parentId);
      if (!current) throw new HttpError(400, 'Parent task not found');
      if (seen.size > 100) throw new HttpError(400, 'Task tree too deep');
    }
  }
}
export function authorizeProjectChange(next: any, previous: any, access: Pick<Access, 'user' | 'role' | 'profile'>) {
  const manager = access.role === 'admin' || previous.createdBy === access.user.id ||
    (access.role === 'teamlead' && previous.teamleadId === access.user.id);
  if (next.createdBy !== previous.createdBy || next.createdAt !== previous.createdAt) throw new HttpError(403, 'Project ownership is immutable');
  if (access.role !== 'admin' && next.teamleadId !== previous.teamleadId) throw new HttpError(403, 'Only admin can assign teamlead');
  if (!manager) {
    const omit = (p: any) => ({ ...p, tasks: undefined, updatedAt: undefined });
    if (!equal(omit(next), omit(previous))) throw new HttpError(403, 'Project settings are read-only');
    if (next.tasks.length !== previous.tasks.length) throw new HttpError(403, 'Cannot add/delete tasks');
  }
  const now = new Date().toISOString();
  for (const task of next.tasks) {
    const old = previous.tasks.find((t: any) => t.id === task.id);
    if (!manager && (!old || !old.assignedUserIds?.includes(access.user.id))) {
      if (!equal(task, old)) throw new HttpError(403, 'Task is not assigned to you');
      continue;
    }
    if (!manager) {
      const locked = ['id','parentId','type','estimate','assignedUserIds','createdAt','createdBy'];
      if (locked.some(k => !equal(task[k], old[k]))) throw new HttpError(403, 'Task management requires manager');
      for (const c of old.comments || []) {
        const changed = task.comments.find((n: any) => n.id === c.id);
        if (c.authorId !== access.user.id && !equal(changed, c)) throw new HttpError(403, 'Cannot change another author comment');
      }
    }
    const ids = new Set();
    for (const c of task.comments) {
      if (ids.has(c.id)) throw new HttpError(400, 'Duplicate comment ID');
      ids.add(c.id);
      if (!old?.comments?.some((o: any) => o.id === c.id)) {
        c.authorId = access.user.id; c.authorName = access.profile.name; c.createdAt = now;
      }
    }
    if (!old) { task.createdBy = access.user.id; task.createdAt = now; }
  }
}
export async function projectRequest(method: string, projectId: string | undefined, body: any, access: Access, admin: SupabaseClient) {
  if (projectId && !id.safeParse(projectId).success) throw new HttpError(400, 'Invalid project ID');
  if (method === 'GET' && !projectId) {
    let query = admin.from('hub_projects').select('document,version').order('updated_at', { ascending: false });
    if (access.role !== 'admin') query = query.or('owner_id.eq.' + access.user.id + ',teamlead_id.eq.' + access.user.id + ',member_ids.cs.{' + access.user.id + '}');
    const { data, error } = await query;
    if (error) throw new HttpError(503, 'Projects unavailable: apply Railway migration');
    return (data || []).map(r => ({ ...r.document, _version: r.version }));
  }
  if (method === 'POST' && !projectId) {
    if (!['admin','teamlead'].includes(access.role)) throw new HttpError(403, 'Cannot create projects');
    const result = projectSchema.safeParse(body);
    if (!result.success) throw new HttpError(400, 'Invalid project');
    const doc = result.data;
    if (access.role !== 'admin') doc.teamleadId = access.user.id;
    doc.createdBy = access.user.id; doc.createdAt = doc.updatedAt = new Date().toISOString();
    validateTree(doc.tasks);
    authorizeProjectChange(doc, { ...doc, tasks: [] }, access);
    const { error } = await admin.from('hub_projects').insert({
      id: doc.id, owner_id: access.user.id, teamlead_id: doc.teamleadId ?? null,
      member_ids: doc.members.map(m => m.userId), document: doc, version: 1,
    });
    if (error) throw new HttpError(error.code === '23505' ? 409 : 503, 'Project not created');
    return { ...doc, _version: 1 };
  }
  if (!projectId || !['PUT','DELETE'].includes(method)) throw new HttpError(405, 'Unsupported operation');
  const { data: row, error } = await admin.from('hub_projects').select('*').eq('id', projectId).maybeSingle();
  if (error) throw new HttpError(503, 'Projects unavailable');
  if (!row || (access.role !== 'admin' && row.owner_id !== access.user.id && row.teamlead_id !== access.user.id && !row.member_ids.includes(access.user.id))) throw new HttpError(404, 'Project not found');
  if (!Number.isInteger(body._version) || body._version !== row.version) throw new HttpError(409, 'Проект изменён другим пользователем. Обновите страницу.');
  if (method === 'DELETE') {
    if (access.role !== 'admin' && row.owner_id !== access.user.id && !(access.role === 'teamlead' && row.teamlead_id === access.user.id)) throw new HttpError(403, 'Cannot delete project');
    const result = await admin.from('hub_projects').delete().eq('id', projectId).eq('version', row.version).select('id');
    if (result.error) throw new HttpError(503, 'Delete failed');
    if (!result.data?.length) throw new HttpError(409, 'Concurrent modification');
    return { deleted: true };
  }
  const parsed = projectSchema.safeParse(body);
  if (!parsed.success || parsed.data.id !== projectId) throw new HttpError(400, 'Invalid project');
  const doc = parsed.data;
  validateTree(doc.tasks);
  authorizeProjectChange(doc, row.document, access);
  doc.updatedAt = new Date().toISOString();
  const result = await admin.from('hub_projects').update({
    document: doc, member_ids: doc.members.map(m => m.userId), teamlead_id: doc.teamleadId ?? null,
    version: row.version + 1, updated_at: doc.updatedAt,
  }).eq('id', projectId).eq('version', row.version).select('id');
  if (result.error) throw new HttpError(503, 'Save failed');
  if (!result.data?.length) throw new HttpError(409, 'Concurrent modification');
  return { ...doc, _version: row.version + 1 };
}
