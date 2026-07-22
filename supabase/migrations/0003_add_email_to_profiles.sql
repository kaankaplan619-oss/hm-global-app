-- ============================================================
-- HM Global — outil interne : email dans les profils
-- ------------------------------------------------------------
-- La liste des collaborateurs (côté admin) affiche l'email. La source
-- de vérité reste auth.users ; on en garde une copie lisible dans
-- profiles, remplie automatiquement à la création du compte par le
-- trigger handle_new_user (déplacé dans le schéma private en 0002).
-- ============================================================

alter table public.profiles add column if not exists email text;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name, email, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name',''), split_part(new.email,'@',1)),
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'role',''), 'collab')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
