\set ON_ERROR_STOP on
-- ÉTAPE OBLIGATOIRE après `pg_restore -n management_next` : l'ACL du SCHÉMA lui-même n'est pas restaurée
-- (constaté par la preuve : sans elle, authenticated perd tout accès — échec fermé, aucune fuite).
do $guard$ declare v text;
begin
  if inet_server_addr() is not null then raise exception 'REFUS: cible non locale POC (connexion TCP)'; end if;
  if to_regclass('public.__poc_sentinel') is null then raise exception 'REFUS: cible non locale POC (sentinelle absente)'; end if;
  execute 'select value from public.__poc_sentinel limit 1' into v;
  if v is distinct from 'MANAGEMENT_NEXT_LOCAL_POC' then raise exception 'REFUS: cible non locale POC (sentinelle inattendue)'; end if;
end $guard$;
revoke all on schema management_next from public, anon, authenticated, service_role;
grant usage on schema management_next to authenticated;
