CREATE POLICY "Authenticated can view buyer roles" ON public.user_roles FOR SELECT TO authenticated USING (role = 'buyer'::app_role);
