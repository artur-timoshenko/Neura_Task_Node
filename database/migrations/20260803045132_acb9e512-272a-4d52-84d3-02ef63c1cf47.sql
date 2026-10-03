CREATE TABLE public.buyer_real_names (
  buyer_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  real_name text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.buyer_real_names TO authenticated;
GRANT ALL ON public.buyer_real_names TO service_role;

ALTER TABLE public.buyer_real_names ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins and teamleads manage buyer real names"
ON public.buyer_real_names FOR ALL TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role) OR private.has_role(auth.uid(), 'teamlead'::public.app_role))
WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role) OR private.has_role(auth.uid(), 'teamlead'::public.app_role));

CREATE TRIGGER update_buyer_real_names_updated_at
BEFORE UPDATE ON public.buyer_real_names
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
