-- FRESH EMPTY SUPABASE PROJECT ONLY. Existing databases: use upgrade-existing.sql.
-- Each migration commits separately so PostgreSQL enum additions can be used safely.
DO $$ BEGIN
  IF to_regclass('public.profiles') IS NOT NULL THEN
    RAISE EXCEPTION 'Database already initialized. Use upgrade-existing.sql instead.';
  END IF;
END $$;

-- 20260331065333_d23ae004-c80a-4c52-88a2-3887b966d7bc.sql
BEGIN;
-- Create app_role enum
CREATE TYPE public.app_role AS ENUM ('admin', 'user');

-- Create task_status enum
CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'review', 'done');

-- Create profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT '',
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Create user_roles table
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'user',
  UNIQUE (user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Create tasks table
CREATE TABLE public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  status task_status NOT NULL DEFAULT 'todo',
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Create indexes
CREATE INDEX idx_tasks_user_id ON public.tasks(user_id);
CREATE INDEX idx_tasks_status ON public.tasks(status);
CREATE INDEX idx_user_roles_user_id ON public.user_roles(user_id);

-- Security definer function to check roles (prevents RLS recursion)
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'name', ''), NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- RLS Policies for profiles
CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles"
  ON public.profiles FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Admins can update all profiles"
  ON public.profiles FOR UPDATE
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can insert profiles"
  ON public.profiles FOR INSERT
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- RLS Policies for user_roles
CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles"
  ON public.user_roles FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can manage roles"
  ON public.user_roles FOR INSERT
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update roles"
  ON public.user_roles FOR UPDATE
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete roles"
  ON public.user_roles FOR DELETE
  USING (public.has_role(auth.uid(), 'admin'));

-- RLS Policies for tasks (CRITICAL: strict isolation)
CREATE POLICY "Users can view own tasks"
  ON public.tasks FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all tasks"
  ON public.tasks FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users can update own tasks"
  ON public.tasks FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can update all tasks"
  ON public.tasks FOR UPDATE
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can create tasks"
  ON public.tasks FOR INSERT
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete tasks"
  ON public.tasks FOR DELETE
  USING (public.has_role(auth.uid(), 'admin'));
COMMIT;

-- 20260331070459_eaad4f0e-7326-41ce-aeba-1608bd242e58.sql
BEGIN;
ALTER TABLE public.user_roles DROP CONSTRAINT IF EXISTS user_roles_user_id_role_key;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_user_id_key UNIQUE (user_id);
COMMIT;

-- 20260331071143_1819bf4c-ed42-40b1-a6f6-116a66e15a10.sql
BEGIN;
-- Add priority enum
CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');

-- Add priority column to tasks
ALTER TABLE public.tasks ADD COLUMN priority task_priority NOT NULL DEFAULT 'medium';

-- Create task_comments table
CREATE TABLE public.task_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;

-- Comments: users can view comments on their own tasks
CREATE POLICY "Users can view comments on own tasks" ON public.task_comments
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_comments.task_id AND tasks.user_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

-- Comments: users can insert comments on their own tasks
CREATE POLICY "Users can insert comments on own tasks" ON public.task_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id AND (
      EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_comments.task_id AND tasks.user_id = auth.uid())
      OR public.has_role(auth.uid(), 'admin')
    )
  );

-- Comments: admins full access
CREATE POLICY "Admins full access to comments" ON public.task_comments
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Create task_attachments table  
CREATE TABLE public.task_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_size bigint,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view attachments on own tasks" ON public.task_attachments
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_attachments.task_id AND tasks.user_id = auth.uid())
    OR public.has_role(auth.uid(), 'admin')
  );

CREATE POLICY "Users can insert attachments on own tasks" ON public.task_attachments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id AND (
      EXISTS (SELECT 1 FROM public.tasks WHERE tasks.id = task_attachments.task_id AND tasks.user_id = auth.uid())
      OR public.has_role(auth.uid(), 'admin')
    )
  );

CREATE POLICY "Admins full access to attachments" ON public.task_attachments
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Storage bucket for task files
INSERT INTO storage.buckets (id, name, public) VALUES ('task-files', 'task-files', true);

-- Storage policies
CREATE POLICY "Authenticated users can upload task files" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'task-files');

CREATE POLICY "Anyone can view task files" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'task-files');

-- Enable realtime for comments
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_comments;
COMMIT;

-- 20260331071846_2e4a0acc-45ed-4ccd-9f75-bee960339122.sql
BEGIN;
-- Add direction column to tasks
ALTER TABLE public.tasks ADD COLUMN direction text DEFAULT null;
COMMIT;

-- 20260331072141_19009163-bb45-4628-b824-b3272f6b8ff5.sql
BEGIN;
-- Allow users to see profiles of people who commented on tasks assigned to them
CREATE POLICY "Users can see commenter profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT tc.user_id FROM public.task_comments tc
      JOIN public.tasks t ON t.id = tc.task_id
      WHERE t.user_id = auth.uid()
    )
  );
COMMIT;

-- 20260331072717_b3b70a91-24db-45e6-8c18-eadcad8d64bd.sql
BEGIN;
-- Add avatar_url and banned columns to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS banned boolean NOT NULL DEFAULT false;

-- Create avatars storage bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for avatars
CREATE POLICY "Users can upload own avatar" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can update own avatar" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Anyone can view avatars" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'avatars');
COMMIT;

-- 20260331073647_eda4a55e-f1a3-4a0b-abe6-4ba72ea8df26.sql
BEGIN;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS task_code text;
COMMIT;

-- 20260331075817_fd4783ca-c0d9-4344-9f07-d25f50ed7d1a.sql
BEGIN;
-- Site settings table for storing company logo and other settings
CREATE TABLE public.site_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;

