-- Create enum for kanban boards
DO $$ BEGIN
  CREATE TYPE public.task_board AS ENUM ('motion', 'sites');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Add board column to tasks
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS board public.task_board NOT NULL DEFAULT 'motion';

-- Index for filtering by board
CREATE INDEX IF NOT EXISTS idx_tasks_board ON public.tasks(board);
