\set ON_ERROR_STOP on
-- Aides de test (jamais dans les migrations). pgTAP installé dans le schéma `tap` pour ne pas polluer `public`.
create schema if not exists tap;
create extension if not exists pgtap with schema tap;
create schema if not exists tests;

create or replace function tests.u(alias text) returns uuid language sql immutable as $$
  select ('00000000-0000-4000-8000-0000000000' || case alias
     when 'owner_a' then 'a1' when 'editor_a' then 'a2' when 'viewer_a' then 'a3'
     when 'owner_b' then 'b1' when 'multi' then 'c1' when 'idle' then 'd1' when 'family' then 'f1' end)::uuid
$$;

create or replace function tests.set_ctx(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text,''), true);
  perform set_config('request.jwt.claims',
    case when p_user is null then '{}' else json_build_object('sub',p_user,'role','authenticated')::text end, true);
end $$;

-- Nombre de lignes visibles pour (rôle, utilisateur). Lève l'erreur d'origine si la requête échoue.
create or replace function tests.count_as(p_role text, p_user uuid, p_query text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  perform tests.set_ctx(p_user);
  execute format('set local role %I', p_role);
  begin
    execute 'select count(*) from (' || p_query || ') q' into n;
  exception when others then reset role; raise;
  end;
  reset role;
  return n;
end $$;

-- Exécute un ordre en tant que (rôle, utilisateur). Retourne 'OK:<lignes>' ou le SQLSTATE.
create or replace function tests.state_as(p_role text, p_user uuid, p_stmt text) returns text
language plpgsql as $$
declare n bigint;
begin
  perform tests.set_ctx(p_user);
  execute format('set local role %I', p_role);
  begin
    execute p_stmt;
    get diagnostics n = row_count;
    reset role;
    return 'OK:' || n;
  exception when others then
    reset role;
    return sqlstate;
  end;
end $$;
grant usage on schema tests to anon, authenticated;
grant execute on function tests.u(text) to anon, authenticated;
