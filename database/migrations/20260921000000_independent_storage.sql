-- Infrastructure created outside source migrations in the former deployment.
INSERT INTO storage.buckets (id, name, public) VALUES
  ('guide-files', 'guide-files', false),
  ('task-files', 'task-files', false),
  ('avatars', 'avatars', true),
  ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;
UPDATE storage.buckets SET public = false WHERE id IN ('task-files', 'guide-files');

-- Use the latest helper, which includes task chats, buyer chats and team members.
-- Keeping the helper in a non-exposed schema avoids granting a browser RPC.
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.can_access_task_file(text) TO authenticated, service_role;
ALTER POLICY "Authorized users can view task files" ON storage.objects
  USING (bucket_id = 'task-files' AND private.can_access_task_file(name));
ALTER POLICY "Authorized users can upload task files" ON storage.objects
  WITH CHECK (bucket_id = 'task-files' AND private.can_access_task_file(name));
ALTER POLICY "Authorized users can update task files" ON storage.objects
  USING (bucket_id = 'task-files' AND private.can_access_task_file(name))
  WITH CHECK (bucket_id = 'task-files' AND private.can_access_task_file(name));
ALTER POLICY "Authorized users can delete task files" ON storage.objects
  USING (bucket_id = 'task-files' AND private.can_access_task_file(name));
