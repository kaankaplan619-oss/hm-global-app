-- ============================================================
-- HM Global — outil interne : durcissement (v1)
-- ------------------------------------------------------------
-- Suite à l'audit de sécurité Supabase (Security Advisor), les deux
-- fonctions SECURITY DEFINER (is_admin, handle_new_user) étaient
-- appelables via l'API REST (/rest/v1/rpc/...) par les rôles anon et
-- authenticated (avertissements 0028 / 0029).
--
-- Correctif : on les déplace dans un schéma privé, NON exposé par l'API.
--   - Les policies RLS continuent de les appeler (référence par OID).
--   - Le trigger continue de fonctionner (recréé explicitement).
--   - Plus aucune de ces fonctions n'est appelable depuis l'extérieur.
--
-- Après application : Security Advisor ne remonte plus aucun problème.
-- ============================================================

create schema if not exists private;
grant usage on schema private to anon, authenticated;

alter function public.is_admin()        set schema private;
alter function public.handle_new_user() set schema private;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();
