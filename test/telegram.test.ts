import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatNotification, queuedNotificationPreview, notify } from '../src/telegram.js';

test('task notification contains safe task details and a direct link', () => {
    const text = formatNotification({
        heading: '🔄 Задача отправлена на правки',
        link: 'https://hub.test/task/19117',
        actorName: 'Admin',
        task: { task_code: '#19117', title: 'IT 23\\09 (2)' },
        designerName: 'Artur <Designer>',
    });
    assert.match(text, /Задача отправлена на правки/);
    assert.match(text, /href="https:\/\/hub\.test\/task\/19117"/);
    assert.match(text, /#19117/);
    assert.match(text, /IT 23\\09 \(2\)/);
    assert.match(text, /Artur &lt;Designer&gt;/);
    assert.match(text, /Открыть задачу/);
});

test('reference layout has no bold heading and normalizes the linked task number', () => {
    assert.equal(formatNotification({
        heading: '🔄 Задача отправлена на правки', link: 'https://hub.test/task/19117',
        actorName: 'Admin', task: { task_code: '19117', title: 'IT 23\\09 (2)' }, designerName: 'Artur Designer',
    }), '🔄 Задача отправлена на правки\n\n' +
        '🏷️ <a href="https://hub.test/task/19117">#19117</a>\n' +
        '📝 IT 23\\09 (2)\n🎨 Исполнитель: <b>Artur Designer</b>\n\n' +
        '<a href="https://hub.test/task/19117">🔗 Открыть задачу</a>');
});

test('deferred messages retain the small below-text preview of our task link', () => {
    const preview = queuedNotificationPreview('<a href="https://evil.test">x</a><a href="https://hub.test/task/42?a=1&amp;b=2">Task</a>', 'https://hub.test');
    assert.equal(preview.url, 'https://hub.test/task/42?a=1&b=2');
    assert.equal(preview.prefer_small_media, true);
    assert.equal(preview.show_above_text, false);
    assert.equal(preview.is_disabled, false);
    assert.equal(queuedNotificationPreview('legacy text', 'https://hub.test').url, 'https://hub.test');
});

test('new-task/corrections send reference format without an inline button, or queue the same HTML', async t => {
    t.mock.method(globalThis, 'fetch', async (_url: unknown, options?: RequestInit) => {
        sent.push(JSON.parse(String(options?.body)));
        return new Response(JSON.stringify({ ok: true, result: {} }), { status: 200 });
    });
    const oldToken = process.env.TELEGRAM_BOT_TOKEN;
    process.env.TELEGRAM_BOT_TOKEN = 'test-only';
    t.after(() => { if (oldToken === undefined) delete process.env.TELEGRAM_BOT_TOKEN; else process.env.TELEGRAM_BOT_TOKEN = oldToken; });
    const sent: any[] = [];
    const queued: any[] = [];
    const task = { id: '00000000-0000-4000-8000-000000000001', task_code: '#19117', title: 'IT 23', user_id: 'designer', status: 'corrections' };
    const admin: any = { from: (table: string) => ({
            select: () => table === 'telegram_group_chats'
                ? Promise.resolve({ data: [{ chat_id: '-100123', user_id: 'designer' }] })
                : { eq: () => ({ maybeSingle: async () => ({ data: { name: 'Artur Designer' } }) }) },
            insert: async (row: any) => { queued.push(row); return { error: null }; },
        }) };
    const access: any = { role: 'admin', user: { id: 'actor' }, profile: { name: 'Admin' }, db: {
            from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: task }) }) }) }),
        } };
    for (const name of ['notify-telegram-new-task', 'notify-telegram-status']) {
        await notify(name, { taskId: task.id }, access, { appUrl: 'https://hub.test' } as any, admin);
    }
    const messages = sent.length ? sent : queued;
    assert.equal(messages.length, 2);
    for (const message of messages) {
        assert.match(message.text, /Исполнитель: <b>Artur Designer<\/b>/);
        assert.match(message.text, /href="https:\/\/hub.test\/task\/19117"/);
        assert.equal(message.reply_markup, undefined);
        if (sent.length) assert.equal(message.link_preview_options.prefer_small_media, true);
    }
});
