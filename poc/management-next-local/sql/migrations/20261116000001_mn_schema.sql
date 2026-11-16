-- 0001 — Schéma management_next : tables et intégrité relationnelle. Idempotent.
\set ON_ERROR_STOP on
-- Garde de cible (échoue fermé) : sentinelle POC obligatoire + connexion par socket Unix uniquement.
do $guard$ declare v text;
begin
  if inet_server_addr() is not null then
    raise exception 'REFUS: cible non locale POC (connexion TCP)';
  end if;
  if to_regclass('public.__poc_sentinel') is null then
    raise exception 'REFUS: cible non locale POC (sentinelle absente)';
  end if;
  execute 'select value from public.__poc_sentinel limit 1' into v;
  if v is distinct from 'MANAGEMENT_NEXT_LOCAL_POC' then
    raise exception 'REFUS: cible non locale POC (sentinelle inattendue)';
  end if;
end $guard$;

create schema if not exists management_next;

create table if not exists management_next.schema_migrations (
  name text primary key, checksum text not null, applied_at timestamptz not null default now());

-- Droit d'usage du produit (Auth partagé : avoir un compte ≠ avoir accès à Management).
create table if not exists management_next.product_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);

create table if not exists management_next.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 120),
  created_by uuid not null,                       -- trace uniquement, volontairement sans FK vers auth.users
  created_at timestamptz not null default now()
);

create table if not exists management_next.memberships (
  org_id uuid not null references management_next.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','editor','viewer')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index if not exists memberships_user_id_idx on management_next.memberships(user_id);

create table if not exists management_next.projects (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references management_next.organizations(id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 200),
  status text not null default 'active' check (status in ('active','archived')),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, org_id)
);
create index if not exists projects_org_id_idx on management_next.projects(org_id);

create table if not exists management_next.actions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  project_id uuid not null,
  title text not null check (length(btrim(title)) between 1 and 300),
  status text not null default 'open' check (status in ('open','done')),
  done_at timestamptz,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  -- Intégrité inter-organisations NATIVE : une action ne peut référencer qu'un projet de SA organisation.
  foreign key (project_id, org_id) references management_next.projects(id, org_id) on delete restrict,
  check ((status = 'done') = (done_at is not null))
);
create index if not exists actions_project_id_idx on management_next.actions(project_id, org_id);
create index if not exists actions_org_id_idx on management_next.actions(org_id);
