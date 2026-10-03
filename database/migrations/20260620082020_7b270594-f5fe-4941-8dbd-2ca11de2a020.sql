
-- ============ Storage: task-files bucket ============

-- Drop old policies
DROP POLICY IF EXISTS "Task owners and admins can upload task files" ON storage.objects;
DROP POLICY IF EXISTS "Task owners and admins can view task files" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete task files" ON storage.objects;

-- Helper: check if current user can manage a given task-files path
-- Path is either '{task_id}/...' or 'description-images/{user_id}/...'
CREATE OR REPLACE FUNCTION public.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  first_segment text;
  task_owner uuid;
  task_uuid uuid;
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
    RETURN split_part(_path, '/', 2) = auth.uid()::text;
  END IF;

  -- {task_id}/...
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
  IF public.is_teamlead_of(auth.uid(), task_owner) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.can_access_task_file(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_task_file(text) TO authenticated, service_role;

CREATE POLICY "Authorized users can view task files"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'task-files' AND public.can_access_task_file(name));

CREATE POLICY "Authorized users can upload task files"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'task-files' AND public.can_access_task_file(name));

CREATE POLICY "Authorized users can update task files"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'task-files' AND public.can_access_task_file(name))
WITH CHECK (bucket_id = 'task-files' AND public.can_access_task_file(name));

CREATE POLICY "Authorized users can delete task files"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'task-files' AND public.can_access_task_file(name));

-- ============ Revoke public/anon execute on internal SECURITY DEFINER functions ============

-- Internal helpers (called only from RLS / app as authenticated): revoke anon
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_teamlead(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_teamlead(uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_teamlead_of(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_teamlead_of(uuid, uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_user_stats(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_stats(timestamptz, timestamptz) TO authenticated, service_role;

-- Service-only functions: revoke from anon and authenticated
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_submissions() FROM PUBLIC, anon, authenticated;

-- ============ Realtime: require authentication for subscriptions ============
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can receive realtime messages" ON realtime.messages;
CREATE POLICY "Authenticated users can receive realtime messages"
ON realtime.messages FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "Authenticated users can send realtime messages" ON realtime.messages;
CREATE POLICY "Authenticated users can send realtime messages"
ON realtime.messages FOR INSERT TO authenticated
WITH CHECK (true);
