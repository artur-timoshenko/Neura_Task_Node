CREATE OR REPLACE FUNCTION public.cleanup_old_tasks()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  old_ids uuid[];
  deleted_count integer := 0;
BEGIN
  SELECT array_agg(id) INTO old_ids
  FROM public.tasks
  WHERE status = 'done'::task_status
    AND COALESCE(completed_at, updated_at, created_at) < now() - interval '3 months';

  IF old_ids IS NULL OR array_length(old_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  -- files stored for these tasks
  DELETE FROM storage.objects
  WHERE bucket_id = 'task-files'
    AND name IN (SELECT file_path FROM public.task_attachments WHERE task_id = ANY(old_ids));

  DELETE FROM storage.objects
  WHERE bucket_id = 'task-files'
    AND split_part(name, '/', 1) = 'chat'
    AND split_part(name, '/', 2) = ANY(SELECT unnest(old_ids)::text);

  DELETE FROM public.task_attachments WHERE task_id = ANY(old_ids);
  DELETE FROM public.task_comments WHERE task_id = ANY(old_ids);
  DELETE FROM public.task_chat_messages WHERE task_id = ANY(old_ids);
  DELETE FROM public.action_logs WHERE task_id = ANY(old_ids);
  DELETE FROM public.tasks WHERE id = ANY(old_ids);

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_old_tasks() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_tasks() TO service_role;
