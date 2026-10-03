-- Allow users to see profiles of people who commented on tasks assigned to them
CREATE POLICY "Users can see commenter profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT tc.user_id FROM public.task_comments tc
      JOIN public.tasks t ON t.id = tc.task_id
      WHERE t.user_id = auth.uid()
    )
  );
