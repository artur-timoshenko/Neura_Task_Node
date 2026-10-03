DROP POLICY IF EXISTS "Authenticated can view buyer profiles" ON public.profiles;

CREATE POLICY "Related users can view buyer profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = profiles.id AND ur.role = 'buyer'::public.app_role
  )
  AND private.has_buyer_relationship(auth.uid(), profiles.id)
);