-- Everyone can read settings
CREATE POLICY "Anyone can read site_settings"
  ON public.site_settings FOR SELECT
  TO authenticated
  USING (true);

-- Only admins can update settings
CREATE POLICY "Admins can insert site_settings"
  ON public.site_settings FOR INSERT
  TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update site_settings"
  ON public.site_settings FOR UPDATE
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- Insert default logo setting
INSERT INTO public.site_settings (key, value) VALUES ('company_logo', null);

-- Create storage bucket for company logo
INSERT INTO storage.buckets (id, name, public) VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for company-assets
CREATE POLICY "Anyone can view company assets"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'company-assets');

CREATE POLICY "Admins can upload company assets"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'company-assets' AND public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update company assets"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'company-assets' AND public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete company assets"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'company-assets' AND public.has_role(auth.uid(), 'admin'));
COMMIT;

-- 20260331080139_1510fa7e-98ec-4663-98fa-25b8542454f0.sql
BEGIN;
-- Allow unauthenticated users to read site_settings (for logo on auth page)
DROP POLICY "Anyone can read site_settings" ON public.site_settings;
CREATE POLICY "Anyone can read site_settings"
  ON public.site_settings FOR SELECT
  TO anon, authenticated
  USING (true);
COMMIT;

-- 20260403095645_b6d92867-cbfa-4ee8-a532-7db202aeadbd.sql
BEGIN;
ALTER TYPE public.task_status ADD VALUE 'corrections' BEFORE 'done';
COMMIT;

-- 20260403100410_aed7a103-77c2-4ddd-8c4b-3737fa21c63c.sql
BEGIN;
ALTER TABLE public.tasks ADD COLUMN in_progress_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE public.tasks ADD COLUMN completed_at TIMESTAMPTZ DEFAULT NULL;
COMMIT;

-- 20260403104009_f189eb11-8371-4d4b-950e-30e6fc376246.sql
BEGIN;
ALTER TABLE public.tasks ADD COLUMN complexity smallint DEFAULT NULL;
COMMIT;

-- 20260403115422_80ed0ac7-6540-4a52-8e90-65f0065671a7.sql
BEGIN;
CREATE TABLE public.telegram_bot_state (
  id int PRIMARY KEY CHECK (id = 1),
  update_offset bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.telegram_bot_state (id, update_offset) VALUES (1, 0);

ALTER TABLE public.telegram_bot_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage bot state"
  ON public.telegram_bot_state
  FOR ALL
  TO public
  USING (auth.role() = 'service_role'::text)
  WITH CHECK (auth.role() = 'service_role'::text);
COMMIT;

-- 20260407142024_c8b8856b-1ae9-4110-86bc-055c22f82a4f.sql
BEGIN;
CREATE POLICY "Users can delete own comments"
ON public.task_comments
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
COMMIT;

-- 20260408045914_f32bcb59-e917-4d30-a8d6-a40718599f28.sql
BEGIN;
ALTER TABLE public.tasks ALTER COLUMN complexity TYPE numeric USING complexity::numeric;
COMMIT;

-- 20260414094911_fd27c9d1-b274-4f6d-90e0-2a1f099d3339.sql
BEGIN;
ALTER TABLE public.task_attachments
ADD COLUMN category text NOT NULL DEFAULT 'attachment';
COMMIT;

-- 20260414095814_e34d35d6-6eda-469f-a699-c9092b5b5705.sql
BEGIN;
-- Create cleanup function for expired submissions (older than 14 days)
CREATE OR REPLACE FUNCTION public.cleanup_expired_submissions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT id, file_path
    FROM public.task_attachments
    WHERE category = 'submission'
      AND created_at < now() - interval '14 days'
  LOOP
    -- Delete from storage via direct table delete (storage cleanup handled by Supabase)
    DELETE FROM storage.objects WHERE bucket_id = 'task-files' AND name = rec.file_path;
    -- Delete the attachment record
    DELETE FROM public.task_attachments WHERE id = rec.id;
  END LOOP;
END;
$$;

-- Schedule daily cleanup at 3 AM UTC
COMMIT;

-- 20260414121739_c8635243-70eb-47f9-af52-3ed37a293c8b.sql
BEGIN;
-- 1. Fix task-files SELECT policy: only task owner or admin
DROP POLICY IF EXISTS "Anyone can view task files" ON storage.objects;
CREATE POLICY "Task owners and admins can view task files"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'task-files'
  AND (
    has_role(auth.uid(), 'admin'::app_role)
    OR EXISTS (
      SELECT 1 FROM public.task_attachments ta
      JOIN public.tasks t ON t.id = ta.task_id
      WHERE ta.file_path = name
      AND t.user_id = auth.uid()
    )
  )
);

-- 2. Fix task-files INSERT policy: only task owner or admin
DROP POLICY IF EXISTS "Authenticated users can upload task files" ON storage.objects;
CREATE POLICY "Task owners and admins can upload task files"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'task-files'
  AND (
    has_role(auth.uid(), 'admin'::app_role)
    OR auth.uid() IS NOT NULL
  )
);

-- 3. Add DELETE policy for task-files (admins only)
CREATE POLICY "Admins can delete task files"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'task-files'
  AND has_role(auth.uid(), 'admin'::app_role)
);

-- 4. Add DELETE policy for avatars
CREATE POLICY "Users can delete own avatar"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 5. Fix site_settings: restrict to authenticated only
DROP POLICY IF EXISTS "Anyone can read site_settings" ON public.site_settings;
CREATE POLICY "Authenticated users can read site_settings"
ON public.site_settings FOR SELECT
TO authenticated
USING (true);
COMMIT;

