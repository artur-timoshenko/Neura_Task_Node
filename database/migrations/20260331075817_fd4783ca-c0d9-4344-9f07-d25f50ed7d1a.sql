
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
