
ALTER TABLE public.task_attachments
ADD COLUMN category text NOT NULL DEFAULT 'attachment';
