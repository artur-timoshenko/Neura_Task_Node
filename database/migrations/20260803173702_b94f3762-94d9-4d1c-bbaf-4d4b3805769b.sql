CREATE INDEX IF NOT EXISTS idx_tasks_status_completed_at ON public.tasks (status, completed_at);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles (role);
CREATE INDEX IF NOT EXISTS idx_task_attachments_task_created ON public.task_attachments (task_id, created_at DESC);
