-- 0002 — Invariants métier au niveau base (déclencheurs). Idempotent.
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

create or replace function management_next.mn_guard_projects() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.org_id is distinct from old.org_id then
    raise exception 'MN001: id/org_id d''un projet sont immuables' using errcode = 'MN001';
  end if;
  return new;
end $$;

create or replace function management_next.mn_guard_actions() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.org_id is distinct from old.org_id
     or new.project_id is distinct from old.project_id then
    raise exception 'MN001: id/org_id/project_id d''une action sont immuables' using errcode = 'MN001';
  end if;
  if old.status = 'done' then
    if new.status is distinct from 'done' or new.done_at is distinct from old.done_at then
      raise exception 'MN002: une action terminée ne peut être ni rouverte ni redatée' using errcode = 'MN002';
    end if;
  elsif new.status = 'done' then
    new.done_at := now();
  end if;
  return new;
end $$;

create or replace function management_next.mn_default_done_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'done' and new.done_at is null then new.done_at := now(); end if;
  return new;
end $$;

create or replace function management_next.mn_guard_memberships() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.org_id is distinct from old.org_id or new.user_id is distinct from old.user_id then
    raise exception 'MN001: org_id/user_id d''une appartenance sont immuables' using errcode = 'MN001';
  end if;
  return new;
end $$;

-- SECURITY DEFINER : doit lire product_access que l'appelant ne voit pas. Non appelable (fonction trigger).
create or replace function management_next.mn_member_requires_access() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from management_next.product_access where user_id = new.user_id) then
    raise exception 'MN003: utilisateur sans accès au produit Management' using errcode = 'MN003';
  end if;
  return new;
end $$;

drop trigger if exists mn_guard_projects on management_next.projects;
create trigger mn_guard_projects before update on management_next.projects
  for each row execute function management_next.mn_guard_projects();
drop trigger if exists mn_guard_actions on management_next.actions;
create trigger mn_guard_actions before update on management_next.actions
  for each row execute function management_next.mn_guard_actions();
drop trigger if exists mn_default_done_at on management_next.actions;
create trigger mn_default_done_at before insert on management_next.actions
  for each row execute function management_next.mn_default_done_at();
drop trigger if exists mn_guard_memberships on management_next.memberships;
create trigger mn_guard_memberships before update on management_next.memberships
  for each row execute function management_next.mn_guard_memberships();
drop trigger if exists mn_member_requires_access on management_next.memberships;
create trigger mn_member_requires_access before insert on management_next.memberships
  for each row execute function management_next.mn_member_requires_access();

revoke all on function management_next.mn_guard_projects(), management_next.mn_guard_actions(),
  management_next.mn_default_done_at(), management_next.mn_guard_memberships(),
  management_next.mn_member_requires_access() from public, anon, authenticated;
