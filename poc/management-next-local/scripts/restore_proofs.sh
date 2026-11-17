#!/usr/bin/env bash
# restore_proofs.sh : scénarios adverses de la restauration sélective par étapes (contraintes actives).
# Sécurité / intégrité / concurrence / reprise. Données fictives, base jetable.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; W="$POC_ROOT/work/rst-$(date +%Y%m%dT%H%M%S)-$$"; mkdir -p "$W"; fail=0; DB=mgmt_poc_rst
ok()  { echo "PASS  $1"; }
ko()  { echo "FAIL  $1"; fail=1; }
eq()  { if [ -z "$2" ] || [ -z "$3" ] && [ "$2" != "0" ]; then ko "$1 (valeur vide : test invalide, attendu '$2', obtenu '$3')"; elif [ "$2" = "$3" ]; then ok "$1 [$2]"; else ko "$1 (attendu '$2', obtenu '$3')"; fi; }
A=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa; B=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
PA2=a1a1a1a1-0000-4000-8000-000000000002
hash_org() { q $DB -c "select md5(coalesce((select string_agg(x,'|' order by x) from (select o::text x from management_next.organizations o where id='$1' union all select m::text from management_next.memberships m where org_id='$1' union all select p::text from management_next.projects p where org_id='$1' union all select a::text from management_next.actions a where org_id='$1') s),''))" | cut -c1-12; }
cnt() { q $DB -c "select (select count(*) from management_next.organizations where id='$1')||'/'||(select count(*) from management_next.memberships where org_id='$1')||'/'||(select count(*) from management_next.projects where org_id='$1')||'/'||(select count(*) from management_next.actions where org_id='$1')"; }
incident() { q $DB -c "begin; update management_next.projects set status='active' where org_id='$1'; delete from management_next.actions where org_id='$1'; delete from management_next.projects where org_id='$1'; delete from management_next.memberships where org_id='$1'; delete from management_next.organizations where id='$1'; commit;" >/dev/null; }
errcode() { echo "$1" | grep -oE 'MN00[0-9]|23503|23514|23505' | head -1; }

bash $S/create_db.sh $DB >/dev/null; bash $S/migrate.sh $DB >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -d $DB -f $POC_ROOT/sql/seed_synthetic.sql; psql -X -q -d $DB -f $POC_ROOT/tests/00_helpers.sql >/dev/null
q $DB -c "update management_next.projects set status='archived' where id='$PA2'" >/dev/null     # A2 archivé (porte l'action AA3)
bash $S/export_org.sh $DB $A $W/A >/dev/null; bash $S/export_org.sh $DB $B $W/B >/dev/null
HA=$(hash_org $A); HB=$(hash_org $B); CA=$(cnt $A)
echo "référence : org A $HA ($CA org/membres/projets/actions, dont 1 projet archivé), org B $HB"

echo "== SÉCURITÉ =="
out=$(PGHOST=db.example.supabase.co bash $S/restore_org.sh $DB $A $W/A 2>&1); [ $? -eq 90 ] && ok "restauration refusée sur hôte distant ($(echo "$out" | tail -1 | cut -c1-70))" || ko "hôte distant non refusé"
out=$(bash $S/restore_org.sh postgres $A $W/A 2>&1); [ $? -eq 90 ] && ok "restauration refusée sur base hors convention" || ko "base hors convention non refusée"
out=$(bash $S/restore_org.sh $DB "$A'; drop schema management_next cascade; --" $W/A 2>&1); [ $? -eq 90 ] && ok "injection via l'uuid d'organisation refusée" || ko "uuid non validé"
eq "schéma intact après les tentatives d'injection" "1" "$(q $DB -c "select count(*) from pg_namespace where nspname='management_next'")"
# Mode de session non 'origin' (réglage de base hérité par toute nouvelle connexion) : la restauration doit refuser (MN008)
incident $A
q $DB -c "alter database $DB set session_replication_role = replica" >/dev/null
out=$(bash $S/restore_org.sh $DB $A $W/A 2>&1)
q $DB -c "alter database $DB reset session_replication_role" >/dev/null
[ "$(errcode "$out")" = "MN008" ] && ok "restauration refusée si la base impose session_replication_role=replica (MN008)" || ko "mode replica non refusé: $out"
eq "rien restauré par la tentative en mode replica" "0/0/0/0" "$(cnt $A)"
n=$(grep -nE "session_replication_role|disable trigger|NOT VALID|set constraints" $S/restore_org.sh $S/export_org.sh | grep -vE "current_setting\('session_replication_role'\) <> 'origin'|session_replication_role.*interdite|mode de session|^.*#" | wc -l)
eq "procédure de restauration : aucune désactivation de trigger/contrainte (analyse statique)" "0" "$n"

