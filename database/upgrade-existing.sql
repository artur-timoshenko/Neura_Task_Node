BEGIN;

-- Hidden buyer metadata. It is never exposed to buyers; the API permits
-- admins to edit it and teamleads to read it.
ALTER TABLE IF EXISTS public.buyer_real_names
  ADD COLUMN IF NOT EXISTS team text;
DO $$
BEGIN
  IF to_regclass('public.buyer_real_names') IS NOT NULL AND NOT EXISTS (
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

-- Projects used to exist only in localStorage. No existing project data is deleted.
CREATE TABLE IF NOT EXISTS public.hub_projects (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  teamlead_id uuid REFERENCES auth.users(id),
  member_ids uuid[] NOT NULL DEFAULT '{}',
  document jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS hub_projects_owner_idx ON public.hub_projects(owner_id);
CREATE INDEX IF NOT EXISTS hub_projects_members_idx ON public.hub_projects USING gin(member_ids);
ALTER TABLE public.hub_projects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.hub_projects FROM anon, authenticated;
GRANT ALL ON public.hub_projects TO service_role;

-- Defense in depth for direct Data API/Realtime access with an older public key.
CREATE OR REPLACE FUNCTION private.hub_user_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (
  SELECT 1 FROM public.profiles WHERE id = auth.uid() AND banned IS NOT TRUE
) $$;
REVOKE ALL ON FUNCTION private.hub_user_enabled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.hub_user_enabled() TO authenticated;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['profiles','user_roles','tasks','task_comments','task_attachments',
    'task_chat_messages','buyer_chat_messages','boards','guides','guide_files','site_settings',
    'telegram_group_chats','team_memberships','buyer_real_names','action_logs','user_last_visits']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP POLICY IF EXISTS hub_active_user ON public.%I', t);
      EXECUTE format('CREATE POLICY hub_active_user ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT private.hub_user_enabled())) WITH CHECK ((SELECT private.hub_user_enabled()))', t);
    END IF;
  END LOOP;
END $$;
DROP POLICY IF EXISTS hub_active_user ON storage.objects;
CREATE POLICY hub_active_user ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
USING ((SELECT private.hub_user_enabled())) WITH CHECK ((SELECT private.hub_user_enabled()));

-- Self-service profile RLS formerly allowed changing sensitive columns as well.
CREATE OR REPLACE FUNCTION private.hub_protect_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() = 'authenticated' AND NOT private.has_role(auth.uid(), 'admin'::public.app_role) THEN
    IF (to_jsonb(NEW) - ARRAY['name','avatar_url','updated_at']) IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['name','avatar_url','updated_at']) THEN
      RAISE EXCEPTION 'Protected profile fields' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS hub_protect_profile ON public.profiles;
CREATE TRIGGER hub_protect_profile BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.hub_protect_profile();

-- Maintenance/email queue functions are not browser-callable APIs.
DO $$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(ARRAY[
      'cleanup_old_tasks','cleanup_old_chat_images','cleanup_expired_submissions',
      'enqueue_email','read_email_batch','delete_email','move_to_dlq'])
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.signature);
  END LOOP;
END $$;
COMMIT;

-- Infrastructure created outside source migrations in the former deployment.
INSERT INTO storage.buckets (id, name, public) VALUES
  ('guide-files', 'guide-files', false),
  ('task-files', 'task-files', false),
  ('avatars', 'avatars', true),
  ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;
UPDATE storage.buckets SET public = false WHERE id IN ('task-files', 'guide-files');

-- Use the latest helper, which includes task chats, buyer chats and team members.
-- Keeping the helper in a non-exposed schema avoids granting a browser RPC.
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.can_access_task_file(text) TO authenticated, service_role;
ALTER POLICY "Authorized users can view task files" ON storage.objects
  USING (bucket_id = 'task-files' AND private.can_access_task_file(name));
ALTER POLICY "Authorized users can upload task files" ON storage.objects
  WITH CHECK (bucket_id = 'task-files' AND private.can_access_task_file(name));
ALTER POLICY "Authorized users can update task files" ON storage.objects
  USING (bucket_id = 'task-files' AND private.can_access_task_file(name))
  WITH CHECK (bucket_id = 'task-files' AND private.can_access_task_file(name));
ALTER POLICY "Authorized users can delete task files" ON storage.objects
  USING (bucket_id = 'task-files' AND private.can_access_task_file(name));