-- 20260416043309_57ab42a3-6674-4a61-b875-3f5f4af19f9a.sql
BEGIN;
UPDATE public.tasks
SET task_code = NULL
WHERE task_code IS NOT NULL
  AND btrim(task_code) = '';

UPDATE public.tasks
SET task_code = btrim(task_code)
WHERE task_code IS NOT NULL
  AND task_code <> btrim(task_code);

WITH ranked AS (
  SELECT
    id,
    NULLIF(btrim(task_code), '') AS normalized_code,
    ROW_NUMBER() OVER (
      PARTITION BY NULLIF(btrim(task_code), '')
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM public.tasks
  WHERE NULLIF(btrim(task_code), '') IS NOT NULL
)
UPDATE public.tasks AS t
SET task_code = ranked.normalized_code || '-dup-' || LEFT(t.id::text, 8)
FROM ranked
WHERE t.id = ranked.id
  AND ranked.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS tasks_task_code_unique_idx
ON public.tasks ((NULLIF(btrim(task_code), '')))
WHERE NULLIF(btrim(task_code), '') IS NOT NULL;
COMMIT;

-- 20260420081012_30092c00-181f-425e-b324-23d9463f5ef4.sql
BEGIN;
ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS paused_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS paused_total_ms BIGINT NOT NULL DEFAULT 0;
COMMIT;

-- 20260421055751_5c7e2a87-fa5b-43ad-8649-bb0650f8d2e6.sql
BEGIN;
CREATE POLICY "Users can delete own attachments"
ON public.task_attachments
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
COMMIT;

-- 20260423072733_f1f151e9-bc16-41d2-8013-c9147a09da61.sql
BEGIN;
CREATE TABLE public.action_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  target_user_id uuid,
  task_id uuid,
  entity_type text NOT NULL,
  entity_id uuid,
  action text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.action_logs ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_action_logs_created_at ON public.action_logs (created_at DESC);
CREATE INDEX idx_action_logs_actor_id ON public.action_logs (actor_id);
CREATE INDEX idx_action_logs_target_user_id ON public.action_logs (target_user_id);
CREATE INDEX idx_action_logs_task_id ON public.action_logs (task_id);
CREATE INDEX idx_action_logs_entity_type_action ON public.action_logs (entity_type, action);

CREATE POLICY "Admins can view action logs"
ON public.action_logs
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can insert own action logs"
ON public.action_logs
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = actor_id);

