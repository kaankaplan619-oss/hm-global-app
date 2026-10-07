-- Étape 1/3 — Table `profiles` liée à `auth.users` et fonctions de rôle.
--
-- Sans effet sur l'application actuelle : on peut l'exécuter avant de
-- créer les comptes Supabase Auth (voir SECURITE.md).

-- Schéma non exposé par l'API REST : les fonctions d'aide aux politiques
-- y vivent pour ne pas être appelables en RPC.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  name text not null,
  role text not null default 'collab' check (role in ('admin', 'collab')),
  -- Identifiant de la ligne d'origine dans public.users (sert à la migration).
  legacy_user_id text unique,
  created_at timestamptz not null default now()
);

-- Rôle de l'utilisateur connecté, NULL s'il n'a pas de profil.
-- SECURITY DEFINER pour lire profiles sans repasser par ses propres politiques.
create or replace function private.my_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid())
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select private.my_role()) = 'admin', false)
$$;

revoke all on function private.my_role() from public;
revoke all on function private.is_admin() from public;
grant execute on function private.my_role() to authenticated;
grant execute on function private.is_admin() to authenticated;

alter table public.profiles enable row level security;

-- Lecture seule depuis l'API : les profils se gèrent dans le tableau de bord
-- Supabase ou via SQL, jamais depuis la page.
revoke all on public.profiles from anon;
revoke insert, update, delete, truncate on public.profiles from authenticated;
grant select on public.profiles to authenticated;

create policy "profiles_select_self_or_admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));
