-- Add direction column to tasks
ALTER TABLE public.tasks ADD COLUMN direction text DEFAULT null;
