\set ON_ERROR_STOP on
-- Produit voisin FICTIF (Family / Identity) partageant auth.users, schéma public, RLS « own rows ».
create table if not exists public.family_notes (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null
);
alter table public.family_notes enable row level security;
drop policy if exists family_notes_own on public.family_notes;
create policy family_notes_own on public.family_notes for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table if not exists public.identity_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null
);
alter table public.identity_profiles enable row level security;
drop policy if exists identity_profiles_own on public.identity_profiles;
create policy identity_profiles_own on public.identity_profiles for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
