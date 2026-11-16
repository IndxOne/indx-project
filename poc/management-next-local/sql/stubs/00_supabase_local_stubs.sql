\set ON_ERROR_STOP on
-- STUBS LOCAUX — imitent le strict nécessaire de Supabase (rôles, auth.users, auth.uid(), privilèges
-- par défaut de `public`). NE FONT PAS partie des migrations Management Next. Différences : voir README §Limites.
create table if not exists public.__poc_sentinel (value text primary key);
insert into public.__poc_sentinel values ('MANAGEMENT_NEXT_LOCAL_POC') on conflict do nothing;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon          nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role  nologin noinherit bypassrls; end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  email text unique,
  created_at timestamptz not null default now()
);
-- Comme GoTrue/PostgREST : le JWT est exposé via des GUC de transaction.
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;

-- Privilèges par défaut de `public` sur Supabase : tout est accordé à anon/authenticated/service_role.
-- Reproduits volontairement pour prouver que management_next n'en hérite pas.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
grant select on public.__poc_sentinel to authenticated;
