\set ON_ERROR_STOP on
-- Retour arrière de la migration 0004 UNIQUEMENT (0001-0003 conservées). Idempotent.
do $guard$ declare v text;
begin
  if inet_server_addr() is not null then raise exception 'REFUS: cible non locale POC (connexion TCP)'; end if;
  if to_regclass('public.__poc_sentinel') is null then raise exception 'REFUS: cible non locale POC (sentinelle absente)'; end if;
  execute 'select value from public.__poc_sentinel limit 1' into v;
  if v is distinct from 'MANAGEMENT_NEXT_LOCAL_POC' then raise exception 'REFUS: cible non locale POC (sentinelle inattendue)'; end if;
end $guard$;
begin;
drop trigger if exists mn_guard_last_owner_upd on management_next.memberships;
drop trigger if exists mn_guard_last_owner_del on management_next.memberships;
drop trigger if exists mn_guard_archived_project on management_next.actions;
drop function if exists management_next.mn_guard_last_owner();
drop function if exists management_next.mn_guard_archived_project();
delete from management_next.schema_migrations where name like '20261116000004%';
commit;
