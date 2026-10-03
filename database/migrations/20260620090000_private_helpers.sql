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
