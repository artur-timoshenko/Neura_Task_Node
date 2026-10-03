DROP INDEX IF EXISTS public.tasks_task_code_unique_idx;

CREATE UNIQUE INDEX IF NOT EXISTS tasks_board_task_code_unique_idx
ON public.tasks (board, (NULLIF(btrim(task_code), '')))
WHERE NULLIF(btrim(task_code), '') IS NOT NULL;
