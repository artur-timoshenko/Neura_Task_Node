import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import type { Config } from './config.js';
import { clients, type Access } from './access.js';
import { HttpError, uuid } from './policy.js';
import adminManageUser from './handlers/admin-manage-user.js';
import recordVisit from './handlers/record-visit.js';
import { notify } from './telegram.js';

export async function runFunction(name: string, body: any, access: Access, config: Config) {
  const { admin } = clients(config);
  if (name === 'create-task-upload') {
    if (!uuid(body.taskId)) throw new HttpError(400, 'Некорректная задача');
    if (typeof body.fileName !== 'string' || !body.fileName.trim() || body.fileName.length > 255) {
      throw new HttpError(400, 'Некорректное имя файла');
    }
    if (!Number.isSafeInteger(body.fileSize) || body.fileSize <= 0 || body.fileSize > 5 * 1024 * 1024 * 1024) {
      throw new HttpError(400, 'Некорректный размер файла');
    }

    const { data: task, error: taskError } = await admin
      .from('tasks')
      .select('id,user_id')
      .eq('id', body.taskId)
      .maybeSingle();
    if (taskError) throw new HttpError(503, 'Не удалось проверить задачу');
    if (!task) throw new HttpError(404, 'Задача не найдена');

    let allowed = access.role === 'admin' || task.user_id === access.user.id;
    if (!allowed && access.role === 'teamlead') {
      const { data: membership, error: membershipError } = await admin
        .from('team_memberships')
        .select('member_id')
        .eq('teamlead_id', access.user.id)
        .eq('member_id', task.user_id)
        .maybeSingle();
      if (membershipError) throw new HttpError(503, 'Не удалось проверить доступ');
      allowed = Boolean(membership);
    }
    if (!allowed) throw new HttpError(403, 'Нет доступа к сдаче этой задачи');

    const safeName = body.fileName.trim().normalize('NFKC')
      .replace(/[\\/\u0000-\u001f\u007f]/g, '_')
      .replace(/\s+/g, ' ')
      .slice(-180);
    const path = `${task.id}/submissions/${Date.now()}_${randomUUID()}_${safeName}`;
    const storageOrigin = new URL(config.supabaseUrl);
    if (storageOrigin.hostname.endsWith('.supabase.co') && !storageOrigin.hostname.endsWith('.storage.supabase.co')) {
      storageOrigin.hostname = storageOrigin.hostname.replace(/\.supabase\.co$/, '.storage.supabase.co');
    }
    const { data: uploadGrant, error: uploadGrantError } = await admin.storage
  .from("task-files")
  .createSignedUploadUrl(path, { upsert: false });

if (uploadGrantError || !uploadGrant?.token) {
  console.error("createSignedUploadUrl failed:", {
    message: uploadGrantError?.message,
    statusCode: (uploadGrantError as any)?.statusCode,
    error: (uploadGrantError as any)?.error,
    bucket: "task-files",
    path,
  });

  throw new HttpError(502, "Не удалось подготовить загрузку");
}

return Response.json({
  path,
  resumableUrl: `${storageOrigin.origin}/storage/v1/upload/resumable`,
  uploadToken: uploadGrant.token,
});
  if (name === 'activate-admin') {
    // Knowledge of a shared code alone must never grant administrative access.
    const emails = (process.env.ADMIN_BOOTSTRAP_EMAILS || '').toLowerCase().split(',').map(s => s.trim());
    const secret = process.env.ADMIN_SECRET_CODE;
    if (!secret || !access.user.email_confirmed_at || !emails.includes(access.user.email?.toLowerCase() || '')) {
      throw new HttpError(403, 'Активация администратора запрещена');
    }
    const hash = (s: string) => createHash('sha256').update(s).digest();
    if (typeof body.code !== 'string' || !timingSafeEqual(hash(body.code), hash(secret))) throw new HttpError(403, 'Неверный код');
    const { error } = await admin.from('user_roles').upsert({ user_id: access.user.id, role: 'admin' }, { onConflict: 'user_id' });
    if (error) throw new HttpError(500, 'Не удалось назначить роль');
    return Response.json({ success: true });
  }
  if (name === 'admin-manage-user') {
    if (access.role !== 'admin') throw new HttpError(403, 'Требуются права администратора');
    const actions = ['create_buyer','change_password','change_name','toggle_role','set_team_members','change_email','verify_email','ban','delete'];
    if (!actions.includes(body.action)) throw new HttpError(400, 'Неизвестное действие');
    if (body.action !== 'create_buyer' && !uuid(body.targetUserId)) throw new HttpError(400, 'Некорректный пользователь');
    if (['delete','ban','toggle_role'].includes(body.action) && body.targetUserId === access.user.id) throw new HttpError(403, 'Нельзя заблокировать или понизить себя');
    if (body.action === 'change_password' && (typeof body.newPassword !== 'string' || body.newPassword.length < 12 || body.newPassword.length > 128)) throw new HttpError(400, 'Пароль: от 12 до 128 символов');
    if (body.action === 'change_email' && (typeof body.newEmail !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.newEmail))) throw new HttpError(400, 'Некорректный email');
    if (body.action === 'change_name' && (typeof body.newName !== 'string' || !body.newName.trim() || body.newName.length > 150)) throw new HttpError(400, 'Некорректное имя');
    if (body.action === 'ban' && typeof body.banned !== 'boolean') throw new HttpError(400, 'Некорректная блокировка');
    if (body.action === 'toggle_role' && !['admin','teamlead','buyer','user'].includes(body.newRole)) throw new HttpError(400, 'Некорректная роль');
    if (body.action === 'set_team_members' && (!Array.isArray(body.memberIds) || body.memberIds.length > 500 || !body.memberIds.every(uuid))) throw new HttpError(400, 'Некорректный список команды');
    return adminManageUser(new Request(config.appUrl, { method: 'POST', headers: { Authorization: 'Bearer ' + access.token, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }));
  }
  if (name === 'record-visit') {
    // Do not trust caller-supplied forwarding/country headers as identity metadata.
    return recordVisit(new Request(config.appUrl, { method: 'POST', headers: { Authorization: 'Bearer ' + access.token } }));
  }
  if (['notify-telegram','notify-telegram-chat','notify-telegram-new-task','notify-telegram-status'].includes(name)) {
    return Response.json(await notify(name, body, access, config, admin));
  }
  throw new HttpError(404, 'Функция не найдена');
}
