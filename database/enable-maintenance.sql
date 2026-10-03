-- Run in Supabase SQL Editor after enabling pg_cron in Database > Extensions.
-- These jobs run SQL inside the database. No external HTTP endpoint is called.
SELECT cron.schedule('cleanup-expired-submissions', '0 3 * * *', $$SELECT public.cleanup_expired_submissions()$$);
SELECT cron.schedule('cleanup-old-chat-images', '30 3 * * *', $$SELECT public.cleanup_old_chat_images()$$);
SELECT cron.schedule('cleanup-old-tasks', '0 4 * * *', $$SELECT public.cleanup_old_tasks()$$);
