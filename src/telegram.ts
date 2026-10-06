import type { SupabaseClient } from '@supabase/supabase-js';
import type { Config } from './config.js';
import { clients, type Access } from './access.js';
import { HttpError, uuid } from './policy.js';

export const escapeHtml = (v: unknown) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

type NotificationTask = { task_code?: string | null; title?: string | null };

export function formatNotification(input: {
  heading: string;
  link: string;
  actorName: string;
  task?: NotificationTask | null;
  designerName?: string | null;
  message?: string | null;
  asBuyer?: boolean;
}) {
  const heading = escapeHtml(input.heading);
  const openLink = '<a href="' + escapeHtml(input.link) + '">🔗 Открыть задачу</a>';
  if (input.task) {
    const code = input.task.task_code ? '#' + String(input.task.task_code).replace(/^#+/, '') : 'Задача';
    const details = [
      '🏷️ <a href="' + escapeHtml(input.link) + '">' + escapeHtml(code) + '</a>',
      input.task.title ? '📝 ' + escapeHtml(String(input.task.title).slice(0, 200)) : '',
      '🎨 Исполнитель: <b>' + escapeHtml(input.designerName || 'Не назначен') + '</b>',
      input.message ? '💬 ' + escapeHtml(String(input.message).slice(0, 800)) : '',
    ].filter(Boolean).join('\n');
    return heading + '\n\n' + details + '\n\n' + openLink;
  }
  const sender = escapeHtml(input.actorName) + (input.asBuyer ? ' (от имени баера)' : '');
  const message = input.message ? '\n' + escapeHtml(String(input.message).slice(0, 800)) : '';
  return heading + '\n\n' + sender + message + '\n\n<a href="' + escapeHtml(input.link) + '">🔗 Открыть чаты</a>';
}

export function notificationPreview(link: string) {
  return { is_disabled: false, url: link, prefer_small_media: true, show_above_text: false };
}

// Existing queue rows contain HTML only. Recover our task link without a DB migration.
export function queuedNotificationPreview(text: string, appUrl: string) {
  const decode = (value: string) => value.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const origin = new URL(appUrl).origin;
  for (const match of text.matchAll(/href="([^"]+)"/g)) {
    try {
      const url = new URL(decode(match[1]));
      if (url.origin === origin && !url.username && !url.password) return notificationPreview(url.href);
    } catch { /* Ignore malformed links in legacy rows. */ }
  }
  return notificationPreview(appUrl);
}

export function workingHours(date = new Date()) {
  const hour = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'Europe/Kyiv', hourCycle: 'h23', hour: '2-digit' }).format(date));
  return hour >= 5 && hour < 19;
}
function safeTelegramError(error: unknown): string {
  const detail = error as { message?: string; code?: string; cause?: { message?: string; code?: string } } | null;
  let text = [detail?.code, detail?.message || String(error), detail?.cause?.code, detail?.cause?.message].filter(Boolean).join(' — ');
  for (const secret of [process.env.TELEGRAM_BOT_TOKEN, process.env.SUPABASE_ANON_KEY, process.env.SUPABASE_SERVICE_ROLE_KEY]) {
    if (secret) text = text.split(secret).join('[redacted]');
  }
  return text;
}

