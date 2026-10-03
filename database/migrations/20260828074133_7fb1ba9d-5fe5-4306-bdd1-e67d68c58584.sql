-- Helper: list of a teamlead's members, evaluated once per query
CREATE OR REPLACE FUNCTION private.team_member_ids(_teamlead_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT member_id FROM public.team_memberships WHERE teamlead_id = _teamlead_id
$$;

REVOKE ALL ON FUNCTION private.team_member_ids(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.team_member_ids(uuid) TO authenticated;

-- ============ tasks ============
DROP POLICY IF EXISTS "Admins can create tasks" ON public.tasks;
DROP POLICY IF EXISTS "Admins can delete tasks" ON public.tasks;
DROP POLICY IF EXISTS "Admins can update all tasks" ON public.tasks;
DROP POLICY IF EXISTS "Admins can view all tasks" ON public.tasks;
DROP POLICY IF EXISTS "Teamleads can create tasks for members" ON public.tasks;
DROP POLICY IF EXISTS "Teamleads can delete member tasks" ON public.tasks;
DROP POLICY IF EXISTS "Teamleads can update member tasks" ON public.tasks;
DROP POLICY IF EXISTS "Teamleads can view member tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can update own tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can view own tasks" ON public.tasks;

CREATE POLICY "Admins can create tasks" ON public.tasks FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can delete tasks" ON public.tasks FOR DELETE TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can update all tasks" ON public.tasks FOR UPDATE TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can view all tasks" ON public.tasks FOR SELECT TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Teamleads can create tasks for members" ON public.tasks FOR INSERT TO authenticated
  WITH CHECK (user_id IN (SELECT private.team_member_ids((SELECT auth.uid()))));
CREATE POLICY "Teamleads can delete member tasks" ON public.tasks FOR DELETE TO authenticated
  USING (user_id IN (SELECT private.team_member_ids((SELECT auth.uid()))));
CREATE POLICY "Teamleads can update member tasks" ON public.tasks FOR UPDATE TO authenticated
  USING (user_id IN (SELECT private.team_member_ids((SELECT auth.uid()))));
CREATE POLICY "Teamleads can view member tasks" ON public.tasks FOR SELECT TO authenticated
  USING (user_id IN (SELECT private.team_member_ids((SELECT auth.uid()))));
CREATE POLICY "Users can update own tasks" ON public.tasks FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can view own tasks" ON public.tasks FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- ============ profiles ============
DROP POLICY IF EXISTS "Admins can insert profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Related users can view buyer profiles" ON public.profiles;
DROP POLICY IF EXISTS "Teamleads can view member profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can see commenter profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;

CREATE POLICY "Admins can insert profiles" ON public.profiles FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can update all profiles" ON public.profiles FOR UPDATE TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Related users can view buyer profiles" ON public.profiles FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = profiles.id AND ur.role = 'buyer'::app_role)
    AND private.has_buyer_relationship((SELECT auth.uid()), id)
  );
CREATE POLICY "Teamleads can view member profiles" ON public.profiles FOR SELECT TO authenticated
  USING (id IN (SELECT private.team_member_ids((SELECT auth.uid()))));
CREATE POLICY "Users can see commenter profiles" ON public.profiles FOR SELECT TO authenticated
  USING (id IN (
    SELECT tc.user_id FROM public.task_comments tc
    JOIN public.tasks t ON t.id = tc.task_id
    WHERE t.user_id = (SELECT auth.uid())
  ));
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = id);
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = id);

-- ============ user_roles ============
DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can manage roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles;
DROP POLICY IF EXISTS "Related users can view buyer roles" ON public.user_roles;
DROP POLICY IF EXISTS "Teamleads can view member roles" ON public.user_roles;
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;

CREATE POLICY "Admins can delete roles" ON public.user_roles FOR DELETE TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can manage roles" ON public.user_roles FOR INSERT TO authenticated
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can update roles" ON public.user_roles FOR UPDATE TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Admins can view all roles" ON public.user_roles FOR SELECT TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Related users can view buyer roles" ON public.user_roles FOR SELECT TO authenticated
  USING (role = 'buyer'::app_role AND private.has_buyer_relationship((SELECT auth.uid()), user_id));
CREATE POLICY "Teamleads can view member roles" ON public.user_roles FOR SELECT TO authenticated
  USING (user_id IN (SELECT private.team_member_ids((SELECT auth.uid()))));
CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- ============ task_attachments ============
DROP POLICY IF EXISTS "Admins full access to attachments" ON public.task_attachments;
DROP POLICY IF EXISTS "Teamleads delete attachments on member tasks" ON public.task_attachments;
DROP POLICY IF EXISTS "Teamleads insert attachments on member tasks" ON public.task_attachments;
DROP POLICY IF EXISTS "Teamleads view attachments on member tasks" ON public.task_attachments;
DROP POLICY IF EXISTS "Users can delete own attachments" ON public.task_attachments;
DROP POLICY IF EXISTS "Users can insert attachments on own tasks" ON public.task_attachments;
DROP POLICY IF EXISTS "Users can view attachments on own tasks" ON public.task_attachments;

