#!/usr/bin/env bash
# migration_independence.sh : prouve que les migrations management_next sont indépendantes (du legacy,
# des autres produits, de l'ordre d'application), idempotentes, réversibles, et détectent le drift.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; fail=0
ok()  { echo "PASS  $1"; }
ko()  { echo "FAIL  $1"; fail=1; }
eq()  { if [ -z "$2" ] || [ -z "$3" ] && [ "$2" != "0" ]; then ko "$1 (valeur vide : test invalide, attendu '$2', obtenu '$3')"; elif [ "$2" = "$3" ]; then ok "$1 [$2]"; else ko "$1 (attendu '$2', obtenu '$3')"; fi; }
FAM_SEED="insert into auth.users(id,email) values ('00000000-0000-4000-8000-0000000000f1','fam@example.invalid') on conflict do nothing;
          insert into public.family_notes values ('f0f0f0f0-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000000f1','n') on conflict do nothing;
          insert into public.identity_profiles values ('00000000-0000-4000-8000-0000000000f1','F') on conflict do nothing;"
A=mgmt_poc_mi_a; B=mgmt_poc_mi_b

echo "== 1. Produit voisin d'abord, puis management_next =="
bash $S/create_db.sh $A >/dev/null; q $A -c "$FAM_SEED" >/dev/null
F0=$($S/fp.sh $A public); echo "empreinte public+auth AVANT : $F0"
bash $S/migrate.sh $A | sed 's/^/   /'
F1=$($S/fp.sh $A public); eq "public+auth inchangés par la migration (DDL, ACL, policies, données)" "$F0" "$F1"
M1=$($S/fp.sh $A mn_ddl); echo "empreinte DDL management_next : $M1"

