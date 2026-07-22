-- ============================================================
-- HM Global — Outil interne : socle de sécurité (v1)
-- ------------------------------------------------------------
-- Ce que fait ce script :
--   1. Recrée les 4 tables avec des identifiants "uuid" alignés sur
--      l'authentification native de Supabase (auth.users).
--   2. Supprime l'ancienne table `users` (mots de passe en clair).
--   3. Active le Row Level Security (RLS) et pose les règles d'accès.
--   4. Crée automatiquement le "profil" d'un compte dès sa création.
--
-- Où l'exécuter : Supabase → projet "hmglobal-interne" → SQL Editor →
--   New query → coller tout → Run.
--
-- ⚠️ Ce script SUPPRIME puis RECREE les tables. Il n'y a aucune donnée
--    réelle à conserver (confirmé). Les éventuelles lignes de test seront
--    effacées — c'est voulu, on repart propre.
-- ============================================================

-- 1) On repart de tables propres (elles sont vides / de test)
drop table if exists public.notes    cascade;
drop table if exists public.tasks    cascade;
drop table if exists public.clients  cascade;
drop table if exists public.users    cascade;  -- ancienne table + mots de passe en clair : supprimée
drop table if exists public.profiles cascade;

-- 2) Profil applicatif, relié 1-pour-1 au compte de connexion (auth.users)
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  role       text not null default 'collab' check (role in ('admin','collab')),
  created_at timestamptz not null default now()
);

create table public.clients (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  sector     text,
  ville      text,
  siren      text,
  created_at timestamptz not null default now()
);

create table public.tasks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  client_id  uuid references public.clients(id) on delete set null,
  title      text not null,
  hours      numeric(5,1) not null check (hours > 0),
  date       date not null,
  status     text not null default 'en cours' check (status in ('en cours','en attente','terminé')),
  created_at timestamptz not null default now()
);

create table public.notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  fr         text,
  tr         text,
  date       date not null default current_date,
  created_at timestamptz not null default now()
);

-- 3) Row Level Security : la vraie serrure (côté base)
alter table public.profiles enable row level security;
alter table public.clients  enable row level security;
alter table public.tasks    enable row level security;
alter table public.notes    enable row level security;

-- "Suis-je admin ?" — en SECURITY DEFINER pour éviter toute boucle infinie
-- (la fonction contourne le RLS de l'intérieur : elle ne se re-verrouille pas).
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- profiles : je vois le mien ; l'admin voit tout le monde
create policy "profiles_select" on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- clients : tout collaborateur connecté lit / ajoute / modifie ; SEUL l'admin supprime
create policy "clients_select" on public.clients
  for select using (auth.uid() is not null);
create policy "clients_insert" on public.clients
  for insert with check (auth.uid() is not null);
create policy "clients_update" on public.clients
  for update using (auth.uid() is not null);
create policy "clients_delete" on public.clients
  for delete using (public.is_admin());

-- tasks : un collab ne voit/gère QUE ses tâches ; l'admin voit tout
create policy "tasks_select" on public.tasks
  for select using (user_id = auth.uid() or public.is_admin());
create policy "tasks_insert" on public.tasks
  for insert with check (user_id = auth.uid());
create policy "tasks_update" on public.tasks
  for update using (user_id = auth.uid() or public.is_admin())
  with check  (user_id = auth.uid() or public.is_admin());
create policy "tasks_delete" on public.tasks
  for delete using (user_id = auth.uid() or public.is_admin());

-- notes : strictement privées à leur auteur
create policy "notes_all" on public.notes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 4) À la création d'un compte (tableau de bord Supabase), créer son profil.
--    name / role peuvent être fournis dans "User metadata" ; sinon défauts.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name',''), split_part(new.email,'@',1)),
    coalesce(nullif(new.raw_user_meta_data->>'role',''), 'collab')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- APRÈS avoir créé les comptes dans le tableau de bord, désigner l'admin
-- (à lancer une fois, en remplaçant l'email) :
--
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'directeur@hmglobal.fr');
-- ------------------------------------------------------------
