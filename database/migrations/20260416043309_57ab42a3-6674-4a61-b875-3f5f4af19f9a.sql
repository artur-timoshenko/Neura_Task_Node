UPDATE public.tasks
SET task_code = NULL
WHERE task_code IS NOT NULL
  AND btrim(task_code) = '';

UPDATE public.tasks
SET task_code = btrim(task_code)
WHERE task_code IS NOT NULL
  AND task_code <> btrim(task_code);

WITH ranked AS (
  SELECT
    id,
    NULLIF(btrim(task_code), '') AS normalized_code,
    ROW_NUMBER() OVER (
      PARTITION BY NULLIF(btrim(task_code), '')
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM public.tasks
  WHERE NULLIF(btrim(task_code), '') IS NOT NULL
)
UPDATE public.tasks AS t
SET task_code = ranked.normalized_code || '-dup-' || LEFT(t.id::text, 8)
FROM ranked
WHERE t.id = ranked.id
  AND ranked.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS tasks_task_code_unique_idx
ON public.tasks ((NULLIF(btrim(task_code), '')))
WHERE NULLIF(btrim(task_code), '') IS NOT NULL;
