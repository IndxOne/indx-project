-- 0004 — Corrections R1/R2 (dernier owner) et R4 (projet archivé = figé). Additive, idempotente.
\set ON_ERROR_STOP on
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

-- R1/R2 : une organisation ne peut pas perdre son dernier owner ACTIF par une action UTILISATEUR.
-- « Utilisateur » = JWT présent (auth.uid() non nul). Les opérations d'administration (migration, support,
-- cascade de suppression de compte Auth partagé) n'ont pas d'identité et ne sont PAS bloquées : supprimer
-- un compte Family/Identity ne doit jamais échouer à cause de Management. Les orgs devenues sans owner par
-- cette voie sont détectables (cf. README) et récupérables par un rôle d'administration.
-- SECURITY DEFINER : doit voir tous les owners (product_access/RLS invisibles à l'appelant). Fonction
-- trigger : non appelable en RPC. Verrou consultatif par organisation : deux owners qui se rétrogradent
-- simultanément sont sérialisés (sinon les deux passeraient le contrôle).
create or replace function management_next.mn_guard_last_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or old.role is distinct from 'owner'
     or (tg_op = 'UPDATE' and new.role = 'owner') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(old.org_id::text, 0));
  -- Suppression de l'organisation elle-même (cascade) : autorisée.
  if exists (select 1 from management_next.organizations where id = old.org_id)
     and not exists (select 1 from management_next.memberships m
                     join management_next.product_access a on a.user_id = m.user_id
                     where m.org_id = old.org_id and m.role = 'owner' and m.user_id <> old.user_id) then
    raise exception 'MN005: une organisation doit conserver au moins un owner actif' using errcode = 'MN005';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- R4 : un projet archivé est figé : plus d'ajout, de modification ni de suppression d'actions
-- (réactiver le projet d'abord). Fonction invoker : l'appelant qui écrit voit déjà son projet.
create or replace function management_next.mn_guard_archived_project() returns trigger
language plpgsql set search_path = '' as $$
declare r management_next.actions := case when tg_op = 'DELETE' then old else new end;
begin
  if exists (select 1 from management_next.projects p
             where p.id = r.project_id and p.org_id = r.org_id and p.status = 'archived') then
    raise exception 'MN006: projet archivé, actions en lecture seule (réactiver le projet d''abord)' using errcode = 'MN006';
  end if;
  return r;
end $$;

drop trigger if exists mn_guard_last_owner_upd on management_next.memberships;
create trigger mn_guard_last_owner_upd before update of role on management_next.memberships
  for each row execute function management_next.mn_guard_last_owner();
drop trigger if exists mn_guard_last_owner_del on management_next.memberships;
create trigger mn_guard_last_owner_del before delete on management_next.memberships
  for each row execute function management_next.mn_guard_last_owner();
drop trigger if exists mn_guard_archived_project on management_next.actions;
create trigger mn_guard_archived_project before insert or update or delete on management_next.actions
  for each row execute function management_next.mn_guard_archived_project();

revoke all on function management_next.mn_guard_last_owner(), management_next.mn_guard_archived_project()
  from public, anon, authenticated, service_role;
