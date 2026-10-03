CREATE TABLE IF NOT EXISTS public.telegram_group_chats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id text NOT NULL,
  label text,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.telegram_group_chats TO authenticated;
GRANT ALL ON public.telegram_group_chats TO service_role;
ALTER TABLE public.telegram_group_chats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins manage telegram group chats" ON public.telegram_group_chats;
CREATE POLICY "Admins manage telegram group chats"
ON public.telegram_group_chats FOR ALL TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

CREATE INDEX IF NOT EXISTS idx_telegram_group_chats_user ON public.telegram_group_chats (user_id);

INSERT INTO public.telegram_group_chats (chat_id, user_id)
SELECT DISTINCT trim(part), NULL::uuid
FROM public.site_settings s,
     LATERAL unnest(string_to_array(coalesce(s.value,''), ',')) AS part
WHERE s.key = 'telegram_group_chat_ids' AND trim(part) <> ''
  AND NOT EXISTS (SELECT 1 FROM public.telegram_group_chats g WHERE g.chat_id = trim(part));
