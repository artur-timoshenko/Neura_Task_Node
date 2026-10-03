
CREATE TABLE public.guides (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title text NOT NULL,
  summary text,
  content text NOT NULL DEFAULT '',
  category text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.guides TO authenticated;
GRANT ALL ON public.guides TO service_role;
ALTER TABLE public.guides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read guides" ON public.guides
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins and teamleads can insert guides" ON public.guides
  FOR INSERT TO authenticated
  WITH CHECK (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role));
CREATE POLICY "Admins and teamleads can update guides" ON public.guides
  FOR UPDATE TO authenticated
  USING (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role))
  WITH CHECK (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role));
CREATE POLICY "Admins and teamleads can delete guides" ON public.guides
  FOR DELETE TO authenticated
  USING (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role));

CREATE TRIGGER update_guides_updated_at BEFORE UPDATE ON public.guides
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.guide_files (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  guide_id uuid NOT NULL REFERENCES public.guides(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_size bigint,
  mime_type text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.guide_files TO authenticated;
GRANT ALL ON public.guide_files TO service_role;
ALTER TABLE public.guide_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read guide files" ON public.guide_files
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins and teamleads can insert guide files" ON public.guide_files
  FOR INSERT TO authenticated
  WITH CHECK (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role));
CREATE POLICY "Admins and teamleads can delete guide files" ON public.guide_files
  FOR DELETE TO authenticated
  USING (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role));

CREATE INDEX idx_guide_files_guide ON public.guide_files(guide_id);
CREATE INDEX idx_guides_updated ON public.guides(updated_at DESC);

CREATE POLICY "Authenticated can read guide bucket" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'guide-files');
CREATE POLICY "Leads can upload guide files" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'guide-files' AND (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role)));
CREATE POLICY "Leads can delete guide files" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'guide-files' AND (private.has_role(auth.uid(),'admin'::app_role) OR private.has_role(auth.uid(),'teamlead'::app_role)));
