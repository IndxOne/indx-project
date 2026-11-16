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
drop schema if exists management_next cascade;   -- ne touche ni public, ni auth