echo "== INTÉGRITÉ =="
bash $S/restore_org.sh $DB $A $W/A; rc=$?
[ $rc -eq 0 ] && ok "restauration nominale org A (projet archivé inclus)" || ko "restauration nominale rc=$rc"
eq "org A identique à la sauvegarde" "$HA" "$(hash_org $A)"
eq "projet A2 de nouveau archivé" "archived" "$(q $DB -c "select status from management_next.projects where id='$PA2'")"
eq "org B non touchée" "$HB" "$(hash_org $B)"
out=$(bash $S/restore_org.sh $DB $A $W/A 2>&1); eq "restauration en double refusée (MN007)" "MN007" "$(errcode "$out")"
eq "refus du doublon : aucune modification" "$HA" "$(hash_org $A)"
# Sauvegarde corrompue 1 : action déclarée dans B mais rattachée à un projet de A (pivot inter-org)
incident $A; mkdir -p $W/bad1; cp $W/A/*.csv $W/bad1/
python3 -I - "$W/bad1/actions.csv" "$B" <<'PY'
import csv,sys
f,b=sys.argv[1],sys.argv[2]; rows=list(csv.reader(open(f))); rows[0][1]=b; csv.writer(open(f,"w",newline="")).writerows(rows)
PY
out=$(bash $S/restore_org.sh $DB $A $W/bad1 2>&1); eq "sauvegarde corrompue (pivot inter-org) : refusée par la clé étrangère composite" "23503" "$(errcode "$out")"
eq "échec atomique : rien restauré, org B inchangée" "0/0/0/0|$HB" "$(cnt $A)|$(hash_org $B)"
# Sauvegarde corrompue 2 : action ouverte portant un done_at
mkdir -p $W/bad2; cp $W/A/*.csv $W/bad2/
python3 -I - "$W/bad2/actions.csv" <<'PY'
import csv,sys
f=sys.argv[1]; rows=list(csv.reader(open(f)))
for r in rows:
    if r[4]=="open": r[5]="2026-01-01 00:00:00+00"; break
csv.writer(open(f,"w",newline="")).writerows(rows)
PY
out=$(bash $S/restore_org.sh $DB $A $W/bad2 2>&1); eq "sauvegarde corrompue (open + done_at) : refusée par la contrainte CHECK" "23514" "$(errcode "$out")"
eq "échec atomique" "0/0/0/0" "$(cnt $A)"
# Sauvegarde corrompue 3 : tentative d'élévation (membre ajouté sans accès produit)
mkdir -p $W/bad3; cp $W/A/*.csv $W/bad3/
echo "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa,00000000-0000-4000-8000-0000000000f1,owner,2026-01-01 00:00:00+00" >> $W/bad3/memberships.csv
out=$(bash $S/restore_org.sh $DB $A $W/bad3 2>&1); eq "membre sans accès produit (compte Family) : refusé (MN003)" "MN003" "$(errcode "$out")"
eq "échec atomique" "0/0/0/0" "$(cnt $A)"

echo "== REPRISE APRÈS ÉCHEC (retour arrière) =="
q $DB -c "delete from management_next.product_access where user_id='00000000-0000-4000-8000-0000000000a2'" >/dev/null
out=$(bash $S/restore_org.sh $DB $A $W/A 2>&1); eq "précondition manquante (accès produit d'un membre) : refus (MN003)" "MN003" "$(errcode "$out")"
eq "rien d'écrit par l'échec" "0/0/0/0" "$(cnt $A)"
q $DB -c "insert into management_next.product_access(user_id) values ('00000000-0000-4000-8000-0000000000a2')" >/dev/null
bash $S/restore_org.sh $DB $A $W/A >/dev/null 2>&1; eq "précondition rétablie puis reprise : org A identique" "$HA" "$(hash_org $A)"

echo "== CONCURRENCE =="
incident $A
( RESTORE_HOLD_SECONDS=3 bash $S/restore_org.sh $DB $A $W/A > $W/c1.log 2>&1; echo $? > $W/c1.rc ) &
sleep 1
( bash $S/restore_org.sh $DB $A $W/A > $W/c2.log 2>&1; echo $? > $W/c2.rc ) &
wait
r1=$(cat $W/c1.rc); r2=$(cat $W/c2.rc)
[ "$r1" = "0" ] && [ "$r2" != "0" ] && ok "deux restaurations simultanées de la même org : une réussit, l'autre est sérialisée puis refusée ($(errcode "$(cat $W/c2.log)"))" || ko "concurrence : rc1=$r1 rc2=$r2"
eq "état final unique et identique à la sauvegarde" "$HA" "$(hash_org $A)"
eq "aucune ligne en double" "$CA" "$(cnt $A)"
incident $A; incident $B
( RESTORE_HOLD_SECONDS=2 bash $S/restore_org.sh $DB $A $W/A > $W/d1.log 2>&1; echo $? > $W/d1.rc ) &
( RESTORE_HOLD_SECONDS=2 bash $S/restore_org.sh $DB $B $W/B > $W/d2.log 2>&1; echo $? > $W/d2.rc ) &
t0=$(now); wait; t1=$(now)
[ "$(cat $W/d1.rc)" = "0" ] && [ "$(cat $W/d2.rc)" = "0" ] && ok "restaurations simultanées de deux orgs différentes : toutes deux réussies en $(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.1f s",b-a}') (parallèles, sans interblocage)" || ko "orgs distinctes: rc=$(cat $W/d1.rc)/$(cat $W/d2.rc)"
eq "org A identique" "$HA" "$(hash_org $A)"; eq "org B identique" "$HB" "$(hash_org $B)"

echo "== DROITS APRÈS RESTAURATION =="
bash $S/run_tests.sh $DB $POC_ROOT/tests/01_structure_privileges.test.sql $POC_ROOT/tests/02_rls_roles.test.sql $POC_ROOT/tests/03_cross_org_products.test.sql > $W/prove.log 2>&1; prc=$?
grep -E "^(All tests|Result:)|not ok" $W/prove.log | sed 's/^/   /'
echo "   (la base porte un projet archivé en A : les attentes de 02 sur A2 sont inchangées car il n'est lu qu'en lecture)"
[ $prc -eq 0 ] && ok "suites pgTAP 01-03 rejouées après restaurations (droits identiques)" || ko "suites pgTAP en échec après restaurations"
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $DB
echo; [ $fail -eq 0 ] && echo "RÉSULTAT preuves de restauration : PASS" || echo "RÉSULTAT preuves de restauration : FAIL"
exit $fail
