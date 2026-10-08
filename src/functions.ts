import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import type { Config } from './config.js';
import { clients, type Access } from './access.js';
import { HttpError, uuid } from './policy.js';
import adminManageUser from './handlers/admin-manage-user.js';
import recordVisit from './handlers/record-visit.js';
import { notify } from './telegram.js';
import { createTaskDownloadUrl, createTaskUploadUrl, deleteTaskObject, isRailwayTaskFile } from './bucket.js';

async function canAccessTask(admin: any, access: Access, taskId: string) {
  const { data: task, error } = await admin
    .from('tasks')
    .select('id,user_id,buyer_id')
    .eq('id', taskId)
    .maybeSingle();
  if (error) throw new HttpError(503, 'Не удалось проверить задачу');
  if (!task) throw new HttpError(404, 'Задача не найдена');

  let allowed = access.role === 'admin' || task.user_id === access.user.id || task.buyer_id === access.user.id;
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
  if (!allowed) throw new HttpError(403, 'Нет доступа к файлам этой задачи');
  return task;
}

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

    const task = await canAccessTask(admin, access, body.taskId);
    const category = body.category === 'attachment' ? 'attachment' : body.category === 'submission' || body.category == null
      ? 'submission'
      : null;
    if (!category) throw new HttpError(400, 'Некорректная категория файла');
    if (category === 'submission' && access.role !== 'admin' && task.user_id !== access.user.id) {
      throw new HttpError(403, 'Сдать задачу может только исполнитель или администратор');
    }

    const safeName = body.fileName.trim().normalize('NFKC')
      .replace(/[\\/\u0000-\u001f\u007f]/g, '_')
      .replace(/\s+/g, ' ')
      .slice(-180);
    const folder = category === 'submission' ? `${task.id}/submissions` : task.id;
    const relativePath = `${folder}/${Date.now()}_${randomUUID()}_${safeName}`;
    const contentType = typeof body.contentType === 'string' && body.contentType.length <= 200 &&
      /^[\w.+-]+\/[\w.+-]+$/.test(body.contentType)
      ? body.contentType
      : 'application/octet-stream';
    return Response.json(await createTaskUploadUrl(config, relativePath, contentType, body.fileSize));
  }
  if (name === 'sign-task-file') {
    if (typeof body.filePath !== 'string' || !isRailwayTaskFile(body.filePath)) {
      throw new HttpError(400, 'Некорректный путь файла');
    }
    const { data: attachment, error } = await admin
      .from('task_attachments')
      .select('task_id,file_name')
      .eq('file_path', body.filePath)
      .maybeSingle();
    if (error) throw new HttpError(503, 'Не удалось проверить файл');
    if (!attachment) throw new HttpError(404, 'Файл не найден');
    await canAccessTask(admin, access, attachment.task_id);
    const downloadName = body.download === true
      ? attachment.file_name
      : typeof body.download === 'string' && body.download.length <= 255
        ? body.download
        : undefined;
    const signedUrl = await createTaskDownloadUrl(config, body.filePath, downloadName);
    return Response.json({ signedUrl, expiresIn: 3600 });
  }
  if (name === 'delete-task-file') {
    if (typeof body.filePath !== 'string' || !isRailwayTaskFile(body.filePath)) {
      throw new HttpError(400, 'Некорректный путь файла');
    }
    const { data: attachment, error } = await admin
      .from('task_attachments')
      .select('task_id,user_id')
      .eq('file_path', body.filePath)
      .maybeSingle();
    if (error) throw new HttpError(503, 'Не удалось проверить файл');
    const taskId = attachment?.task_id || body.taskId;
    if (!uuid(taskId)) throw new HttpError(404, 'Файл не найден');
    if (!body.filePath.startsWith(`railway/${taskId}/`)) {
      throw new HttpError(400, 'Путь файла не принадлежит задаче');
    }
    await canAccessTask(admin, access, taskId);
    if (access.role !== 'admin' && attachment && attachment.user_id !== access.user.id && access.role !== 'teamlead') {
      throw new HttpError(403, 'Удалить файл может автор или администратор');
    }
    await deleteTaskObject(config, body.filePath);
    return Response.json({ success: true });
  }
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
