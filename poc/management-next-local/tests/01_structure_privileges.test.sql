begin;
set local search_path = tap, public;
select plan(18);

select has_schema('management_next', 'schéma management_next présent');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='management_next' and c.relkind='r' and not c.relrowsecurity), 0::bigint,
          'RLS activée sur toutes les tables du schéma');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='management_next' and c.relkind='r'), 6::bigint, '6 tables attendues (dont schema_migrations)');
select is((select count(*) from information_schema.role_table_grants
           where table_schema='management_next' and grantee in ('anon','PUBLIC','service_role')), 0::bigint,
          'aucun privilège de table pour anon / PUBLIC / service_role');
select ok(not has_schema_privilege('anon','management_next','USAGE'),  'anon : pas de USAGE sur le schéma');
select ok(not has_schema_privilege('public','management_next','USAGE'),'PUBLIC : pas de USAGE sur le schéma');
select ok(has_schema_privilege('authenticated','management_next','USAGE'), 'authenticated : USAGE sur le schéma');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='management_next'
             and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('public',p.oid,'EXECUTE'))),
          0::bigint, 'aucune fonction du schéma exécutable par anon ni PUBLIC');
select is((select array_agg(p.proname order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='management_next' and p.prosecdef),
          array['create_organization','mn_guard_last_owner','mn_member_requires_access','role_in']::name[],
          'inventaire exact des fonctions SECURITY DEFINER');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='management_next'
             and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), 0::bigint,
          'toutes les fonctions ont un search_path figé');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='management_next' and c.relkind in ('v','m')), 0::bigint, 'aucune vue ni vue matérialisée (surface RPC/vues : néant)');
select is((select count(*) from pg_default_acl d join pg_namespace n on n.oid=d.defaclnamespace
           where n.nspname='management_next'), 0::bigint, 'aucun privilège par défaut hérité dans le schéma');
select ok(not has_column_privilege('authenticated','management_next.projects','org_id','UPDATE'), 'org_id projet : UPDATE non accordé');
select ok(not has_column_privilege('authenticated','management_next.actions','project_id','UPDATE'), 'project_id action : UPDATE non accordé');
select ok(not has_column_privilege('authenticated','management_next.actions','done_at','UPDATE'), 'done_at : UPDATE non accordé');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$insert into management_next.organizations(name,created_by) values ('x', auth.uid())$q$),
          '42501', 'INSERT direct d''organisation refusé (passage obligé par create_organization)');
select is(tests.state_as('authenticated', tests.u('owner_a'), 'truncate management_next.actions'), '42501', 'TRUNCATE refusé');
select is((select count(*) from information_schema.tables where table_schema='storage'), 0::bigint,
          'Storage : aucun objet (non applicable en V0, schéma storage absent en local)');

select * from finish();
rollback;
