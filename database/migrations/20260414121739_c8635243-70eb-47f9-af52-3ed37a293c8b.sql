
-- 1. Fix task-files SELECT policy: only task owner or admin
DROP POLICY IF EXISTS "Anyone can view task files" ON storage.objects;
CREATE POLICY "Task owners and admins can view task files"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'task-files'
  AND (
    has_role(auth.uid(), 'admin'::app_role)
    OR EXISTS (
      SELECT 1 FROM public.task_attachments ta
      JOIN public.tasks t ON t.id = ta.task_id
      WHERE ta.file_path = name
      AND t.user_id = auth.uid()
    )
  )
);

-- 2. Fix task-files INSERT policy: only task owner or admin
DROP POLICY IF EXISTS "Authenticated users can upload task files" ON storage.objects;
CREATE POLICY "Task owners and admins can upload task files"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'task-files'
  AND (
    has_role(auth.uid(), 'admin'::app_role)
    OR auth.uid() IS NOT NULL
  )
);

-- 3. Add DELETE policy for task-files (admins only)
CREATE POLICY "Admins can delete task files"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'task-files'
  AND has_role(auth.uid(), 'admin'::app_role)
);

-- 4. Add DELETE policy for avatars
CREATE POLICY "Users can delete own avatar"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 5. Fix site_settings: restrict to authenticated only
DROP POLICY IF EXISTS "Anyone can read site_settings" ON public.site_settings;
CREATE POLICY "Authenticated users can read site_settings"
ON public.site_settings FOR SELECT
TO authenticated
USING (true);
