#!/usr/bin/env bash
# guard_negative.sh : prouve que le POC REFUSE de s'exécuter contre une cible non locale / non marquée.
cd "$(dirname "$0")"
fail=0
expect_refus() { # desc, commande...
  local desc="$1"; shift
  out=$("$@" 2>&1); rc=$?
  if [ $rc -eq 90 ] && echo "$out" | grep -q '^REFUS'; then echo "PASS  refusé : $desc  -> ${out##*$'\n'}"; else echo "FAIL  non refusé : $desc (rc=$rc) $out"; fail=1; fi
}
expect_refus "PGHOST distant (db.example.supabase.co)"    env PGHOST=db.example.supabase.co ./migrate.sh mgmt_poc_main
expect_refus "PGHOST=127.0.0.1 (TCP)"                      env PGHOST=127.0.0.1 ./migrate.sh mgmt_poc_main
expect_refus "PGPORT=5432 (port Postgres standard)"        env PGPORT=5432 ./migrate.sh mgmt_poc_main
expect_refus "DATABASE_URL défini"                         env DATABASE_URL=postgres://u:p@db.example.supabase.co:5432/postgres ./migrate.sh mgmt_poc_main
expect_refus "SUPABASE_DB_URL défini"                      env SUPABASE_DB_URL=postgresql://x ./migrate.sh mgmt_poc_main
expect_refus "PGPASSWORD défini"                           env PGPASSWORD=secret ./migrate.sh mgmt_poc_main
expect_refus "PGUSER=supabase_admin"                       env PGUSER=supabase_admin ./migrate.sh mgmt_poc_main
expect_refus "base hors convention (postgres)"             ./migrate.sh postgres
expect_refus "base hors convention (hub)"                  ./migrate.sh indxone_hub
# base POC valide en nom mais SANS sentinelle
source ./lib.sh; set +e
dropdb --if-exists -h "$POC_SOCK" -p "$POC_PORT" -U postgres mgmt_poc_nosentinel; createdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres mgmt_poc_nosentinel
expect_refus "base mgmt_poc_* sans sentinelle"             ./migrate.sh mgmt_poc_nosentinel
# Filet SQL (2e ligne de défense) : la migration elle-même refuse sans sentinelle, même lancée à la main
out=$(psql -X -q -v ON_ERROR_STOP=1 -h "$POC_SOCK" -p "$POC_PORT" -U postgres -d mgmt_poc_nosentinel -f ../sql/migrations/20261116000001_mn_schema.sql 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "REFUS: cible non locale POC (sentinelle absente)"; then echo "PASS  refusé : migration SQL lancée à la main sur base sans sentinelle -> $(echo "$out" | grep -o 'REFUS: cible non locale POC (sentinelle absente)' | head -1)"; else echo "FAIL  la migration SQL s'est exécutée sans sentinelle: $out"; fail=1; fi
n=$(psql -X -qAt -h "$POC_SOCK" -p "$POC_PORT" -U postgres -d mgmt_poc_nosentinel -c "select count(*) from pg_namespace where nspname='management_next'")
[ "$n" = "0" ] && echo "PASS  aucun schéma management_next créé dans la base refusée" || { echo "FAIL  schéma créé malgré le refus"; fail=1; }
dropdb --if-exists -h "$POC_SOCK" -p "$POC_PORT" -U postgres mgmt_poc_nosentinel
exit $fail
