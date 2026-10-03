CREATE OR REPLACE FUNCTION public.log_action(_action text, _entity_type text, _entity_id uuid DEFAULT NULL::uuid, _task_id uuid DEFAULT NULL::uuid, _target_user_id uuid DEFAULT NULL::uuid, _details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  new_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;
  IF _action IS NULL OR length(_action) = 0 OR length(_action) > 64 THEN
    RETURN NULL;
  END IF;
  IF _entity_type IS NULL OR length(_entity_type) = 0 OR length(_entity_type) > 64 THEN
    RETURN NULL;
  END IF;
  IF _details IS NOT NULL AND length(_details::text) > 8000 THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.action_logs (
    actor_id, target_user_id, task_id, entity_type, entity_id, action, details
  ) VALUES (
    auth.uid(), _target_user_id, _task_id, _entity_type, _entity_id, _action, COALESCE(_details, '{}'::jsonb)
  )
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.log_actions_batch(_events jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  inserted_count integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;
  IF _events IS NULL OR jsonb_typeof(_events) <> 'array' THEN
    RETURN 0;
  END IF;
  IF jsonb_array_length(_events) > 200 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.action_logs (
    actor_id, target_user_id, task_id, entity_type, entity_id, action, details, created_at
  )
  SELECT
    auth.uid(),
    NULLIF(e->>'target_user_id','')::uuid,
    NULLIF(e->>'task_id','')::uuid,
    left(e->>'entity_type', 64),
    NULLIF(e->>'entity_id','')::uuid,
    left(e->>'action', 64),
    COALESCE(e->'details', '{}'::jsonb),
    COALESCE(NULLIF(e->>'created_at','')::timestamptz, now())
  FROM jsonb_array_elements(_events) AS e
  WHERE e->>'action' IS NOT NULL AND e->>'entity_type' IS NOT NULL
    AND length(COALESCE(e->'details','{}'::jsonb)::text) <= 8000;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$function$;
