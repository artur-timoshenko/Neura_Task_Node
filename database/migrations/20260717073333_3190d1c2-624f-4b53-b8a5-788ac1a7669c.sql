ALTER TABLE public.task_chat_messages ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.buyer_chat_messages ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.task_chat_messages ALTER COLUMN body DROP NOT NULL;
ALTER TABLE public.buyer_chat_messages ALTER COLUMN body DROP NOT NULL;
