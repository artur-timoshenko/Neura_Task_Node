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
  WITH today_start AS (SELECT date_trunc('day', now()) AS d),
  today_end AS (SELECT (SELECT d FROM today_start) + interval '19 hours' AS d)
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
  WHERE private.has_role(auth.uid(), 'admin'::public.app_role)
    AND NOT EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = p.id AND ur.role = 'buyer'::public.app_role
    )
  GROUP BY p.id, p.name
  ORDER BY done_tasks DESC;
$$;
