ALTER TABLE public.guides ADD COLUMN IF NOT EXISTS section text NOT NULL DEFAULT 'guide';
CREATE INDEX IF NOT EXISTS idx_guides_section_updated_at ON public.guides (section, updated_at DESC);
