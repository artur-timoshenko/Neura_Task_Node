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

ALTER POLICY "Admins and teamleads manage buyer real names" ON public.buyer_real_names
  USING ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)))
  WITH CHECK ((SELECT private.has_role((SELECT auth.uid()), 'admin'::app_role) OR private.has_role((SELECT auth.uid()), 'teamlead'::app_role)));

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
