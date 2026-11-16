#!/usr/bin/env bash
# backup_restore.sh : sauvegarde + restauration SÉLECTIVE de management_next sur copie, données fictives.
#  Partie 1 : dump du seul schéma management_next -> restauration dans une base voisine déjà peuplée (Family).
#  Partie 2 : restauration sélective d'UNE organisation après incident, sans écraser les autres orgs.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; W="$POC_ROOT/work/run-$(date +%Y%m%dT%H%M%S)-$$"; mkdir -p "$W"; fail=0
ok()  { echo "PASS  $1"; }
ko()  { echo "FAIL  $1"; fail=1; }
eq()  { if [ -z "$2" ] || [ -z "$3" ] && [ "$2" != "0" ]; then ko "$1 (valeur vide : test invalide, attendu '$2', obtenu '$3')"; elif [ "$2" = "$3" ]; then ok "$1 [$2]"; else ko "$1 (attendu '$2', obtenu '$3')"; fi; }
dt()  { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f s", b-a}'; }
SRC=mgmt_poc_br_src; DST=mgmt_poc_br_dst
ORG_A=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa; ORG_B=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb

echo "== Préparation : source fictive (graine + 40 000 actions) =="
bash $S/create_db.sh $SRC >/dev/null; bash $S/migrate.sh $SRC >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -d $SRC -f $POC_ROOT/sql/seed_synthetic.sql
t0=$(now); psql -X -v ON_ERROR_STOP=1 -q -d $SRC -f $POC_ROOT/sql/seed_bulk.sql; t1=$(now)
echo "volumes : $(q $SRC -c "select (select count(*) from management_next.organizations)||' orgs, '||(select count(*) from management_next.projects)||' projets, '||(select count(*) from management_next.actions)||' actions, '||(select count(*) from management_next.memberships)||' appartenances'") (génération $(dt $t0 $t1))"
SRC_DDL=$($S/fp.sh $SRC mn_ddl); SRC_DATA=$($S/fp.sh $SRC mn_data)

echo; echo "== Partie 1 : sauvegarde du schéma management_next seul, restauration sélective sur copie =="
t0=$(now); pg_dump -h $POC_SOCK -p $POC_PORT -U postgres -d $SRC -n management_next -Fc -f $W/mn.dump; t1=$(now)
echo "sauvegarde : $(dt $t0 $t1), $(du -h $W/mn.dump | cut -f1) (format custom)"
echo "contenu de l'archive : $(pg_restore -l $W/mn.dump | grep -cE ' TABLE DATA ') tables de données ; schémas : $(pg_restore -l $W/mn.dump | grep -E ' SCHEMA ' | awk '{print $NF}' | sort -u | tr '\n' ' ')"
# Cible : un voisin DÉJÀ en service (Family + comptes Auth existants, données propres)
bash $S/create_db.sh $DST >/dev/null
q $SRC -c "copy (select id,email,created_at from auth.users where id in (select user_id from management_next.product_access)) to stdout" > $W/auth_ids.tsv
q $DST -c "copy auth.users(id,email,created_at) from stdin" < $W/auth_ids.tsv
q $DST -c "insert into auth.users(id,email) values ('00000000-0000-4000-8000-0000000000f1','family_only@example.invalid');
 insert into public.family_notes values ('f0f0f0f0-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000000f1','DST note family_only'),('f0f0f0f0-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000000a1','DST note owner_a'),('f0f0f0f0-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','DST autre note');
 insert into public.identity_profiles values ('00000000-0000-4000-8000-0000000000f1','F DST'),('00000000-0000-4000-8000-0000000000a1','A DST');"
F_BEFORE=$($S/fp.sh $DST public); echo "voisin AVANT restauration : $F_BEFORE"
# pg_restore -n ne recrée PAS le schéma lui-même : pré-créer un schéma vide (ses privilèges/objets viennent de l'archive).
q $DST -c "create schema management_next"
t0=$(now); pg_restore -h $POC_SOCK -p $POC_PORT -U postgres -d $DST --exit-on-error --single-transaction -n management_next $W/mn.dump; rc=$?; t1=$(now)
[ $rc -eq 0 ] && ok "pg_restore sélectif (transaction unique) rc=0 en $(dt $t0 $t1)" || ko "pg_restore rc=$rc"
eq "AVANT étape post-restauration : l'ACL du schéma est perdue (constat, échec fermé)" "f" "$(q $DST -c "select has_schema_privilege('authenticated','management_next','USAGE')")"
psql -X -v ON_ERROR_STOP=1 -q -d $DST -f $POC_ROOT/sql/restore/post_restore.sql && ok "étape post-restauration appliquée (sql/restore/post_restore.sql)" || ko "post_restore en erreur"
eq "DDL management_next restauré = source (tables, triggers, fonctions, policies, ACL)" "$SRC_DDL" "$($S/fp.sh $DST mn_ddl)"
eq "données restaurées = source (orgs, membres, projets, actions, accès produit)" "$SRC_DATA" "$($S/fp.sh $DST mn_data)"
eq "voisin (Family/Identity/Auth) inchangé par la restauration" "$F_BEFORE" "$($S/fp.sh $DST public)"
eq "lignes actions restaurées" "$(q $SRC -c 'select count(*) from management_next.actions')" "$(q $DST -c 'select count(*) from management_next.actions')"
eq "RLS activée sur les 6 tables après restauration" "6" "$(q $DST -c "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='management_next' and c.relkind='r' and c.relrowsecurity")"
CNT="select (select count(*) from pg_policies where schemaname='management_next')||'/'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='management_next' and not tgisinternal)"
eq "policies / triggers restaurés" "$(q $SRC -c "$CNT")" "$(q $DST -c "$CNT")"
q $DST -c "grant select on management_next.actions to anon" >/dev/null
[ "$SRC_DDL" != "$($S/fp.sh $DST mn_ddl)" ] && ok "témoin de sensibilité : un GRANT parasite à anon est détecté par l'empreinte" || ko "témoin : altération non détectée"
q $DST -c "revoke select on management_next.actions from anon" >/dev/null
eq "témoin retiré : empreinte de nouveau identique" "$SRC_DDL" "$($S/fp.sh $DST mn_ddl)"
echo "-- Droits après restauration : suites pgTAP 01-04 rejouées sur la copie restaurée --"
bash $S/run_tests.sh $DST > $W/prove_dst.log 2>&1; prc=$?
grep -E "^(All tests successful|Files=|Result:)|not ok" $W/prove_dst.log | sed 's/^/   /'
[ $prc -eq 0 ] && ok "suites pgTAP 01-04 sur copie restaurée" || ko "suites pgTAP en échec sur la copie restaurée"

echo; echo "== Partie 2 : restauration sélective d'UNE organisation après incident =="
ORG_1=20000000-0000-4000-8000-000000000001; PRJ_1=30000000-0000-4000-0001-000000000001
export_org() { # $1=org
  for t in organizations:"id='$1'" memberships:"org_id='$1'" projects:"org_id='$1'" actions:"org_id='$1'"; do
    n=${t%%:*}; w=${t#*:}; q $DST -c "copy (select * from management_next.$n where $w order by 1) to stdout with (format csv)" > $W/org_${1:0:8}_$n.csv
  done
}
hash_org() { q $DST -c "select md5(coalesce((select string_agg(x,'|' order by x) from (select o::text x from management_next.organizations o where id='$1' union all select m::text from management_next.memberships m where org_id='$1' union all select p::text from management_next.projects p where org_id='$1' union all select a::text from management_next.actions a where org_id='$1') s),''))" | cut -c1-12; }
hash_others() { q $DST -c "select md5(coalesce((select string_agg(x,'|' order by x) from (select o::text x from management_next.organizations o where id<>'$1' union all select m::text from management_next.memberships m where org_id<>'$1' union all select p::text from management_next.projects p where org_id<>'$1' union all select a::text from management_next.actions a where org_id<>'$1') s),''))" | cut -c1-12; }
restore_org() { # $1=org $2=normal|replica
  local pre=""; [ "$2" = "replica" ] && pre="set local session_replication_role = replica;"
  psql -X -v ON_ERROR_STOP=1 -q -d $DST <<SQL 2>&1
begin;
$pre
\copy management_next.organizations from '$W/org_${1:0:8}_organizations.csv' with (format csv)
\copy management_next.memberships from '$W/org_${1:0:8}_memberships.csv' with (format csv)
\copy management_next.projects from '$W/org_${1:0:8}_projects.csv' with (format csv)
\copy management_next.actions from '$W/org_${1:0:8}_actions.csv' with (format csv)
commit;
SQL
}
orphans() { q $DST -c "select count(*) from management_next.actions a left join management_next.projects p on p.id=a.project_id and p.org_id=a.org_id where p.id is null"; }

echo "-- 2a. org A (chemin normal, triggers actifs) --"
export_org $ORG_A
echo "export org A : $(wc -l < $W/org_aaaaaaaa_organizations.csv) org, $(wc -l < $W/org_aaaaaaaa_memberships.csv) membres, $(wc -l < $W/org_aaaaaaaa_projects.csv) projets, $(wc -l < $W/org_aaaaaaaa_actions.csv) actions"
HA0=$(hash_org $ORG_A)
q $DST -c "insert into management_next.projects(id,org_id,name,created_by) values ('b1b1b1b1-0000-4000-8000-0000000000aa','$ORG_B','Projet créé après la sauvegarde','00000000-0000-4000-8000-0000000000b1');
           update management_next.actions set status='done' where id='b1b1b1b1-0000-4000-8001-000000000001'" >/dev/null
HB0=$(hash_others $ORG_A); echo "org A avant incident : $HA0 | autres orgs (avec changements post-sauvegarde) : $HB0"
q $DST -c "delete from management_next.actions where org_id='$ORG_A'; delete from management_next.projects where org_id='$ORG_A'; delete from management_next.memberships where org_id='$ORG_A'; delete from management_next.organizations where id='$ORG_A'" >/dev/null
eq "incident : org A entièrement supprimée (actions restantes)" "0" "$(q $DST -c "select count(*) from management_next.actions where org_id='$ORG_A'")"
t0=$(now); restore_org $ORG_A normal; rc=$?; t1=$(now)
[ $rc -eq 0 ] && ok "restauration org A en transaction unique en $(dt $t0 $t1)" || ko "restauration org A rc=$rc"
eq "org A restaurée à l'identique (empreinte des 4 tables)" "$HA0" "$(hash_org $ORG_A)"
eq "autres orgs NON écrasées (changements post-sauvegarde conservés)" "$HB0" "$(hash_others $ORG_A)"
eq "projet créé après la sauvegarde toujours présent" "1" "$(q $DST -c "select count(*) from management_next.projects where name='Projet créé après la sauvegarde'")"
eq "action terminée avant sauvegarde : done_at restauré tel quel" "2026-01-02 10:00:00+00" "$(q $DST -c "select done_at from management_next.actions where id='a1a1a1a1-0000-4000-8001-000000000002'")"

echo "-- 2b. org avec projet ARCHIVÉ : la garde MN006 bloque aussi l'administration --"
q $DST -c "update management_next.projects set status='archived' where id='$PRJ_1'" >/dev/null
export_org $ORG_1; H10=$(hash_org $ORG_1); HO0=$(hash_others $ORG_1)
echo "export org bulk 1 : $(wc -l < $W/org_20000000_actions.csv) actions dont $(q $DST -c "select count(*) from management_next.actions where project_id='$PRJ_1'") dans un projet archivé"
out=$(q $DST -c "delete from management_next.actions where org_id='$ORG_1'" 2>&1)
echo "$out" | grep -q MN006 && ok "même l'administration ne peut pas vider un projet archivé sans mode de restauration (MN006)" || ko "suppression en projet archivé non bloquée: $out"
q $DST -c "begin; set local session_replication_role = replica; delete from management_next.actions where org_id='$ORG_1'; delete from management_next.projects where org_id='$ORG_1'; delete from management_next.memberships where org_id='$ORG_1'; delete from management_next.organizations where id='$ORG_1'; commit;" >/dev/null
eq "incident : org bulk 1 supprimée (mode administration)" "0" "$(q $DST -c "select count(*) from management_next.actions where org_id='$ORG_1'")"
out=$(restore_org $ORG_1 normal); echo "$out" | grep -q MN006 && ok "restauration en mode NORMAL refusée par MN006 (constat documenté)" || ko "restauration normale non refusée: $out"
eq "échec atomique : rien n'a été restauré partiellement" "0" "$(q $DST -c "select count(*) from management_next.organizations where id='$ORG_1'")"
t0=$(now); restore_org $ORG_1 replica; rc=$?; t1=$(now)
[ $rc -eq 0 ] && ok "restauration en mode administration (session_replication_role=replica, transaction unique) en $(dt $t0 $t1)" || ko "restauration replica rc=$rc"
eq "org bulk 1 restaurée à l'identique, projet archivé inclus" "$H10" "$(hash_org $ORG_1)"
eq "autres orgs non écrasées" "$HO0" "$(hash_others $ORG_1)"
eq "contrôle d'intégrité post-restauration : 0 action orpheline (FK non vérifiée en mode replica)" "0" "$(orphans)"
eq "le projet restauré est toujours archivé" "archived" "$(q $DST -c "select status from management_next.projects where id='$PRJ_1'")"
echo "-- Droits après restauration sélective (oracle indépendant, par utilisateur) --"
{ echo "begin; set local search_path = tap, public;"; echo "select plan(15);"
for u in owner_a editor_a viewer_a owner_b multi idle; do for t in projects actions; do
echo "select is(tests.count_as('authenticated', tests.u('$u'), 'select 1 from management_next.$t'), (select count(*) from management_next.$t x where exists (select 1 from management_next.memberships m join management_next.product_access p using (user_id) where m.org_id = x.org_id and m.user_id = tests.u('$u'))), '$u voit exactement les $t de ses organisations');"
done; done
cat <<'SQL'
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','x')$q$), '42501', 'viewer_a toujours en lecture seule sur A restaurée');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','x')$q$), 'OK:1', 'editor_a écrit toujours dans A restaurée');
select is(tests.count_as('authenticated', tests.u('family'), 'select 1 from management_next.organizations'), 0::bigint, 'family_only : toujours 0 organisation après restauration');
select * from finish(); rollback;
SQL
} > $W/90_post_restore.test.sql
pg_prove -h $POC_SOCK -p $POC_PORT -U postgres -d $DST --verbose $W/90_post_restore.test.sql > $W/prove_orgA.log 2>&1; prc=$?
grep -E "not ok|^All tests|Result:|Failed|planned" $W/prove_orgA.log | sed 's/^/   /'
[ $prc -eq 0 ] && ok "droits vérifiés après restaurations sélectives" || ko "droits en échec après restaurations sélectives"
echo; [ $fail -eq 0 ] && echo "RÉSULTAT sauvegarde/restauration : PASS" || echo "RÉSULTAT sauvegarde/restauration : FAIL"
exit $fail
