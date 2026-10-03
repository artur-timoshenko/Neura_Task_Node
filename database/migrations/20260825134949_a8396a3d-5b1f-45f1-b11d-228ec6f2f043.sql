CREATE OR REPLACE FUNCTION private.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  first_segment text;
  task_owner uuid;
  task_uuid uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF private.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  -- Images embedded into task descriptions/comments: readable by any authenticated member
  IF first_segment = 'description-images' THEN
    RETURN true;
  END IF;

  BEGIN
    task_uuid := first_segment::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  SELECT user_id INTO task_owner FROM public.tasks WHERE id = task_uuid;
  IF task_owner IS NULL THEN
    RETURN false;
  END IF;
  IF task_owner = auth.uid() THEN
    RETURN true;
  END IF;
  IF private.is_teamlead_of(auth.uid(), task_owner) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;
