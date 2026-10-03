CREATE TABLE public.action_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  target_user_id uuid,
  task_id uuid,
  entity_type text NOT NULL,
  entity_id uuid,
  action text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.action_logs ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_action_logs_created_at ON public.action_logs (created_at DESC);
CREATE INDEX idx_action_logs_actor_id ON public.action_logs (actor_id);
CREATE INDEX idx_action_logs_target_user_id ON public.action_logs (target_user_id);
CREATE INDEX idx_action_logs_task_id ON public.action_logs (task_id);
CREATE INDEX idx_action_logs_entity_type_action ON public.action_logs (entity_type, action);

CREATE POLICY "Admins can view action logs"
ON public.action_logs
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can insert own action logs"
ON public.action_logs
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = actor_id);

CREATE OR REPLACE FUNCTION public.log_action(
  _action text,
  _entity_type text,
  _entity_id uuid DEFAULT NULL,
  _task_id uuid DEFAULT NULL,
  _target_user_id uuid DEFAULT NULL,
  _details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  new_id uuid;
BEGIN
  INSERT INTO public.action_logs (
    actor_id,
    target_user_id,
    task_id,
    entity_type,
    entity_id,
    action,
    details
  ) VALUES (
    auth.uid(),
    _target_user_id,
    _task_id,
    _entity_type,
    _entity_id,
    _action,
    COALESCE(_details, '{}'::jsonb)
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;
