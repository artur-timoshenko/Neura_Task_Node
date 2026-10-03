
-- 1) Add 'buyer' role
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'buyer';

-- 2) Add buyer_id on tasks
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS buyer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_buyer_id ON public.tasks(buyer_id);

-- 3) Chat between designer <-> buyer, admin can see and write as buyer
CREATE TABLE IF NOT EXISTS public.task_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  as_buyer boolean NOT NULL DEFAULT false,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_chat_messages_task_id ON public.task_chat_messages(task_id, created_at);

GRANT SELECT, INSERT ON public.task_chat_messages TO authenticated;
GRANT ALL ON public.task_chat_messages TO service_role;

ALTER TABLE public.task_chat_messages ENABLE ROW LEVEL SECURITY;

-- Read: admin/teamlead OR designer OR buyer of that task
CREATE POLICY "chat_select_participants" ON public.task_chat_messages
FOR SELECT TO authenticated
USING (
  private.has_role(auth.uid(), 'admin'::app_role)
  OR private.has_role(auth.uid(), 'teamlead'::app_role)
  OR EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_chat_messages.task_id
      AND (t.user_id = auth.uid() OR t.buyer_id = auth.uid())
  )
);

-- Insert: sender must be authed user; must be a participant.
-- as_buyer=true is only allowed for admins.
CREATE POLICY "chat_insert_participants" ON public.task_chat_messages
FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND (
    (as_buyer = true AND private.has_role(auth.uid(), 'admin'::app_role))
    OR (
      as_buyer = false
      AND (
        private.has_role(auth.uid(), 'admin'::app_role)
        OR EXISTS (
          SELECT 1 FROM public.tasks t
          WHERE t.id = task_chat_messages.task_id
            AND (t.user_id = auth.uid() OR t.buyer_id = auth.uid())
        )
      )
    )
  )
);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_chat_messages;
