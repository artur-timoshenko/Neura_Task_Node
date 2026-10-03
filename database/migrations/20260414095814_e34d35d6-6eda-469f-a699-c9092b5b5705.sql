
-- Create cleanup function for expired submissions (older than 14 days)
CREATE OR REPLACE FUNCTION public.cleanup_expired_submissions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT id, file_path
    FROM public.task_attachments
    WHERE category = 'submission'
      AND created_at < now() - interval '14 days'
  LOOP
    -- Delete from storage via direct table delete (storage cleanup handled by Supabase)
    DELETE FROM storage.objects WHERE bucket_id = 'task-files' AND name = rec.file_path;
    -- Delete the attachment record
    DELETE FROM public.task_attachments WHERE id = rec.id;
  END LOOP;
END;
$$;

-- Schedule daily cleanup at 3 AM UTC
