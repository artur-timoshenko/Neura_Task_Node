
-- 1) Add tags to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}';

-- 2) Direct chat table (not task-bound)
CREATE TABLE IF NOT EXISTS public.buyer_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  designer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  as_buyer boolean NOT NULL DEFAULT false,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS buyer_chat_pair_idx ON public.buyer_chat_messages (designer_id, buyer_id, created_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.buyer_chat_messages TO authenticated;
GRANT ALL ON public.buyer_chat_messages TO service_role;

ALTER TABLE public.buyer_chat_messages ENABLE ROW LEVEL SECURITY;

-- SELECT: participants or admin/teamlead
CREATE POLICY "buyer_chat_select" ON public.buyer_chat_messages
FOR SELECT TO authenticated
USING (
  auth.uid() = designer_id
  OR auth.uid() = buyer_id
  OR private.has_role(auth.uid(), 'admin'::app_role)
  OR private.has_role(auth.uid(), 'teamlead'::app_role)
);

-- INSERT: sender must be auth.uid(); either a participant sending as themselves,
-- or admin/teamlead (may send as buyer via as_buyer=true).
CREATE POLICY "buyer_chat_insert" ON public.buyer_chat_messages
FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND (
    (as_buyer = false AND (auth.uid() = designer_id OR auth.uid() = buyer_id))
    OR private.has_role(auth.uid(), 'admin'::app_role)
    OR private.has_role(auth.uid(), 'teamlead'::app_role)
  )
);

-- DELETE: sender or admin/teamlead
CREATE POLICY "buyer_chat_delete" ON public.buyer_chat_messages
FOR DELETE TO authenticated
USING (
  sender_id = auth.uid()
  OR private.has_role(auth.uid(), 'admin'::app_role)
  OR private.has_role(auth.uid(), 'teamlead'::app_role)
);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.buyer_chat_messages;
ALTER TABLE public.buyer_chat_messages REPLICA IDENTITY FULL;
