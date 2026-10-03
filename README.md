# Neura Task Hub — Backend

Самостоятельный Node.js 22 + TypeScript + Express API. Запускается отдельно от frontend;
в архиве нет React-компонентов, стилей или frontend-сборки. В каждом архиве свой lockfile.
Начните с `START-HERE.md`: он описывает запуск обоих сервисов на Railway.

## Что находится здесь

- `src/app.ts` — защищённый API gateway для Auth, данных, файлов и Realtime.
- `src/access.ts`, `policy.ts`, `functions.ts` — проверка пользователя, роли, блокировки и административных операций.
- `src/projects.ts` — проекты, участники, дерево задач и контроль версий при одновременном редактировании.
- `src/telegram.ts` — прямой Telegram Bot API, кнопки статусов, отложенные уведомления и worker.
- `database/` — схема, RLS, миграции, установка с нуля и обновление существующей базы.
- `email-templates/` — шесть почтовых шаблонов для стандартного Supabase Auth + Custom SMTP.
- `scripts/` — сборка, создание первого администратора и ручной перенос файлов/Projects.

База PostgreSQL, Auth, Storage и Realtime используют **собственный Supabase-проект**.
Supabase — отдельный сервис: его аккаунт и ключи должны принадлежать вам. Сервисы
приложения размещаются на Railway. Обычный PostgreSQL Railway не заменяет весь
Supabase API: одной переменной DATABASE_URL здесь недостаточно.

## Локальный запуск

Откройте PowerShell именно в папке backend, где лежит package.json:

```powershell
Copy-Item .env.example .env
notepad .env
npm ci
npm run dev
```

Заполните SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
APP_URL=http://localhost:8080 — адрес frontend; PORT=3001 — порт backend.
Используйте localhost в браузере, а не 127.0.0.1: это разные Origin.
Worker Telegram до переключения оставьте выключенным.

Production локально:

```powershell
npm run check
npm run build
npm start
```

Обе команды запуска читают локальный .env автоматически. В Railway значения задаются
через Variables; .env в репозиторий не добавляется. Production в Docker требует HTTPS APP_URL.
При разработке backend перезапускается автоматически после изменения исходников.

## База: выберите один сценарий

**Новая пустая база:** создайте собственный Supabase-проект. В SQL Editor выполните
`database/install-new.sql` целиком. Он содержит 60 последовательных миграций с отдельными
транзакциями для enum, создаёт четыре bucket, политики, таблицы и публикации Realtime.
Повторный запуск на уже созданной базе останавливается защитной проверкой.

**Существующая база с таблицами этого приложения:** сначала сделайте резервную копию,
затем выполните только `database/upgrade-existing.sql`. Не применяйте install-new.sql
или всю историю к рабочей базе. Обновление не импортирует данные и не удаляет задачи.

**Перенос в другой проект:** следуйте `MIGRATION.md`. Дамп схемы/данных и установка
пустой схемы — разные пути; не накладывайте два полных набора CREATE TABLE друг на друга.

## Первый администратор в новой базе

Чтобы не зависеть от открытой регистрации, добавьте временно в локальный backend .env:

```env
INITIAL_ADMIN_EMAIL=ВАША_ПОЧТА
INITIAL_ADMIN_PASSWORD=ВАШ_СЛУЧАЙНЫЙ_ПАРОЛЬ_МИНИМУМ_12_СИМВОЛОВ
INITIAL_ADMIN_NAME=Administrator
```

После применения схемы:

```powershell
npm run admin:create
```

Скрипт создаёт подтверждённого пользователя и роль admin. Существующие аккаунты он
не меняет. Удалите INITIAL_ADMIN_PASSWORD из .env после создания и войдите на frontend.
Для существующей базы прежние пользователи/роли сохраняются, создавать админа заново не нужно.

ALLOW_SIGNUP=false закрывает публичную регистрацию через API. Если нужна прежняя
открытая регистрация, поставьте true и включите регистрацию в Supabase Auth.
Пользователи без назначенной роли видят прежний экран «ДОСТУП НЕ ВЫДАН».

## Email: SMTP

