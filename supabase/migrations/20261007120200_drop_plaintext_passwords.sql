-- Étape 3/3 — Supprime les mots de passe en clair.
--
-- À exécuter une fois que chaque admin et collab s'est connecté avec
-- succès sur les nouvelles pages (Supabase Auth stocke ses propres
-- empreintes bcrypt dans auth.users).

do $$
declare
  unlinked text;
begin
  select string_agg(coalesce(u.email, '(id ' || u.id::text || ')'), ', ')
    into unlinked
  from public.users u
  where not exists (
    select 1 from public.profiles p where p.legacy_user_id = u.id::text
  );
  if unlinked is not null then
    raise exception 'Utilisateurs sans profil : %. Lancez d''abord l''étape 2.', unlinked;
  end if;
end $$;

alter table public.users drop column if exists password;
