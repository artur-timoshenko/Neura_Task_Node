-- Composite & supporting indexes
CREATE INDEX IF NOT EXISTS idx_tasks_user_status_board ON public.tasks (user_id, status, board);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON public.tasks (updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON public.tasks (created_at);
CREATE INDEX IF NOT EXISTS idx_task_comments_task_id ON public.task_comments (task_id);
CREATE INDEX IF NOT EXISTS idx_task_attachments_task_id ON public.task_attachments (task_id);
CREATE INDEX IF NOT EXISTS idx_task_attachments_category_created ON public.task_attachments (category, created_at);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles (user_id);

-- Aggregated stats RPC: replaces 4 separate client queries with 1 server-side aggregation
CREATE OR REPLACE FUNCTION public.get_user_stats(_from timestamptz, _to timestamptz)
RETURNS TABLE (
  user_id uuid,
  user_name text,
  done_tasks bigint,
  total_tasks bigint,
  workload_hours numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH today_start AS (
    SELECT date_trunc('day', now()) AS d
  ),
  today_end AS (
    SELECT (SELECT d FROM today_start) + interval '19 hours' AS d
  )
  SELECT
    p.id AS user_id,
    COALESCE(p.name, '—') AS user_name,
    COALESCE(SUM(CASE WHEN t.status = 'done' AND t.updated_at >= _from AND t.updated_at <= _to THEN 1 ELSE 0 END), 0)::bigint AS done_tasks,
    COALESCE(COUNT(t.id), 0)::bigint AS total_tasks,
    COALESCE(SUM(
      CASE WHEN t.created_at >= (SELECT d FROM today_start)
            AND t.created_at <= (SELECT d FROM today_end)
        THEN COALESCE(t.complexity, 1)
        ELSE 0
      END
    ), 0)::numeric AS workload_hours
  FROM public.profiles p
  LEFT JOIN public.tasks t ON t.user_id = p.id
  WHERE has_role(auth.uid(), 'admin'::app_role)
  GROUP BY p.id, p.name
  ORDER BY done_tasks DESC;
$$;

-- Batched action log insert
CREATE OR REPLACE FUNCTION public.log_actions_batch(_events jsonb)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  inserted_count integer := 0;
BEGIN
  IF _events IS NULL OR jsonb_typeof(_events) <> 'array' THEN
    RETURN 0;
  END IF;

  INSERT INTO public.action_logs (
    actor_id, target_user_id, task_id, entity_type, entity_id, action, details, created_at
  )
  SELECT
    auth.uid(),
    NULLIF(e->>'target_user_id','')::uuid,
    NULLIF(e->>'task_id','')::uuid,
    e->>'entity_type',
    NULLIF(e->>'entity_id','')::uuid,
    e->>'action',
    COALESCE(e->'details', '{}'::jsonb),
    COALESCE(NULLIF(e->>'created_at','')::timestamptz, now())
  FROM jsonb_array_elements(_events) AS e
  WHERE e->>'action' IS NOT NULL AND e->>'entity_type' IS NOT NULL;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;
