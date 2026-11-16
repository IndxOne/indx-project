#!/usr/bin/env bash
# open_risks_probe.sh : sonde les trous SUSPECTÉS du schéma V0. Constate, ne « réussit » pas : chaque ligne = comportement observé.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; DB=mgmt_poc_probe
bash $S/create_db.sh $DB >/dev/null; bash $S/migrate.sh $DB >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -d $DB -f $POC_ROOT/sql/seed_synthetic.sql; psql -X -q -d $DB -f $POC_ROOT/tests/00_helpers.sql >/dev/null
OA=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
st() { q $DB -c "select tests.state_as('authenticated', tests.u('$1'), \$\$$2\$\$)"; }
echo "R1 [corrigé en 0004] dernier owner se rétrograde lui-même (attendu MN005) : $(st owner_a "update management_next.memberships set role='viewer' where user_id=auth.uid() and org_id='$OA'")"
echo "   propriétaires restants de l'org A : $(q $DB -c "select count(*) from management_next.memberships where org_id='$OA' and role='owner'")  -> organisation SANS owner si 0"
echo "R2 [mitigé : non bloquant par conception] suppression du compte Auth du dernier owner (cascade, sans JWT) :"
q $DB -c "delete from auth.users where id=tests.u('owner_a')" >/dev/null
echo "   propriétaires de A : $(q $DB -c "select count(*) from management_next.memberships where org_id='$OA' and role='owner'") ; membres restants : $(q $DB -c "select count(*) from management_next.memberships where org_id='$OA'") ; organisation toujours en base : $(q $DB -c "select count(*) from management_next.organizations where id='$OA'")  -> org orpheline, aucun owner pour la gérer"
echo "R3 sonde d'un UUID par un owner (oracle limité) (ajout de membre) :"
echo "   UUID inexistant            -> $(st owner_b "insert into management_next.memberships(org_id,user_id,role) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','99999999-9999-4999-8999-999999999999','viewer')")"
echo "   compte Auth sans accès     -> $(st owner_b "insert into management_next.memberships(org_id,user_id,role) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',tests.u('family'),'viewer')")"
echo "   compte avec accès produit  -> $(st owner_b "insert into management_next.memberships(org_id,user_id,role) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',tests.u('idle'),'viewer')")  (2 réponses distinctes seulement : MN003 = « pas d'accès produit OU compte inexistant », OK = accès produit ; l'existence d'un compte n'est PAS révélée, seul le droit produit l'est — et l'ajout réussi a un effet visible)"
echo "R4 [corrigé en 0004] ajout d'action dans un projet archivé (attendu MN006) :"
q $DB -c "update management_next.projects set status='archived' where id='b1b1b1b1-0000-4000-8000-000000000001'" >/dev/null
echo "   owner_b -> $(st owner_b "insert into management_next.actions(org_id,project_id,title) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','b1b1b1b1-0000-4000-8000-000000000001','dans archivé')")"
echo "R5 contournement des invariants par le superuser local (session_replication_role=replica) :"
echo "   $(q $DB -c "begin; set local session_replication_role=replica; update management_next.actions set status='open', done_at=null where id='a1a1a1a1-0000-4000-8001-000000000002'; select 'réouverture acceptée (triggers désactivés)'; rollback;" | head -1)  -> limite inhérente à Postgres, à interdire côté rôles cloud"
echo "R6 SELECT sur schema_migrations par authenticated : $(st owner_b "select 1 from management_next.schema_migrations")"
echo "R7 le rôle service_role (BYPASSRLS) : aucun privilège de table accordé -> $(q $DB -c "select count(*) from information_schema.role_table_grants where table_schema='management_next' and grantee='service_role'") privilège ; en cloud il contourne la RLS s'il reçoit des GRANT (Edge Functions)"
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $DB
