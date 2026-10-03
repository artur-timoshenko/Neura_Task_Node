-- Add priority enum
CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');

-- Add priority column to tasks
ALTER TABLE public.tasks ADD COLUMN priority task_priority NOT NULL DEFAULT 'medium';

-- Create task_comments table
CREATE TABLE public.task_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;

-- Comments: users can view comments on their own tasks
CREATE POLICY "Users can view comments on own tasks" ON public.task_comments
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_comments.task_id AND tasks.user_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

-- Comments: users can insert comments on their own tasks
CREATE POLICY "Users can insert comments on own tasks" ON public.task_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id AND (
      EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_comments.task_id AND tasks.user_id = auth.uid())
      OR public.has_role(auth.uid(), 'admin')
    )
  );

-- Comments: admins full access
CREATE POLICY "Admins full access to comments" ON public.task_comments
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Create task_attachments table  
CREATE TABLE public.task_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_size bigint,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view attachments on own tasks" ON public.task_attachments
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_attachments.task_id AND tasks.user_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

CREATE POLICY "Users can insert attachments on own tasks" ON public.task_attachments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id AND (
      EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_attachments.task_id AND tasks.user_id = auth.uid())
      OR public.has_role(auth.uid(), 'admin')
    )
  );

CREATE POLICY "Admins full access to attachments" ON public.task_attachments
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Storage bucket for task files
INSERT INTO storage.buckets (id, name, public) VALUES ('task-files', 'task-files', true);

-- Storage policies
CREATE POLICY "Authenticated users can upload task files" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'task-files');

CREATE POLICY "Anyone can view task files" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'task-files');

-- Enable realtime for comments
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_comments;
