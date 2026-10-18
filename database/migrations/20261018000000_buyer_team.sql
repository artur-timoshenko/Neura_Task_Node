BEGIN;

ALTER TABLE public.buyer_real_names
  ADD COLUMN IF NOT EXISTS team text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'buyer_real_names_team_length'
  ) THEN
    ALTER TABLE public.buyer_real_names
      ADD CONSTRAINT buyer_real_names_team_length CHECK (team IS NULL OR char_length(team) <= 100);
  END IF;
END $$;

DROP POLICY IF EXISTS "Admins and teamleads manage buyer real names" ON public.buyer_real_names;
DROP POLICY IF EXISTS "Admins and teamleads can read buyer real names" ON public.buyer_real_names;
DROP POLICY IF EXISTS "Admins can manage buyer real names" ON public.buyer_real_names;

CREATE POLICY "Admins and teamleads can read buyer real names"
ON public.buyer_real_names FOR SELECT TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role) OR private.has_role(auth.uid(), 'teamlead'::public.app_role));

CREATE POLICY "Admins can manage buyer real names"
ON public.buyer_real_names FOR ALL TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

COMMIT;
