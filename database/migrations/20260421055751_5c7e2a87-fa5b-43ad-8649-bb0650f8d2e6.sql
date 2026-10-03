CREATE POLICY "Users can delete own attachments"
ON public.task_attachments
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
