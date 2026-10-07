-- Étape 2/3 — Lie chaque ligne de public.users à son compte Supabase Auth,
-- rattache tâches et notes aux profils, puis active RLS partout.
--
-- Prérequis : un compte Supabase Auth existe pour chaque e-mail de
-- public.users (scripts/migrate-users-to-auth.mjs ou tableau de bord).
-- Toutes les vérifications passent avant la première modification :
-- en cas d'erreur, rien n'a changé.
--
-- À partir d'ici, les anciennes pages (connexion via la table users) ne
-- fonctionnent plus : déployer les nouvelles pages en même temps.

-- 1. Vérifications préalables -------------------------------------------------

do $$
declare
  missing text;
  dupes text;
begin
  select string_agg(coalesce(u.email, '(id ' || u.id::text || ', sans e-mail)'), ', ')
    into missing
  from public.users u
  where not exists (
    select 1 from auth.users a where lower(a.email) = lower(trim(u.email))
  );
  if missing is not null then
    raise exception 'Compte Supabase Auth manquant pour : %. Créez-les avant de relancer ce script.', missing;
  end if;

  select string_agg(e, ', ') into dupes
  from (
    select lower(trim(email)) as e from public.users group by 1 having count(*) > 1
  ) d;
  if dupes is not null then
    raise exception 'E-mails en double dans public.users : %. Dédoublonnez avant de relancer.', dupes;
  end if;

  if exists (select 1 from public.tasks t where t.user_id is not null
             and not exists (select 1 from public.users u where u.id = t.user_id)) then
    raise exception 'Des tâches référencent un utilisateur absent de public.users ; corrigez-les avant de relancer.';
  end if;
  if exists (select 1 from public.notes n where n.user_id is not null
             and not exists (select 1 from public.users u where u.id = n.user_id)) then
    raise exception 'Des notes référencent un utilisateur absent de public.users ; corrigez-les avant de relancer.';
  end if;
end $$;

-- 2. Profils -------------------------------------------------------------------

insert into public.profiles (id, email, name, role, legacy_user_id)
select
  a.id,
  a.email,
  coalesce(nullif(trim(u.name), ''), a.email),
  case when u.role = 'admin' then 'admin' else 'collab' end,
  u.id::text
from public.users u
join auth.users a on lower(a.email) = lower(trim(u.email))
on conflict (id) do update
  set name = excluded.name,
      role = excluded.role,
      legacy_user_id = excluded.legacy_user_id;

-- 3. tasks.user_id et notes.user_id pointent désormais sur profiles.id --------

-- Les anciennes politiques (ex. « allow all ») s'ajouteraient aux nouvelles :
-- on repart de zéro sur ces quatre tables.
do $$
declare pol record;
begin
  for pol in
    select tablename, policyname from pg_policies
    where schemaname = 'public' and tablename in ('users', 'clients', 'tasks', 'notes')
  loop
    execute format('drop policy %I on public.%I', pol.policyname, pol.tablename);
  end loop;
end $$;

-- Clés étrangères de tasks/notes vers public.users, quel que soit leur nom.
do $$
declare fk record;
begin
  for fk in
    select conrelid::regclass as tbl, conname from pg_constraint
    where contype = 'f'
      and confrelid = 'public.users'::regclass
      and conrelid in ('public.tasks'::regclass, 'public.notes'::regclass)
  loop
    execute format('alter table %s drop constraint %I', fk.tbl, fk.conname);
  end loop;
end $$;

alter table public.tasks add column user_id_new uuid;
update public.tasks t
  set user_id_new = p.id
  from public.profiles p
  where p.legacy_user_id = t.user_id::text;

alter table public.notes add column user_id_new uuid;
update public.notes n
  set user_id_new = p.id
  from public.profiles p
  where p.legacy_user_id = n.user_id::text;

alter table public.tasks drop column user_id;
alter table public.tasks rename column user_id_new to user_id;
alter table public.tasks alter column user_id set default auth.uid();
alter table public.tasks
  add constraint tasks_user_id_fkey foreign key (user_id) references public.profiles (id);
create index if not exists tasks_user_id_idx on public.tasks (user_id);

alter table public.notes drop column user_id;
alter table public.notes rename column user_id_new to user_id;
alter table public.notes alter column user_id set default auth.uid();
alter table public.notes
  add constraint notes_user_id_fkey foreign key (user_id) references public.profiles (id);
create index if not exists notes_user_id_idx on public.notes (user_id);

-- 4. RLS -------------------------------------------------------------------------

-- users : plus aucun accès via l'API (ni anon, ni utilisateur connecté).
alter table public.users enable row level security;
revoke all on public.users from anon, authenticated;

-- clients : lecture pour toute l'équipe, écriture et suppression admin.
alter table public.clients enable row level security;
revoke all on public.clients from anon;

create policy "clients_select_staff" on public.clients
  for select to authenticated
  using ((select private.my_role()) is not null);

create policy "clients_insert_admin" on public.clients
  for insert to authenticated
  with check ((select private.is_admin()));

create policy "clients_update_admin" on public.clients
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "clients_delete_admin" on public.clients
  for delete to authenticated
  using ((select private.is_admin()));

-- tasks : un collab ne voit et ne modifie que ses tâches ; l'admin voit tout.
alter table public.tasks enable row level security;
revoke all on public.tasks from anon;

create policy "tasks_select_own_or_admin" on public.tasks
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "tasks_insert_own_or_admin" on public.tasks
  for insert to authenticated
  with check (
    (user_id = (select auth.uid()) and (select private.my_role()) is not null)
    or (select private.is_admin())
  );

create policy "tasks_update_own_or_admin" on public.tasks
  for update to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()))
  with check (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "tasks_delete_own_or_admin" on public.tasks
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

-- notes : mêmes règles que les tâches.
alter table public.notes enable row level security;
revoke all on public.notes from anon;

create policy "notes_select_own_or_admin" on public.notes
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "notes_insert_own_or_admin" on public.notes
  for insert to authenticated
  with check (
    (user_id = (select auth.uid()) and (select private.my_role()) is not null)
    or (select private.is_admin())
  );

create policy "notes_update_own_or_admin" on public.notes
  for update to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()))
  with check (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "notes_delete_own_or_admin" on public.notes
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
