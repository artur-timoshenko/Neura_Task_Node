CREATE OR REPLACE FUNCTION public.cleanup_old_chat_images()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT name FROM storage.objects
    WHERE bucket_id = 'task-files'
      AND (name LIKE 'chat/%' OR name LIKE 'buyer-chat/%')
      AND created_at < now() - interval '5 days'
  LOOP
    DELETE FROM storage.objects WHERE bucket_id = 'task-files' AND name = rec.name;
    UPDATE public.task_chat_messages SET image_url = NULL WHERE image_url = rec.name;
    UPDATE public.buyer_chat_messages SET image_url = NULL WHERE image_url = rec.name;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_old_chat_images() FROM PUBLIC, anon, authenticated;