В Supabase Authentication настройте Custom SMTP: host, port, username, password,
sender email и sender name вашего почтового провайдера. Отключите прежний Send Email Hook,
если он был включён: при активном hook стандартный SMTP-путь не используется.

В Email Templates вставьте содержимое соответствующих файлов:

| Шаблон Supabase | Файл | Тема |
| --- | --- | --- |
| Confirm signup | signup.html | Подтвердите ваш email |
| Invite user | invite.html | Вас пригласили |
| Magic link | magic-link.html | Ссылка для входа |
| Reset password | recovery.html | Сброс пароля |
| Change email address | email-change.html | Подтвердите смену email |
| Reauthentication | reauthentication.html | Ваш код подтверждения |

Сохраняются подтверждение email, приглашения, вход по ссылке, восстановление пароля,
смена адреса и код повторной проверки. Доставку, срок жизни и проверку токенов выполняет
Supabase Auth. Старый почтовый шлюз и его очередь не нужны. SMTP-пароль хранится
в настройках Supabase Auth, а не в браузере и не в frontend Variables.

Site URL = APP_URL. Redirect URLs: APP_URL и APP_URL/reset-password. Для локальной
проверки добавьте http://localhost:8080 и http://localhost:8080/reset-password.

Документация: [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp),
[Email Templates](https://supabase.com/docs/guides/auth/auth-email-templates).

## Telegram

Задайте TELEGRAM_BOT_TOKEN из BotFather. Chat ID и привязки дизайнеров остаются
в site_settings и telegram_group_chats и настраиваются в прежнем интерфейсе.
TELEGRAM_ADMIN_USER_IDS — числовые Telegram user ID через запятую; только им разрешены
кнопки изменения статуса в настроенном личном чате. Это не chat ID группы.

Перед включением worker остановите прежние poller/cron и удалите webhook этого бота,
если он использовался. `database/disable-legacy-jobs.sql` отключает известные старые
расписания без удаления данных. Проверьте внешние расписания отдельно.
После этого TELEGRAM_WORKER_ENABLED=true. Держите одну реплику backend и выключите
Serverless/засыпание для постоянно работающего worker. Frontend масштабируется отдельно.

Сохраняются уведомления о новых задачах, проверке, правках и сообщениях, кнопки
«Выполнено» / «На правки», рабочее окно групп 10:00–19:00 Europe/Kyiv и отложенная очередь.
При сбое после отправки возможен повтор сообщения: доставка at-least-once.

## Обслуживание и перенос

`database/enable-maintenance.sql` содержит SQL-расписания очистки с прежними сроками:
сданные вложения 14 дней, картинки чатов 5 дней, завершённые задачи 3 месяца.
Для этих расписаний включите pg_cron в Supabase Extensions. Они не вызывают внешние
HTTP-функции. На существующей базе сначала проверьте действующие cleanup jobs,
чтобы не дублировать их. Эти операции удаляют устаревшие данные согласно указанным срокам.

`MIGRATION.md` объясняет перенос данных, файлов и проектов из localStorage.
Проверки и их ограничения перечислены в VERIFICATION.md.

## API и границы доступа

- /api/health — состояние процесса, не полноценная проверка доступности базы.
- /api/supabase/auth/v1/* — разрешённые операции входа/сессии через backend.
- /api/supabase/rest/v1/* — разрешённые таблицы/RPC с пользовательским JWT и RLS.
- /api/supabase/storage/v1/* — загрузка/скачивание/подпись файлов.
- /api/supabase/realtime/v1/websocket — WebSocket с проверкой Origin; канал защищает RLS.
- /api/supabase/functions/v1/* — локальные Express-обработчики, а не Edge Functions.
- /api/projects — проверка участников и версии документа.

SUPABASE_SERVICE_ROLE_KEY и TELEGRAM_BOT_TOKEN существуют только в backend.
Обычные CRUD идут под пользовательским JWT; service-role используется для разрешённых
серверных операций. RLS отключать нельзя. Сессия пользователя, как и раньше, хранится
в localStorage через SDK; это не HttpOnly-cookie. Frontend использует SDK как клиент
протокола к /api и не получает серверные ключи.
