CREATE POLICY "Users can delete own comments"
ON public.task_comments
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
