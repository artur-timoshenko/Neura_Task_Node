
-- Allow unauthenticated users to read site_settings (for logo on auth page)
DROP POLICY "Anyone can read site_settings" ON public.site_settings;
CREATE POLICY "Anyone can read site_settings"
  ON public.site_settings FOR SELECT
  TO anon, authenticated
  USING (true);