echo "== 2. Idempotence =="
out=$(bash $S/migrate.sh $A); echo "$out" | grep -c "checksum identique" | xargs -I{} echo "   {} migrations ignorées par le registre"
eq "re-run du runner : DDL identique" "$M1" "$($S/fp.sh $A mn_ddl)"
for i in 1 2; do for f in $POC_ROOT/sql/migrations/*.sql; do psql -X -v ON_ERROR_STOP=1 -q -d $A -f $f >/dev/null 2>&1 || ko "ré-exécution directe de $(basename $f) (passe $i) en erreur"; done; done
eq "ré-exécution directe ×2 de chaque fichier : DDL identique" "$M1" "$($S/fp.sh $A mn_ddl)"
eq "public+auth toujours inchangés" "$F0" "$($S/fp.sh $A public)"
eq "registre : 4 migrations" "4" "$(q $A -c 'select count(*) from management_next.schema_migrations')"

echo "== 3. Réversibilité (down puis up) =="
psql -X -v ON_ERROR_STOP=1 -q -d $A -f $POC_ROOT/sql/down/99_mn_drop.sql >/dev/null 2>&1
eq "schéma management_next supprimé" "0" "$(q $A -c "select count(*) from pg_namespace where nspname='management_next'")"
eq "public+auth inchangés après DOWN" "$F0" "$($S/fp.sh $A public)"
bash $S/migrate.sh $A >/dev/null
eq "UP après DOWN : DDL identique au premier UP" "$M1" "$($S/fp.sh $A mn_ddl)"

echo "== 3b. Retour arrière de la SEULE migration 0004 (0001-0003 conservées) =="
C=mgmt_poc_mi_c
bash $S/create_db.sh $C >/dev/null; FC0=$($S/fp.sh $C public); bash $S/migrate.sh $C 20261116000003 >/dev/null
M3=$($S/fp.sh $C mn_ddl); bash $S/migrate.sh $C >/dev/null; M4=$($S/fp.sh $C mn_ddl)
[ "$M3" != "$M4" ] && ok "0004 modifie bien le schéma ($M3 -> $M4)" || ko "0004 sans effet sur le schéma"
eq "0001-0004 appliquées par le runner = empreinte du premier UP complet" "$M1" "$M4"
psql -X -v ON_ERROR_STOP=1 -q -d $C -f $POC_ROOT/sql/down/98_mn_revert_0004.sql >/dev/null 2>&1
eq "après retour arrière de 0004 : DDL identique à l'état 0001-0003" "$M3" "$($S/fp.sh $C mn_ddl)"
eq "registre : 3 migrations après retour arrière" "3" "$(q $C -c 'select count(*) from management_next.schema_migrations')"
psql -X -v ON_ERROR_STOP=1 -q -d $C -f $POC_ROOT/sql/down/98_mn_revert_0004.sql >/dev/null 2>&1 && ok "retour arrière idempotent (2e exécution sans erreur)" || ko "retour arrière non idempotent"
bash $S/migrate.sh $C >/dev/null
eq "ré-application de 0004 après retour arrière : DDL identique" "$M4" "$($S/fp.sh $C mn_ddl)"
eq "public+auth inchangés par ces allers-retours" "$FC0" "$($S/fp.sh $C public)"
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $C

echo "== 4. Détection de drift =="
q $A -c "update management_next.schema_migrations set checksum='altered' where name like '%0002%'" >/dev/null
out=$(bash $S/migrate.sh $A 2>&1); rc=$?
[ $rc -eq 90 ] && echo "$out" | grep -q DRIFT && ok "checksum altéré : exécution refusée -> $(echo "$out" | grep DRIFT)" || ko "drift non détecté (rc=$rc)"
q $A -c "update management_next.schema_migrations set checksum=(select checksum from management_next.schema_migrations where name like '%0001%') where name like '%0002%'" >/dev/null
q $A -c "delete from management_next.schema_migrations where name like '%0002%'" >/dev/null; bash $S/migrate.sh $A >/dev/null
eq "retour à l'état sain après correction du registre" "$M1" "$($S/fp.sh $A mn_ddl)"

echo "== 5. Indépendance vis-à-vis du legacy (aucune des 61 migrations / tables projets_*) =="
n=$(grep -rnE "projets_|supabase_migrations|sync_snapshots|hub_settings" $POC_ROOT/sql/migrations | wc -l)
eq "références legacy dans les migrations" "0" "$n"
n=$(grep -rhoE "public\.[a-z_]+" $POC_ROOT/sql/migrations | sort -u | grep -v '^public.__poc_sentinel$' | wc -l)
eq "références à public.* hors sentinelle de garde" "0" "$n"
eq "tables legacy présentes dans la base d'essai" "0" "$(q $A -c "select count(*) from pg_tables where tablename like 'projets\\_%'")"
deps=$(q $A -c "select coalesce(string_agg(distinct confrelid::regclass::text, ','),'') from pg_constraint where contype='f' and connamespace='management_next'::regnamespace and confrelid::regclass::text not like 'management_next.%'")
eq "seule dépendance externe des clés étrangères" "auth.users" "$deps"

echo "== 6. Indépendance de l'ordre / d'un autre produit =="
bash $S/create_db.sh $B --no-family >/dev/null
bash $S/migrate.sh $B >/dev/null
eq "management_next migré SANS produit voisin : DDL identique" "$M1" "$($S/fp.sh $B mn_ddl)"
psql -X -v ON_ERROR_STOP=1 -q -d $B -f $POC_ROOT/sql/stubs/10_family_product_stub.sql >/dev/null
q $B -c "create table public.other_product_migration_61 (id int primary key, note text); alter table public.other_product_migration_61 enable row level security;" >/dev/null
eq "arrivée d'un autre produit/migration APRÈS : DDL management_next inchangé" "$M1" "$($S/fp.sh $B mn_ddl)"
q $A -c "create table public.other_product_migration_61 (id int primary key, note text)" >/dev/null
eq "idem sur l'ordre inverse (voisin d'abord, nouvelle table après)" "$M1" "$($S/fp.sh $A mn_ddl)"
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $B; dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $A
echo; [ $fail -eq 0 ] && echo "RÉSULTAT migrations indépendantes : PASS" || echo "RÉSULTAT migrations indépendantes : FAIL"
exit $fail