async function telegram(method: string, payload: Record<string, any>) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new HttpError(503, 'Telegram не настроен');
  let request = { ...payload };
  // Retry only explicit API rejections. A timeout may mean the message was delivered.
  for (let attempt = 0; attempt < 3; attempt++) {
    const result = await fetch('https://api.telegram.org/bot' + token + '/' + method, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(request),
      signal: AbortSignal.timeout(35_000),
    });
    const data = await result.json();
    if (result.ok && data.ok) return data.result;
    const description = String(data.description || 'Unknown error');
    if (method === 'sendMessage' && data.ok === false && data.error_code === 400 && attempt < 2) {
      if (/WEBPAGE_URL_INVALID|WEBPAGE_CURL_FAILED/i.test(description) && request.link_preview_options?.is_disabled !== true) {
        request = { ...request, link_preview_options: { is_disabled: true } };
        console.warn('Telegram rejected the link preview; retrying this notification without preview.');
        continue;
      }
      // Keep callback buttons and the text link if Telegram rejects a URL button.
      const rows = request.reply_markup?.inline_keyboard as Array<Array<Record<string, unknown>>> | undefined;
      if (/BUTTON_URL_INVALID|(?:inline keyboard )?button URL .*invalid/i.test(description) && rows?.some(row => row.some(button => 'url' in button))) {
        const inline_keyboard = rows.map(row => row.filter(button => !('url' in button))).filter(row => row.length);
        request = { ...request, reply_markup: inline_keyboard.length ? { ...request.reply_markup, inline_keyboard } : undefined };
        console.warn('Telegram rejected a URL button; retrying this notification with its remaining controls.');
        continue;
      }
    }
    throw new HttpError(502, safeTelegramError(new Error(`Telegram ${method}: ${data.error_code ?? result.status} — ${description}`)));
  }
  throw new HttpError(502, 'Telegram notification could not be sent');
}
async function targets(admin: SupabaseClient, designerId: string | null, personal: boolean) {
  if (personal) {
    const { data, error } = await admin.from('site_settings').select('value').eq('key', 'telegram_chat_id');
    if (error) throw new HttpError(503, 'Notification settings unavailable');
    return [...new Set((data ?? []).flatMap(r => String(r.value).split(/[,;\n]+/).map(x => x.trim()).filter(Boolean)))];
  }
  const { data, error } = await admin.from('telegram_group_chats').select('chat_id,user_id');
  if (error) throw new HttpError(503, 'Notification settings unavailable');
  return [...new Set((data ?? []).filter(r => !r.user_id || r.user_id === designerId).map(r => String(r.chat_id)))];
}
export async function notify(name: string, body: any, access: Access, config: Config, admin: SupabaseClient) {
  let task: any = null;
  let designerId: string | null = null;
  let designerName: string | null = null;
  let message: any = null;
  if (body.taskId) {
    if (!uuid(body.taskId)) throw new HttpError(400, 'Invalid task');
    const result = await access.db.from('tasks').select('id,title,task_code,user_id,buyer_id,status').eq('id', body.taskId).maybeSingle();
    if (result.error || !result.data) throw new HttpError(403, 'Нет доступа к задаче');
    task = result.data; designerId = task.user_id;
    if (designerId) {
      const designer = await admin.from('profiles').select('name,email').eq('id', designerId).maybeSingle();
      if (!designer.error) designerName = designer.data?.name || designer.data?.email || null;
    }
  } else if (name !== 'notify-telegram-chat') throw new HttpError(400, 'Task required');
  if (name === 'notify-telegram-chat') {
    let query = access.db.from(task ? 'task_chat_messages' : 'buyer_chat_messages')
        .select('body,image_url,as_buyer,created_at').eq('sender_id', access.user.id)
        .gte('created_at', new Date(Date.now() - 120_000).toISOString()).order('created_at', { ascending: false }).limit(1);
    if (task) query = query.eq('task_id', task.id);
    else {
      if (!uuid(body.designerId) || !uuid(body.buyerId)) throw new HttpError(400, 'Chat participants required');
      designerId = body.designerId;
      query = query.eq('designer_id', body.designerId).eq('buyer_id', body.buyerId);
    }
    const result = await query.maybeSingle();
    if (result.error || !result.data) throw new HttpError(403, 'Сообщение не найдено');
    message = result.data;
  }
  if (name === 'notify-telegram-new-task' && !['admin','teamlead'].includes(access.role)) throw new HttpError(403, 'Недостаточно прав');
  if (name === 'notify-telegram' && task.status !== 'review') throw new HttpError(409, 'Задача не на проверке');
  if (name === 'notify-telegram-status' && task.status !== 'corrections') throw new HttpError(409, 'Задача не на правках');
  const asBuyer = access.role === 'buyer' || (access.role === 'admin' && message?.as_buyer === true);
  const personal = name === 'notify-telegram' || (name === 'notify-telegram-chat' && !asBuyer);
  const chatIds = await targets(admin, designerId, personal);
  const headings: Record<string, string> = {
    'notify-telegram': '📋 Задача на проверку', 'notify-telegram-new-task': '🆕 Новая задача',
    'notify-telegram-status': '🔄 Задача отправлена на правки', 'notify-telegram-chat': '💬 Новое сообщение',
  };
  const link = task?.task_code ? config.appUrl + '/task/' + encodeURIComponent(String(task.task_code).replace('#', '')) : config.appUrl + '/chats';
  const text = formatNotification({
    heading: headings[name], link, actorName: access.profile.name, task, designerName,
    message: message?.body || (message?.image_url ? '📷 Изображение' : null), asBuyer,
  });
  const openButton = { text: task ? '🔗 Открыть задачу' : '🔗 Открыть чаты', url: link };
  const payload: any = {
    text,
    parse_mode: 'HTML',
    link_preview_options: notificationPreview(link),
  };
  // New-task/corrections messages match the reference: text link + small branded preview.
  if (name === 'notify-telegram-chat') payload.reply_markup = { inline_keyboard: [[openButton]] };
  if (name === 'notify-telegram') payload.reply_markup = { inline_keyboard: [
      [
        { text: '🔄 На правки', callback_data: 'corrections:' + task.id },
        { text: '✅ Выполнено', callback_data: 'done:' + task.id },
      ],
      [openButton],
    ] };
  if (!process.env.TELEGRAM_BOT_TOKEN) return { success: true, sent: 0, skipped: 'Telegram not configured' };
  if (!workingHours() && chatIds.length) {
    const { error } = await admin.from('telegram_deferred_messages').insert({ chat_ids: chatIds, text, parse_mode: 'HTML' });
    if (error) throw new HttpError(503, 'Notification queue unavailable');
    return { success: true, deferred: chatIds.length, sent: 0 };
  }
  let sent = 0;
  for (const chat_id of chatIds) { await telegram('sendMessage', { ...payload, chat_id }); sent++; }
  return { success: true, sent };
}

