#!/usr/bin/env bash
# run_all.sh : exécute TOUTES les preuves sur l'instance locale isolée et archive les sorties dans evidence/.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; E="$POC_ROOT/evidence"; mkdir -p "$E"
guard_server
{
 echo "Date UTC        : $(date -u +%FT%TZ)"
 echo "Postgres        : $(psql -X -qAt -d postgres -c 'select version()')"
 echo "pgTAP           : $(ls /usr/share/postgresql/16/extension | grep -oE 'pgtap--[0-9.]+\.sql' | sort -V | tail -1)  | pg_prove $(pg_prove --version | head -1)"
 echo "Cible           : socket $POC_SOCK, port $POC_PORT, data_directory $(psql -X -qAt -d postgres -c "select current_setting('data_directory')"), listen_addresses='$(psql -X -qAt -d postgres -c 'show listen_addresses')'"
 echo "Docker/Supabase CLI : $(docker info >/dev/null 2>&1 && echo disponible || echo 'daemon Docker absent') / $(which supabase >/dev/null 2>&1 && echo présent || echo absent)"
 echo "Données         : 100 % synthétiques (@example.invalid, UUID fixes) — aucune donnée réelle"
 echo "SHA256 migrations :"; sha256sum "$POC_ROOT"/sql/migrations/*.sql | sed "s|$POC_ROOT/||"
} > "$E/00_environnement.txt"
rc=0
run() { name="$1"; shift; echo ">>> $name"; "$@" > "$E/$name.log" 2>&1; r=$?; tail -n 3 "$E/$name.log" | sed 's/^/    /'; echo "    [rc=$r]"; [ $r -ne 0 ] && rc=1; }
bash $S/create_db.sh mgmt_poc_main >/dev/null && bash $S/migrate.sh mgmt_poc_main > "$E/10_migration_initiale.log" 2>&1
psql -X -v ON_ERROR_STOP=1 -q -d mgmt_poc_main -f "$POC_ROOT/sql/seed_synthetic.sql"
run 20_garde_cible_negative   bash $S/guard_negative.sh
run 30_tests_pgtap_rls_roles_invariants bash $S/run_tests.sh mgmt_poc_main
run 40_migrations_independantes bash $S/migration_independence.sh
run 50_sauvegarde_restauration  bash $S/backup_restore.sh
run 52_restauration_adverse     bash $S/restore_proofs.sh
run 55_course_dernier_owner     bash $S/race_last_owner.sh
run 60_mutation_tests           bash $S/mutation_check.sh
run 62_mutation_restauration    bash $S/restore_mutation.sh
run 70_risques_ouverts_sondes   bash $S/open_risks_probe.sh
echo; [ $rc -eq 0 ] && echo "TOUTES LES PREUVES : PASS" || echo "AU MOINS UNE PREUVE EN ÉCHEC"
exit $rc