CREATE OR REPLACE FUNCTION public.log_action(
  _action text,
  _entity_type text,
  _entity_id uuid DEFAULT NULL,
  _task_id uuid DEFAULT NULL,
  _target_user_id uuid DEFAULT NULL,
  _details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  new_id uuid;
BEGIN
  INSERT INTO public.action_logs (
    actor_id,
    target_user_id,
    task_id,
    entity_type,
    entity_id,
    action,
    details
  ) VALUES (
    auth.uid(),
    _target_user_id,
    _task_id,
    _entity_type,
    _entity_id,
    _action,
    COALESCE(_details, '{}'::jsonb)
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;
COMMIT;

-- 20260425144202_8c331ba1-a922-4c65-be85-05673d1583df.sql
BEGIN;
-- Create enum for kanban boards
DO $$ BEGIN
  CREATE TYPE public.task_board AS ENUM ('motion', 'sites');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Add board column to tasks
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS board public.task_board NOT NULL DEFAULT 'motion';

-- Index for filtering by board
CREATE INDEX IF NOT EXISTS idx_tasks_board ON public.tasks(board);
COMMIT;

-- 20260427062120_db7dda88-3d69-4d42-a69c-af2c8e644469.sql
BEGIN;
-- 1. Add 'teamlead' to app_role enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'teamlead';
COMMIT;

-- 20260427062201_8da06d28-2df8-4102-8607-862e70828aad.sql
BEGIN;
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
COMMIT;

-- 20260513085306_eab26041-1d2b-4d0e-bc0e-f25b62ce68d3.sql
BEGIN;
-- Composite & supporting indexes
CREATE INDEX IF NOT EXISTS idx_tasks_user_status_board ON public.tasks (user_id, status, board);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON public.tasks (updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON public.tasks (created_at);
CREATE INDEX IF NOT EXISTS idx_task_comments_task_id ON public.task_comments (task_id);
CREATE INDEX IF NOT EXISTS idx_task_attachments_task_id ON public.task_attachments (task_id);
CREATE INDEX IF NOT EXISTS idx_task_attachments_category_created ON public.task_attachments (category, created_at);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles (user_id);

-- Aggregated stats RPC: replaces 4 separate client queries with 1 server-side aggregation
CREATE OR REPLACE FUNCTION public.get_user_stats(_from timestamptz, _to timestamptz)
RETURNS TABLE (
  user_id uuid,
  user_name text,
  done_tasks bigint,
  total_tasks bigint,
  workload_hours numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH today_start AS (
    SELECT date_trunc('day', now()) AS d
  ),
  today_end AS (
    SELECT (SELECT d FROM today_start) + interval '19 hours' AS d
  )
  SELECT
    p.id AS user_id,
    COALESCE(p.name, '—') AS user_name,
    COALESCE(SUM(CASE WHEN t.status = 'done' AND t.updated_at >= _from AND t.updated_at <= _to THEN 1 ELSE 0 END), 0)::bigint AS done_tasks,
    COALESCE(COUNT(t.id), 0)::bigint AS total_tasks,
    COALESCE(SUM(
      CASE WHEN t.created_at >= (SELECT d FROM today_start)
            AND t.created_at <= (SELECT d FROM today_end)
        THEN COALESCE(t.complexity, 1)
        ELSE 0
      END
    ), 0)::numeric AS workload_hours
  FROM public.profiles p
  LEFT JOIN public.tasks t ON t.user_id = p.id
  WHERE has_role(auth.uid(), 'admin'::app_role)
  GROUP BY p.id, p.name
  ORDER BY done_tasks DESC;
$$;

-- Batched action log insert
CREATE OR REPLACE FUNCTION public.log_actions_batch(_events jsonb)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  inserted_count integer := 0;
BEGIN
  IF _events IS NULL OR jsonb_typeof(_events) <> 'array' THEN
    RETURN 0;
  END IF;

  INSERT INTO public.action_logs (
    actor_id, target_user_id, task_id, entity_type, entity_id, action, details, created_at
  )
  SELECT
    auth.uid(),
    NULLIF(e->>'target_user_id','')::uuid,
    NULLIF(e->>'task_id','')::uuid,
    e->>'entity_type',
    NULLIF(e->>'entity_id','')::uuid,
    e->>'action',
    COALESCE(e->'details', '{}'::jsonb),
    COALESCE(NULLIF(e->>'created_at','')::timestamptz, now())
  FROM jsonb_array_elements(_events) AS e
  WHERE e->>'action' IS NOT NULL AND e->>'entity_type' IS NOT NULL;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;
COMMIT;

-- 20260513143007_dc77a73e-26ef-4db3-8cd6-8788e7d62dbd.sql
BEGIN;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.task_comments REPLICA IDENTITY FULL;
COMMIT;

-- 20260620082020_7b270594-f5fe-4941-8dbd-2ca11de2a020.sql
BEGIN;
-- ============ Storage: task-files bucket ============

-- Drop old policies
DROP POLICY IF EXISTS "Task owners and admins can upload task files" ON storage.objects;
DROP POLICY IF EXISTS "Task owners and admins can view task files" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete task files" ON storage.objects;

-- Helper: check if current user can manage a given task-files path
-- Path is either '{task_id}/...' or 'description-images/{user_id}/...'
CREATE OR REPLACE FUNCTION public.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  first_segment text;
  task_owner uuid;
  task_uuid uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  -- description-images/{user_id}/...
  IF first_segment = 'description-images' THEN
    RETURN split_part(_path, '/', 2) = auth.uid()::text;
  END IF;

  -- {task_id}/...
  BEGIN
    task_uuid := first_segment::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  SELECT user_id INTO task_owner FROM public.tasks WHERE id = task_uuid;
  IF task_owner IS NULL THEN
    RETURN false;
  END IF;
  IF task_owner = auth.uid() THEN
    RETURN true;
  END IF;
  IF public.is_teamlead_of(auth.uid(), task_owner) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.can_access_task_file(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_task_file(text) TO authenticated, service_role;

CREATE POLICY "Authorized users can view task files"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'task-files' AND public.can_access_task_file(name));

CREATE POLICY "Authorized users can upload task files"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'task-files' AND public.can_access_task_file(name));

CREATE POLICY "Authorized users can update task files"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'task-files' AND public.can_access_task_file(name))
WITH CHECK (bucket_id = 'task-files' AND public.can_access_task_file(name));

CREATE POLICY "Authorized users can delete task files"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'task-files' AND public.can_access_task_file(name));

-- ============ Revoke public/anon execute on internal SECURITY DEFINER functions ============

-- Internal helpers (called only from RLS / app as authenticated): revoke anon
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_teamlead(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_teamlead(uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_teamlead_of(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_teamlead_of(uuid, uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_user_stats(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_stats(timestamptz, timestamptz) TO authenticated, service_role;

-- Service-only functions: revoke from anon and authenticated
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_submissions() FROM PUBLIC, anon, authenticated;

-- Postgres Changes permissions are enforced by RLS on the subscribed public tables.
-- Do not alter realtime.messages: managed Supabase projects do not grant ownership
-- of that internal table to the SQL Editor role.
COMMIT;

-- 20260620090000_private_helpers.sql
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT public.has_role(_user_id, _role) $$;
REVOKE ALL ON FUNCTION private.has_role(_user_id uuid, _role public.app_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.has_role(_user_id uuid, _role public.app_role) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION private.is_teamlead(_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT public.is_teamlead(_user_id) $$;
REVOKE ALL ON FUNCTION private.is_teamlead(_user_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_teamlead(_user_id uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION private.is_teamlead_of(_teamlead_id uuid, _member_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT public.is_teamlead_of(_teamlead_id, _member_id) $$;
REVOKE ALL ON FUNCTION private.is_teamlead_of(_teamlead_id uuid, _member_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_teamlead_of(_teamlead_id uuid, _member_id uuid) TO authenticated, service_role;
COMMIT;

-- 20260629085227_5b5a22e1-40a6-4dcd-bd9e-76a9298a4b5e.sql
BEGIN;
CREATE OR REPLACE FUNCTION private.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  first_segment text;
  task_owner uuid;
  task_uuid uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF private.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  IF first_segment = 'description-images' THEN
    RETURN split_part(_path, '/', 2) = auth.uid()::text;
  END IF;

  BEGIN
    task_uuid := first_segment::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  SELECT user_id INTO task_owner FROM public.tasks WHERE id = task_uuid;
  IF task_owner IS NULL THEN
    RETURN false;
  END IF;
  IF task_owner = auth.uid() THEN
    RETURN true;
  END IF;
  IF private.is_teamlead_of(auth.uid(), task_owner) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;
COMMIT;

-- 20260714193547_e3fb8f69-b1b2-4889-a01f-4013375b7718.sql
BEGIN;
-- 1) Add 'buyer' role
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'buyer';

-- 2) Add buyer_id on tasks
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS buyer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_buyer_id ON public.tasks(buyer_id);

-- 3) Chat between designer <-> buyer, admin can see and write as buyer
CREATE TABLE IF NOT EXISTS public.task_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  as_buyer boolean NOT NULL DEFAULT false,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_chat_messages_task_id ON public.task_chat_messages(task_id, created_at);

GRANT SELECT, INSERT ON public.task_chat_messages TO authenticated;
GRANT ALL ON public.task_chat_messages TO service_role;

ALTER TABLE public.task_chat_messages ENABLE ROW LEVEL SECURITY;

-- Read: admin/teamlead OR designer OR buyer of that task
CREATE POLICY "chat_select_participants" ON public.task_chat_messages
FOR SELECT TO authenticated
USING (
  private.has_role(auth.uid(), 'admin'::app_role)
  OR private.has_role(auth.uid(), 'teamlead'::app_role)
  OR EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_chat_messages.task_id
      AND (t.user_id = auth.uid() OR t.buyer_id = auth.uid())
  )
);

-- Insert: sender must be authed user; must be a participant.
-- as_buyer=true is only allowed for admins.
CREATE POLICY "chat_insert_participants" ON public.task_chat_messages
FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND (
    (as_buyer = true AND private.has_role(auth.uid(), 'admin'::app_role))
    OR (
      as_buyer = false
      AND (
        private.has_role(auth.uid(), 'admin'::app_role)
        OR EXISTS (
          SELECT 1 FROM public.tasks t
          WHERE t.id = task_chat_messages.task_id
            AND (t.user_id = auth.uid() OR t.buyer_id = auth.uid())
        )
      )
    )
  )
);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_chat_messages;
COMMIT;

-- 20260714194903_177ca854-ada8-47f0-b438-14d5f375577b.sql
BEGIN;
-- 1) Add tags to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}';

-- 2) Direct chat table (not task-bound)
CREATE TABLE IF NOT EXISTS public.buyer_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  designer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  as_buyer boolean NOT NULL DEFAULT false,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS buyer_chat_pair_idx ON public.buyer_chat_messages (designer_id, buyer_id, created_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.buyer_chat_messages TO authenticated;
GRANT ALL ON public.buyer_chat_messages TO service_role;

ALTER TABLE public.buyer_chat_messages ENABLE ROW LEVEL SECURITY;

-- SELECT: participants or admin/teamlead
CREATE POLICY "buyer_chat_select" ON public.buyer_chat_messages
FOR SELECT TO authenticated
USING (
  auth.uid() = designer_id
  OR auth.uid() = buyer_id
  OR private.has_role(auth.uid(), 'admin'::app_role)
  OR private.has_role(auth.uid(), 'teamlead'::app_role)
);

-- INSERT: sender must be auth.uid(); either a participant sending as themselves,
-- or admin/teamlead (may send as buyer via as_buyer=true).
CREATE POLICY "buyer_chat_insert" ON public.buyer_chat_messages
FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND (
    (as_buyer = false AND (auth.uid() = designer_id OR auth.uid() = buyer_id))
    OR private.has_role(auth.uid(), 'admin'::app_role)
    OR private.has_role(auth.uid(), 'teamlead'::app_role)
  )
);

-- DELETE: sender or admin/teamlead
CREATE POLICY "buyer_chat_delete" ON public.buyer_chat_messages
FOR DELETE TO authenticated
USING (
  sender_id = auth.uid()
  OR private.has_role(auth.uid(), 'admin'::app_role)
  OR private.has_role(auth.uid(), 'teamlead'::app_role)
);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.buyer_chat_messages;
ALTER TABLE public.buyer_chat_messages REPLICA IDENTITY FULL;
COMMIT;

-- 20260717070847_4aae9539-a699-40f3-8ef9-40adc0da7901.sql
BEGIN;
CREATE POLICY "Authenticated can view buyer roles" ON public.user_roles FOR SELECT TO authenticated USING (role = 'buyer'::app_role);
COMMIT;

-- 20260717071830_ea333a54-634a-456b-bcaf-d6a1fb86da51.sql
BEGIN;
CREATE POLICY "Authenticated can view buyer profiles" ON public.profiles FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = profiles.id AND ur.role = 'buyer'::app_role));
COMMIT;

-- 20260717073333_3190d1c2-624f-4b53-b8a5-788ac1a7669c.sql
BEGIN;
ALTER TABLE public.task_chat_messages ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.buyer_chat_messages ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.task_chat_messages ALTER COLUMN body DROP NOT NULL;
ALTER TABLE public.buyer_chat_messages ALTER COLUMN body DROP NOT NULL;
COMMIT;

-- 20260717120207_460bf3ca-43ef-4c06-868b-08108687a3e9.sql
BEGIN;
CREATE OR REPLACE FUNCTION public.get_user_stats(_from timestamptz, _to timestamptz)
RETURNS TABLE (
  user_id uuid,
  user_name text,
  done_tasks bigint,
  total_tasks bigint,
  workload_hours numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH today_start AS (SELECT date_trunc('day', now()) AS d),
  today_end AS (SELECT (SELECT d FROM today_start) + interval '19 hours' AS d)
  SELECT
    p.id AS user_id,
    COALESCE(p.name, '—') AS user_name,
    COALESCE(SUM(CASE WHEN t.status = 'done' AND t.updated_at >= _from AND t.updated_at <= _to THEN 1 ELSE 0 END), 0)::bigint AS done_tasks,
    COALESCE(COUNT(t.id), 0)::bigint AS total_tasks,
    COALESCE(SUM(
      CASE WHEN t.created_at >= (SELECT d FROM today_start)
            AND t.created_at <= (SELECT d FROM today_end)
        THEN COALESCE(t.complexity, 1)
        ELSE 0
      END
    ), 0)::numeric AS workload_hours
  FROM public.profiles p
  LEFT JOIN public.tasks t ON t.user_id = p.id
  WHERE private.has_role(auth.uid(), 'admin'::public.app_role)
    AND NOT EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = p.id AND ur.role = 'buyer'::public.app_role
    )
  GROUP BY p.id, p.name
  ORDER BY done_tasks DESC;
$$;
COMMIT;

-- 20260803045132_acb9e512-272a-4d52-84d3-02ef63c1cf47.sql
BEGIN;
CREATE TABLE public.buyer_real_names (
  buyer_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  real_name text NOT NULL DEFAULT '',
  team text CHECK (team IS NULL OR char_length(team) <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.buyer_real_names TO authenticated;
GRANT ALL ON public.buyer_real_names TO service_role;

ALTER TABLE public.buyer_real_names ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins and teamleads can read buyer real names"
ON public.buyer_real_names FOR SELECT TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role) OR private.has_role(auth.uid(), 'teamlead'::public.app_role));

CREATE POLICY "Admins can manage buyer real names"
ON public.buyer_real_names FOR ALL TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

CREATE TRIGGER update_buyer_real_names_updated_at
BEFORE UPDATE ON public.buyer_real_names
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
COMMIT;

-- 20260803053129_366f169c-e566-432d-be3e-102b5c4cf51c.sql
BEGIN;
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
COMMIT;

-- 20260803053206_d2921a7a-bde7-4936-a659-2b660d931e86.sql
BEGIN;
CREATE OR REPLACE FUNCTION public.log_action(_action text, _entity_type text, _entity_id uuid DEFAULT NULL::uuid, _task_id uuid DEFAULT NULL::uuid, _target_user_id uuid DEFAULT NULL::uuid, _details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  new_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;
  IF _action IS NULL OR length(_action) = 0 OR length(_action) > 64 THEN
    RETURN NULL;
  END IF;
  IF _entity_type IS NULL OR length(_entity_type) = 0 OR length(_entity_type) > 64 THEN
    RETURN NULL;
  END IF;
  IF _details IS NOT NULL AND length(_details::text) > 8000 THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.action_logs (
    actor_id, target_user_id, task_id, entity_type, entity_id, action, details
  ) VALUES (
    auth.uid(), _target_user_id, _task_id, _entity_type, _entity_id, _action, COALESCE(_details, '{}'::jsonb)
  )
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.log_actions_batch(_events jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  inserted_count integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;
  IF _events IS NULL OR jsonb_typeof(_events) <> 'array' THEN
    RETURN 0;
  END IF;
  IF jsonb_array_length(_events) > 200 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.action_logs (
    actor_id, target_user_id, task_id, entity_type, entity_id, action, details, created_at
  )
  SELECT
    auth.uid(),
    NULLIF(e->>'target_user_id','')::uuid,
    NULLIF(e->>'task_id','')::uuid,
    left(e->>'entity_type', 64),
    NULLIF(e->>'entity_id','')::uuid,
    left(e->>'action', 64),
    COALESCE(e->'details', '{}'::jsonb),
    COALESCE(NULLIF(e->>'created_at','')::timestamptz, now())
  FROM jsonb_array_elements(_events) AS e
  WHERE e->>'action' IS NOT NULL AND e->>'entity_type' IS NOT NULL
    AND length(COALESCE(e->'details','{}'::jsonb)::text) <= 8000;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$function$;
COMMIT;

-- 20260803053548_c3932dbb-2904-4a5c-9604-df3f0ba6bdd3.sql
BEGIN;
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
COMMIT;

-- 20260803054420_7f8937bd-6ef0-445a-8c8a-23880779faca.sql
BEGIN;
GRANT EXECUTE ON FUNCTION private.has_buyer_relationship(uuid, uuid) TO authenticated;
COMMIT;

-- 20260803055015_9e239aae-2c5e-4499-bc9e-6a121939f55a.sql
BEGIN;
CREATE OR REPLACE FUNCTION public.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  first_segment text;
  task_uuid uuid;
  t_owner uuid;
  t_buyer uuid;
  designer uuid;
  buyer uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  -- description-images/{user_id}/...
  IF first_segment = 'description-images' THEN
    IF split_part(_path, '/', 2) = auth.uid()::text THEN
      RETURN true;
    END IF;
    RETURN EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.description LIKE '%' || _path || '%'
        AND (t.user_id = auth.uid() OR t.buyer_id = auth.uid() OR public.is_teamlead_of(auth.uid(), t.user_id))
    );
  END IF;

  -- buyer-chat/{designer_id}/{buyer_id}/...
  IF first_segment = 'buyer-chat' THEN
    BEGIN
      designer := split_part(_path, '/', 2)::uuid;
      buyer := split_part(_path, '/', 3)::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
    RETURN auth.uid() = designer
        OR auth.uid() = buyer
        OR public.is_teamlead_of(auth.uid(), designer);
  END IF;

  -- chat/{task_id}/...
  IF first_segment = 'chat' THEN
    BEGIN
      task_uuid := split_part(_path, '/', 2)::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
  ELSE
    -- {task_id}/...
    BEGIN
      task_uuid := first_segment::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
  END IF;

  SELECT t.user_id, t.buyer_id INTO t_owner, t_buyer FROM public.tasks t WHERE t.id = task_uuid;
  IF t_owner IS NULL THEN
    RETURN false;
  END IF;

  RETURN auth.uid() = t_owner
      OR auth.uid() = t_buyer
      OR public.is_teamlead_of(auth.uid(), t_owner);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.can_access_task_file(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.can_access_task_file(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_access_task_file(text) TO authenticated, service_role;
COMMIT;

-- 20260803173702_b94f3762-94d9-4d1c-bbaf-4d4b3805769b.sql
BEGIN;
CREATE INDEX IF NOT EXISTS idx_tasks_status_completed_at ON public.tasks (status, completed_at);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles (role);
CREATE INDEX IF NOT EXISTS idx_task_attachments_task_created ON public.task_attachments (task_id, created_at DESC);
COMMIT;

-- 20260806150450_25de4874-0841-43dd-a368-b5c4dd7f817a.sql
BEGIN;
CREATE TABLE IF NOT EXISTS public.telegram_group_chats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id text NOT NULL,
  label text,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.telegram_group_chats TO authenticated;
GRANT ALL ON public.telegram_group_chats TO service_role;
ALTER TABLE public.telegram_group_chats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins manage telegram group chats" ON public.telegram_group_chats;
CREATE POLICY "Admins manage telegram group chats"
ON public.telegram_group_chats FOR ALL TO authenticated
USING (private.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

CREATE INDEX IF NOT EXISTS idx_telegram_group_chats_user ON public.telegram_group_chats (user_id);

INSERT INTO public.telegram_group_chats (chat_id, user_id)
SELECT DISTINCT trim(part), NULL::uuid
FROM public.site_settings s,
     LATERAL unnest(string_to_array(coalesce(s.value,''), ',')) AS part
WHERE s.key = 'telegram_group_chat_ids' AND trim(part) <> ''
  AND NOT EXISTS (SELECT 1 FROM public.telegram_group_chats g WHERE g.chat_id = trim(part));
COMMIT;

-- 20260810161158_585a6b19-3568-4da6-96e3-222c9a408b20.sql
BEGIN;
CREATE TABLE public.telegram_deferred_messages (
  id uuid primary key default gen_random_uuid(),
  chat_ids text[] not null,
  text text not null,
  parse_mode text not null default 'HTML',
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
GRANT ALL ON public.telegram_deferred_messages TO service_role;
ALTER TABLE public.telegram_deferred_messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_tdm_pending ON public.telegram_deferred_messages (created_at) WHERE sent_at IS NULL;
COMMIT;

-- 20260810162339_8933a25a-31b1-437e-8c6c-105cc24d64df.sql
BEGIN;
ALTER TYPE public.task_board ADD VALUE IF NOT EXISTS 'cs2';
COMMIT;

-- 20260810164630_1ea03c2e-bb5a-4645-8e32-08845736ea09.sql
BEGIN;
DROP INDEX IF EXISTS public.tasks_task_code_unique_idx;

CREATE UNIQUE INDEX IF NOT EXISTS tasks_board_task_code_unique_idx
ON public.tasks (board, (NULLIF(btrim(task_code), '')))
WHERE NULLIF(btrim(task_code), '') IS NOT NULL;
COMMIT;

-- 20260810170333_00c70ee4-3aa5-4fa8-a30a-dabe0cfaa5cb.sql
BEGIN;
update public.tasks set status='todo' where task_code='#22';
COMMIT;

-- 20260811144805_4539c724-fb87-4f72-befc-b2b554f6759d.sql
BEGIN;
CREATE OR REPLACE FUNCTION public.cleanup_old_chat_images()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT name FROM storage.objects
    WHERE bucket_id = 'task-files'
      AND (name LIKE 'chat/%' OR name LIKE 'buyer-chat/%')
      AND created_at < now() - interval '5 days'
  LOOP
    DELETE FROM storage.objects WHERE bucket_id = 'task-files' AND name = rec.name;
    UPDATE public.task_chat_messages SET image_url = NULL WHERE image_url = rec.name;
    UPDATE public.buyer_chat_messages SET image_url = NULL WHERE image_url = rec.name;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_old_chat_images() FROM PUBLIC, anon, authenticated;
COMMIT;

-- 20260814102918_55b88200-1e59-4045-932d-9279cad50b6c.sql
BEGIN;
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
COMMIT;

-- 20260825134949_a8396a3d-5b1f-45f1-b11d-228ec6f2f043.sql
BEGIN;
CREATE OR REPLACE FUNCTION private.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  first_segment text;
  task_owner uuid;
  task_uuid uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF private.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  -- Images embedded into task descriptions/comments: readable by any authenticated member
  IF first_segment = 'description-images' THEN
    RETURN true;
  END IF;

  BEGIN
    task_uuid := first_segment::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  SELECT user_id INTO task_owner FROM public.tasks WHERE id = task_uuid;
  IF task_owner IS NULL THEN
    RETURN false;
  END IF;
  IF task_owner = auth.uid() THEN
    RETURN true;
  END IF;
  IF private.is_teamlead_of(auth.uid(), task_owner) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;
COMMIT;

-- 20260828064705_4f552655-94cf-4634-9bff-03b72771e0d4.sql
BEGIN;
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
COMMIT;

-- 20260828074133_7fb1ba9d-5fe5-4306-bdd1-e67d68c58584.sql
BEGIN;
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
COMMIT;

-- 20260828075515_44f04a7f-2788-4bb6-b167-5d4a11f896ab.sql
BEGIN;
-- 1. InitPlan-оптимизация оставшихся политик (семантика идентична)
ALTER POLICY "Admins can view action logs" ON public.action_logs
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

ALTER POLICY "Admins can delete boards" ON public.boards
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
ALTER POLICY "Admins can update boards" ON public.boards
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
ALTER POLICY "Admins can insert boards" ON public.boards
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

ALTER POLICY "Admins and teamleads can read buyer real names" ON public.buyer_real_names
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));
ALTER POLICY "Admins can manage buyer real names" ON public.buyer_real_names
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

ALTER POLICY "Admins and teamleads can delete guide files" ON public.guide_files
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));
ALTER POLICY "Admins and teamleads can insert guide files" ON public.guide_files
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));

ALTER POLICY "Admins and teamleads can delete guides" ON public.guides
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));
ALTER POLICY "Admins and teamleads can insert guides" ON public.guides
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));
ALTER POLICY "Admins and teamleads can update guides" ON public.guides
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));