// One worker/replica only. DB offset survives restarts; delivery is at-least-once.
export function startTelegramWorker(config: Config) {
  if (process.env.TELEGRAM_WORKER_ENABLED !== 'true' || !process.env.TELEGRAM_BOT_TOKEN) return () => {};
  const { admin } = clients(config);
  let stopped = false;
  let timer: ReturnType<typeof setTimeout>;
  const admins = new Set((process.env.TELEGRAM_ADMIN_USER_IDS || '').split(',').map(x => x.trim()).filter(Boolean));
  async function tick() {
    try {
      const state = await admin.from('telegram_bot_state').select('update_offset').eq('id', 1).single();
      if (state.error) throw state.error;
      const updates = await telegram('getUpdates', { offset: state.data.update_offset, timeout: 10, allowed_updates: ['callback_query'] });
      for (const update of updates) {
        if (stopped) return;
        const cb = update.callback_query;
        if (cb) {
          const [action, taskId] = String(cb.data || '').split(':');
          const personalChats = await targets(admin, null, true);
          const authorized = admins.has(String(cb.from?.id)) && personalChats.includes(String(cb.message?.chat?.id));
          if (!authorized || !uuid(taskId) || !['done','corrections'].includes(action)) {
            await telegram('answerCallbackQuery', { callback_query_id: cb.id, text: 'Нет доступа' });
          } else {
            const task = await admin.from('tasks').select('completed_at,status').eq('id', taskId).maybeSingle();
            if (task.error) throw task.error;
            if (task.data?.status === 'review') {
              const result = await admin.from('tasks').update({
                status: action, completed_at: action === 'done' ? task.data.completed_at || new Date().toISOString() : null,
              }).eq('id', taskId).eq('status', 'review').select('id,title,task_code,user_id').maybeSingle();
              if (result.error) throw result.error;
              // Telegram callbacks bypass the browser's notify call, so queue this event here.
              if (action === 'corrections' && result.data) {
                const changed = result.data;
                const designer = await admin.from('profiles').select('name').eq('id', changed.user_id).maybeSingle();
                if (designer.error) throw designer.error;
                const chatIds = await targets(admin, changed.user_id, false);
                const link = changed.task_code
                    ? config.appUrl + '/task/' + encodeURIComponent(String(changed.task_code).replace(/^#+/, ''))
                    : config.appUrl;
                const text = formatNotification({
                  heading: '🔄 Задача отправлена на правки', link, actorName: '', task: changed,
                  designerName: designer.data?.name,
                });
                if (chatIds.length) {
                  const queued = await admin.from('telegram_deferred_messages').insert({ chat_ids: chatIds, text, parse_mode: 'HTML' });
                  if (queued.error) throw queued.error;
                }
              }
            }
            await telegram('answerCallbackQuery', { callback_query_id: cb.id, text: 'Статус обработан' });
            await telegram('editMessageReplyMarkup', { chat_id: cb.message.chat.id, message_id: cb.message.message_id, reply_markup: { inline_keyboard: [] } });
          }
        }
        const save = await admin.from('telegram_bot_state').update({ update_offset: update.update_id + 1, updated_at: new Date().toISOString() }).eq('id', 1);
        if (save.error) throw save.error;
      }
      if (workingHours() && !stopped) {
        const { data, error } = await admin.from('telegram_deferred_messages').select('id,chat_ids,text,parse_mode').is('sent_at', null).order('created_at').limit(20);
        if (error) throw error;
        for (const row of data ?? []) {
          for (const chat_id of row.chat_ids ?? []) {
            if (stopped) return;
            await telegram('sendMessage', {
              chat_id, text: row.text, parse_mode: row.parse_mode,
              link_preview_options: queuedNotificationPreview(row.text, config.appUrl),
            });
          }
          const save = await admin.from('telegram_deferred_messages').update({ sent_at: new Date().toISOString() }).eq('id', row.id);
          if (save.error) throw save.error;
        }
      }
    } catch (error: unknown) { console.warn('Telegram worker failed:', safeTelegramError(error)); }
    if (!stopped) timer = setTimeout(tick, 5_000);
  }
  void tick();
  return () => { stopped = true; clearTimeout(timer); };
}
