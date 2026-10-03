
CREATE TABLE public.telegram_deferred_messages (
  id uuid primary key default gen_random_uuid(),
  chat_ids text[] not null,
  text text not null,
  parse_mode text not null default 'HTML',
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
GRANT ALL ON public.telegram_deferred_messages TO service_role;
ALTER TABLE public.telegram_deferred_messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_tdm_pending ON public.telegram_deferred_messages (created_at) WHERE sent_at IS NULL;