ALTER POLICY "Admins can update site_settings" ON public.site_settings
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));
ALTER POLICY "Admins can insert site_settings" ON public.site_settings
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

ALTER POLICY "Member can view own membership" ON public.team_memberships
  USING (member_id = (SELECT auth.uid()));
ALTER POLICY "Teamlead can view own memberships" ON public.team_memberships
  USING (teamlead_id = (SELECT auth.uid()));
ALTER POLICY "Admins manage memberships" ON public.team_memberships
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

ALTER POLICY "Admins manage telegram group chats" ON public.telegram_group_chats
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role)));

-- 2. Удаление избыточных индексов (перекрыты более полными / уникальными)
DROP INDEX IF EXISTS public.idx_tasks_status;              -- префикс idx_tasks_status_completed_at
DROP INDEX IF EXISTS public.idx_tasks_board;               -- фильтрация по доске идёт на клиенте
DROP INDEX IF EXISTS public.idx_user_roles_user_id;        -- дубль user_roles_user_id_key
DROP INDEX IF EXISTS public.idx_task_attachments_task_id;  -- префикс idx_task_attachments_task_created

ANALYZE public.tasks;
ANALYZE public.profiles;
COMMIT;

-- 20260828080137_e55f72ae-9bfc-409b-b7ed-5b2a6492b339.sql
BEGIN;
CREATE OR REPLACE FUNCTION private.can_access_task_file(_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  first_segment text;
  task_uuid uuid;
  t_owner uuid;
  t_buyer uuid;
  designer uuid;
  buyer uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF private.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN true;
  END IF;

  first_segment := split_part(_path, '/', 1);

  -- Images embedded into task descriptions/comments: readable by any authenticated member
  IF first_segment = 'description-images' THEN
    RETURN true;
  END IF;

  -- buyer-chat/{designer_id}/{buyer_id}/...
  IF first_segment = 'buyer-chat' THEN
    BEGIN
      designer := split_part(_path, '/', 2)::uuid;
      buyer := split_part(_path, '/', 3)::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
    RETURN auth.uid() = designer
        OR auth.uid() = buyer
        OR private.is_teamlead_of(auth.uid(), designer);
  END IF;

  -- chat/{task_id}/...
  IF first_segment = 'chat' THEN
    BEGIN
      task_uuid := split_part(_path, '/', 2)::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
  ELSE
    BEGIN
      task_uuid := first_segment::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
  END IF;

  SELECT t.user_id, t.buyer_id INTO t_owner, t_buyer FROM public.tasks t WHERE t.id = task_uuid;
  IF t_owner IS NULL THEN
    RETURN false;
  END IF;

  RETURN auth.uid() = t_owner
      OR auth.uid() = t_buyer
      OR private.is_teamlead_of(auth.uid(), t_owner);
END;
$function$;
COMMIT;

-- 20260916084751_f7f816d9-c54a-4317-9257-6e9f81a099e1.sql
BEGIN;
ALTER TABLE public.guides ADD COLUMN IF NOT EXISTS section text NOT NULL DEFAULT 'guide';
CREATE INDEX IF NOT EXISTS idx_guides_section_updated_at ON public.guides (section, updated_at DESC);
COMMIT;

-- 20260916181514_0c70ba6a-0c00-4854-a104-db7f88d62db2.sql
BEGIN;
CREATE OR REPLACE FUNCTION public.cleanup_old_tasks()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  old_ids uuid[];
  deleted_count integer := 0;
BEGIN
  SELECT array_agg(id) INTO old_ids
  FROM public.tasks
  WHERE status = 'done'::task_status
    AND COALESCE(completed_at, updated_at, created_at) < now() - interval '3 months';

  IF old_ids IS NULL OR array_length(old_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  -- files stored for these tasks
  DELETE FROM storage.objects
  WHERE bucket_id = 'task-files'
    AND name IN (SELECT file_path FROM public.task_attachments WHERE task_id = ANY(old_ids));

  DELETE FROM storage.objects
  WHERE bucket_id = 'task-files'
    AND split_part(name, '/', 1) = 'chat'
    AND split_part(name, '/', 2) = ANY(SELECT unnest(old_ids)::text);

  DELETE FROM public.task_attachments WHERE task_id = ANY(old_ids);
  DELETE FROM public.task_comments WHERE task_id = ANY(old_ids);
  DELETE FROM public.task_chat_messages WHERE task_id = ANY(old_ids);
  DELETE FROM public.action_logs WHERE task_id = ANY(old_ids);
  DELETE FROM public.tasks WHERE id = ANY(old_ids);

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_old_tasks() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_tasks() TO service_role;
COMMIT;

-- 20260916182008_97139408-7d48-4275-a801-df2d0bc7a417.sql
BEGIN;
CREATE TABLE public.user_last_visits (user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE, ip_address inet, country text, last_seen_at timestamptz NOT NULL DEFAULT now()); GRANT SELECT ON public.user_last_visits TO authenticated; GRANT ALL ON public.user_last_visits TO service_role; ALTER TABLE public.user_last_visits ENABLE ROW LEVEL SECURITY; CREATE POLICY admin_read_visits ON public.user_last_visits FOR SELECT TO authenticated USING ((SELECT private.has_role(auth.uid(), 'admin'::public.app_role)));
COMMIT;

-- 20260917000000_railway_backend.sql
BEGIN;
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

-- 20260921000000_independent_storage.sql
BEGIN;
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
COMMIT;
