-- 1. Team membership table (teamlead -> subordinate user)
CREATE TABLE IF NOT EXISTS public.team_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teamlead_id uuid NOT NULL,
  member_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (teamlead_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_team_memberships_teamlead ON public.team_memberships(teamlead_id);
CREATE INDEX IF NOT EXISTS idx_team_memberships_member ON public.team_memberships(member_id);

ALTER TABLE public.team_memberships ENABLE ROW LEVEL SECURITY;

-- 2. Helper: is current user a teamlead of given member?
CREATE OR REPLACE FUNCTION public.is_teamlead_of(_teamlead_id uuid, _member_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.team_memberships
    WHERE teamlead_id = _teamlead_id AND member_id = _member_id
  )
$$;

-- 3. Helper: is the user a teamlead at all (has the role)?
-- (already covered by has_role, but explicit shortcut)
CREATE OR REPLACE FUNCTION public.is_teamlead(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = 'teamlead'
  )
$$;

-- 4. RLS for team_memberships
CREATE POLICY "Admins manage memberships"
ON public.team_memberships
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Teamlead can view own memberships"
ON public.team_memberships
FOR SELECT
TO authenticated
USING (teamlead_id = auth.uid());

CREATE POLICY "Member can view own membership"
ON public.team_memberships
FOR SELECT
TO authenticated
USING (member_id = auth.uid());

-- 5. RLS for tasks: teamleads can view & manage tasks of their members
CREATE POLICY "Teamleads can view member tasks"
ON public.tasks
FOR SELECT
TO authenticated
USING (public.is_teamlead_of(auth.uid(), user_id));

CREATE POLICY "Teamleads can update member tasks"
ON public.tasks
FOR UPDATE
TO authenticated
USING (public.is_teamlead_of(auth.uid(), user_id));

CREATE POLICY "Teamleads can create tasks for members"
ON public.tasks
FOR INSERT
TO authenticated
WITH CHECK (public.is_teamlead_of(auth.uid(), user_id));

CREATE POLICY "Teamleads can delete member tasks"
ON public.tasks
FOR DELETE
TO authenticated
USING (public.is_teamlead_of(auth.uid(), user_id));

-- 6. Profiles: teamlead can view own members' profiles
CREATE POLICY "Teamleads can view member profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (public.is_teamlead_of(auth.uid(), id));

-- 7. user_roles: teamlead can view own members' roles (so UI knows)
CREATE POLICY "Teamleads can view member roles"
ON public.user_roles
FOR SELECT
TO authenticated
USING (public.is_teamlead_of(auth.uid(), user_id));

-- 8. task_comments: teamlead full access for member tasks
CREATE POLICY "Teamleads view comments on member tasks"
ON public.task_comments
FOR SELECT
TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.tasks t
  WHERE t.id = task_comments.task_id
    AND public.is_teamlead_of(auth.uid(), t.user_id)
));

CREATE POLICY "Teamleads insert comments on member tasks"
ON public.task_comments
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_comments.task_id
      AND public.is_teamlead_of(auth.uid(), t.user_id)
  )
);

CREATE POLICY "Teamleads delete comments on member tasks"
ON public.task_comments
FOR DELETE
TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.tasks t
  WHERE t.id = task_comments.task_id
    AND public.is_teamlead_of(auth.uid(), t.user_id)
));

-- 9. task_attachments: teamlead full access for member tasks
CREATE POLICY "Teamleads view attachments on member tasks"
ON public.task_attachments
FOR SELECT
TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.tasks t
  WHERE t.id = task_attachments.task_id
    AND public.is_teamlead_of(auth.uid(), t.user_id)
));

CREATE POLICY "Teamleads insert attachments on member tasks"
ON public.task_attachments
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_attachments.task_id
      AND public.is_teamlead_of(auth.uid(), t.user_id)
  )
);

CREATE POLICY "Teamleads delete attachments on member tasks"
ON public.task_attachments
FOR DELETE
TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.tasks t
  WHERE t.id = task_attachments.task_id
    AND public.is_teamlead_of(auth.uid(), t.user_id)
));
