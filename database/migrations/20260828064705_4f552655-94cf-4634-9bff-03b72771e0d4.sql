CREATE TABLE public.boards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name_ru text NOT NULL,
  name_en text NOT NULL,
  icon text NOT NULL DEFAULT 'LayoutGrid',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.boards TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.boards TO authenticated;
GRANT ALL ON public.boards TO service_role;

ALTER TABLE public.boards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view boards"
  ON public.boards FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can insert boards"
  ON public.boards FOR INSERT TO authenticated
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins can update boards"
  ON public.boards FOR UPDATE TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins can delete boards"
  ON public.boards FOR DELETE TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

CREATE TRIGGER update_boards_updated_at
  BEFORE UPDATE ON public.boards
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.boards (slug, name_ru, name_en, icon, sort_order) VALUES
  ('motion', 'Моушен', 'Motion', 'Clapperboard', 1),
  ('sites', 'Сайты', 'Sites', 'Globe2', 2),
  ('cs2', 'CS2 Bot', 'CS2 Bot', 'Bot', 3);

ALTER TABLE public.tasks ALTER COLUMN board DROP DEFAULT;
ALTER TABLE public.tasks ALTER COLUMN board TYPE text USING board::text;
ALTER TABLE public.tasks ALTER COLUMN board SET DEFAULT 'motion';

DROP TYPE IF EXISTS public.task_board;
