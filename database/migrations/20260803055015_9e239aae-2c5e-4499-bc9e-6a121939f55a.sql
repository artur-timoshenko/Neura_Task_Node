CREATE OR REPLACE FUNCTION public.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  first_segment text;
  task_uuid uuid;
  t_owner uuid;
  t_buyer uuid;
  designer uuid;
  buyer uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  -- description-images/{user_id}/...
  IF first_segment = 'description-images' THEN
    IF split_part(_path, '/', 2) = auth.uid()::text THEN
      RETURN true;
    END IF;
    RETURN EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.description LIKE '%' || _path || '%'
        AND (t.user_id = auth.uid() OR t.buyer_id = auth.uid() OR public.is_teamlead_of(auth.uid(), t.user_id))
    );
  END IF;

  -- buyer-chat/{designer_id}/{buyer_id}/...
  IF first_segment = 'buyer-chat' THEN
    BEGIN
      designer := split_part(_path, '/', 2)::uuid;
      buyer := split_part(_path, '/', 3)::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
    RETURN auth.uid() = designer
        OR auth.uid() = buyer
        OR public.is_teamlead_of(auth.uid(), designer);
  END IF;

  -- chat/{task_id}/...
  IF first_segment = 'chat' THEN
    BEGIN
      task_uuid := split_part(_path, '/', 2)::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
  ELSE
    -- {task_id}/...
    BEGIN
      task_uuid := first_segment::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
  END IF;

  SELECT t.user_id, t.buyer_id INTO t_owner, t_buyer FROM public.tasks t WHERE t.id = task_uuid;
  IF t_owner IS NULL THEN
    RETURN false;
  END IF;

  RETURN auth.uid() = t_owner
      OR auth.uid() = t_buyer
      OR public.is_teamlead_of(auth.uid(), t_owner);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.can_access_task_file(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.can_access_task_file(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_task_file(text) TO authenticated, service_role;
