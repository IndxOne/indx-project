-- 0003 — RLS, privilèges minimaux, fonctions contrôlées. Idempotent.
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

-- Rôle de l'appelant dans une organisation, NUL sans accès produit. SECURITY DEFINER pour éviter la
-- récursion RLS sur memberships ; search_path vidé ; EXECUTE réservé à authenticated.
create or replace function management_next.role_in(p_org uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.role
  from management_next.memberships m
  join management_next.product_access a on a.user_id = m.user_id
  where m.org_id = p_org and m.user_id = auth.uid()
$$;

-- Seul chemin de création d'organisation (INSERT direct non accordé).
create or replace function management_next.create_organization(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_org uuid;
begin
  if v_uid is null then
    raise exception 'MN004: authentification requise' using errcode = 'MN004';
  end if;
  if not exists (select 1 from management_next.product_access where user_id = v_uid) then
    raise exception 'MN003: utilisateur sans accès au produit Management' using errcode = 'MN003';
  end if;
  insert into management_next.organizations(name, created_by) values (p_name, v_uid) returning id into v_org;
  insert into management_next.memberships(org_id, user_id, role) values (v_org, v_uid, 'owner');
  return v_org;
end $$;

revoke all on function management_next.role_in(uuid), management_next.create_organization(text) from public, anon;
grant execute on function management_next.role_in(uuid), management_next.create_organization(text) to authenticated;

alter table management_next.schema_migrations enable row level security;
alter table management_next.product_access    enable row level security;
alter table management_next.organizations     enable row level security;
alter table management_next.memberships       enable row level security;
alter table management_next.projects          enable row level security;
alter table management_next.actions           enable row level security;

-- Privilèges : rien par défaut, puis liste blanche minimale (colonnes incluses).
revoke all on schema management_next from public, anon, authenticated, service_role;
revoke all on all tables in schema management_next from public, anon, authenticated, service_role;
grant usage on schema management_next to authenticated;
grant select on management_next.product_access to authenticated;
grant select, delete on management_next.organizations to authenticated;
grant update (name) on management_next.organizations to authenticated;
grant select, delete on management_next.memberships to authenticated;
grant insert (org_id, user_id, role), update (role) on management_next.memberships to authenticated;
grant select, delete on management_next.projects to authenticated;
grant insert (org_id, name, status), update (name, status) on management_next.projects to authenticated;
grant select, delete on management_next.actions to authenticated;
grant insert (org_id, project_id, title, status), update (title, status) on management_next.actions to authenticated;

drop policy if exists product_access_self on management_next.product_access;
create policy product_access_self on management_next.product_access for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists org_select on management_next.organizations;
create policy org_select on management_next.organizations for select to authenticated
  using ((select management_next.role_in(id)) is not null);
drop policy if exists org_update on management_next.organizations;
create policy org_update on management_next.organizations for update to authenticated
  using ((select management_next.role_in(id)) = 'owner') with check ((select management_next.role_in(id)) = 'owner');
drop policy if exists org_delete on management_next.organizations;
create policy org_delete on management_next.organizations for delete to authenticated
  using ((select management_next.role_in(id)) = 'owner');

drop policy if exists mem_select on management_next.memberships;
create policy mem_select on management_next.memberships for select to authenticated
  using ((select management_next.role_in(org_id)) is not null);
drop policy if exists mem_insert on management_next.memberships;
create policy mem_insert on management_next.memberships for insert to authenticated
  with check ((select management_next.role_in(org_id)) = 'owner');
drop policy if exists mem_update on management_next.memberships;
create policy mem_update on management_next.memberships for update to authenticated
  using ((select management_next.role_in(org_id)) = 'owner') with check ((select management_next.role_in(org_id)) = 'owner');
drop policy if exists mem_delete on management_next.memberships;
create policy mem_delete on management_next.memberships for delete to authenticated
  using ((select management_next.role_in(org_id)) = 'owner');

drop policy if exists prj_select on management_next.projects;
create policy prj_select on management_next.projects for select to authenticated
  using ((select management_next.role_in(org_id)) is not null);
drop policy if exists prj_insert on management_next.projects;
create policy prj_insert on management_next.projects for insert to authenticated
  with check ((select management_next.role_in(org_id)) in ('owner','editor'));
drop policy if exists prj_update on management_next.projects;
create policy prj_update on management_next.projects for update to authenticated
  using ((select management_next.role_in(org_id)) in ('owner','editor'))
  with check ((select management_next.role_in(org_id)) in ('owner','editor'));
drop policy if exists prj_delete on management_next.projects;
create policy prj_delete on management_next.projects for delete to authenticated
  using ((select management_next.role_in(org_id)) = 'owner');

drop policy if exists act_select on management_next.actions;
create policy act_select on management_next.actions for select to authenticated
  using ((select management_next.role_in(org_id)) is not null);
drop policy if exists act_insert on management_next.actions;
create policy act_insert on management_next.actions for insert to authenticated
  with check ((select management_next.role_in(org_id)) in ('owner','editor'));
drop policy if exists act_update on management_next.actions;
create policy act_update on management_next.actions for update to authenticated
  using ((select management_next.role_in(org_id)) in ('owner','editor'))
  with check ((select management_next.role_in(org_id)) in ('owner','editor'));
drop policy if exists act_delete on management_next.actions;
create policy act_delete on management_next.actions for delete to authenticated
  using ((select management_next.role_in(org_id)) in ('owner','editor'));