CREATE POLICY "Admins full access to attachments" ON public.task_attachments FOR ALL TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Teamleads delete attachments on member tasks" ON public.task_attachments FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_attachments.task_id
    AND t.user_id IN (SELECT private.team_member_ids((SELECT auth.uid())))));
CREATE POLICY "Teamleads insert attachments on member tasks" ON public.task_attachments FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_attachments.task_id
    AND t.user_id IN (SELECT private.team_member_ids((SELECT auth.uid())))));
CREATE POLICY "Teamleads view attachments on member tasks" ON public.task_attachments FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_attachments.task_id
    AND t.user_id IN (SELECT private.team_member_ids((SELECT auth.uid())))));
CREATE POLICY "Users can delete own attachments" ON public.task_attachments FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can insert attachments on own tasks" ON public.task_attachments FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_attachments.task_id AND tasks.user_id = (SELECT auth.uid()))
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))));
CREATE POLICY "Users can view attachments on own tasks" ON public.task_attachments FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_attachments.task_id AND tasks.user_id = (SELECT auth.uid()))
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

-- ============ task_comments ============
DROP POLICY IF EXISTS "Admins full access to comments" ON public.task_comments;
DROP POLICY IF EXISTS "Teamleads delete comments on member tasks" ON public.task_comments;
DROP POLICY IF EXISTS "Teamleads insert comments on member tasks" ON public.task_comments;
DROP POLICY IF EXISTS "Teamleads view comments on member tasks" ON public.task_comments;
DROP POLICY IF EXISTS "Users can delete own comments" ON public.task_comments;
DROP POLICY IF EXISTS "Users can insert comments on own tasks" ON public.task_comments;
DROP POLICY IF EXISTS "Users can view comments on own tasks" ON public.task_comments;

CREATE POLICY "Admins full access to comments" ON public.task_comments FOR ALL TO authenticated
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
CREATE POLICY "Teamleads delete comments on member tasks" ON public.task_comments FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_comments.task_id
    AND t.user_id IN (SELECT private.team_member_ids((SELECT auth.uid())))));
CREATE POLICY "Teamleads insert comments on member tasks" ON public.task_comments FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_comments.task_id
    AND t.user_id IN (SELECT private.team_member_ids((SELECT auth.uid())))));
CREATE POLICY "Teamleads view comments on member tasks" ON public.task_comments FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_comments.task_id
    AND t.user_id IN (SELECT private.team_member_ids((SELECT auth.uid())))));
CREATE POLICY "Users can delete own comments" ON public.task_comments FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can insert comments on own tasks" ON public.task_comments FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_comments.task_id AND tasks.user_id = (SELECT auth.uid()))
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))));
CREATE POLICY "Users can view comments on own tasks" ON public.task_comments FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_comments.task_id AND tasks.user_id = (SELECT auth.uid()))
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

-- ============ task_chat_messages ============
DROP POLICY IF EXISTS "chat_insert_participants" ON public.task_chat_messages;
DROP POLICY IF EXISTS "chat_select_participants" ON public.task_chat_messages;

CREATE POLICY "chat_select_participants" ON public.task_chat_messages FOR SELECT TO authenticated
  USING (
    (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))
    OR (SELECT private.has_role((SELECT auth.uid()), 'teamlead'::app_role))
    OR EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_chat_messages.task_id
      AND (t.user_id = (SELECT auth.uid()) OR t.buyer_id = (SELECT auth.uid()))));
CREATE POLICY "chat_insert_participants" ON public.task_chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = (SELECT auth.uid()) AND (
      (as_buyer = true AND (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
      OR (as_buyer = false AND (
        (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))
        OR EXISTS (SELECT 1 FROM public.tasks t WHERE t.id = task_chat_messages.task_id
          AND (t.user_id = (SELECT auth.uid()) OR t.buyer_id = (SELECT auth.uid())))))));

-- ============ buyer_chat_messages ============
DROP POLICY IF EXISTS "buyer_chat_delete" ON public.buyer_chat_messages;
DROP POLICY IF EXISTS "buyer_chat_insert" ON public.buyer_chat_messages;
DROP POLICY IF EXISTS "buyer_chat_select" ON public.buyer_chat_messages;

CREATE POLICY "buyer_chat_select" ON public.buyer_chat_messages FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = designer_id OR (SELECT auth.uid()) = buyer_id
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))
    OR (SELECT private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));
CREATE POLICY "buyer_chat_insert" ON public.buyer_chat_messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = (SELECT auth.uid()) AND (
    (as_buyer = false AND ((SELECT auth.uid()) = designer_id OR (SELECT auth.uid()) = buyer_id))
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))
    OR (SELECT private.has_role((SELECT auth.uid()), 'teamlead'::app_role))));
CREATE POLICY "buyer_chat_delete" ON public.buyer_chat_messages FOR DELETE TO authenticated
  USING (sender_id = (SELECT auth.uid())
    OR (SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role))
    OR (SELECT private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));
