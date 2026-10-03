-- 1) Revoke direct execution of internal email-queue SECURITY DEFINER functions

-- 2) Restrict buyer role enumeration to users with an actual relationship
CREATE OR REPLACE FUNCTION private.has_buyer_relationship(_viewer uuid, _buyer uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT _viewer IS NOT NULL AND (
    _viewer = _buyer
    OR private.has_role(_viewer, 'admin'::public.app_role)
    OR private.is_teamlead(_viewer)
    OR EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.buyer_id = _buyer
        AND (t.user_id = _viewer OR t.created_by = _viewer)
    )
    OR EXISTS (
      SELECT 1 FROM public.buyer_chat_messages m
      WHERE m.buyer_id = _buyer
        AND (m.designer_id = _viewer OR m.sender_id = _viewer)
    )
  );
$$;

REVOKE ALL ON FUNCTION private.has_buyer_relationship(uuid, uuid) FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "Authenticated can view buyer roles" ON public.user_roles;
CREATE POLICY "Related users can view buyer roles"
ON public.user_roles
FOR SELECT
TO authenticated
USING (
  role = 'buyer'::public.app_role
  AND private.has_buyer_relationship(auth.uid(), user_id)
);
