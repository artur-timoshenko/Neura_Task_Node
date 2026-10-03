-- After copying avatars/company-assets, replace ONLY the two origins below.
-- Updates persisted public asset references. No storage objects are deleted.
BEGIN;
SET LOCAL hub.old_origin = 'https://OLD_PROJECT.supabase.co';
SET LOCAL hub.frontend_origin = 'https://YOUR_FRONTEND_DOMAIN';
UPDATE public.profiles
SET avatar_url = replace(avatar_url,
  current_setting('hub.old_origin') || '/storage/v1/object/public/avatars/',
  current_setting('hub.frontend_origin') || '/api/supabase/storage/v1/object/public/avatars/')
WHERE avatar_url LIKE current_setting('hub.old_origin') || '/storage/v1/object/public/avatars/%';
UPDATE public.site_settings
SET value = replace(value,
  current_setting('hub.old_origin') || '/storage/v1/object/public/company-assets/',
  current_setting('hub.frontend_origin') || '/api/supabase/storage/v1/object/public/company-assets/')
WHERE key = 'company_logo' AND value LIKE current_setting('hub.old_origin') || '/storage/v1/object/public/company-assets/%';
COMMIT;
