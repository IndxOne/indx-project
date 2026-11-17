# Management Next — POC local RLS / migrations / restauration

Arborescence : `sql/migrations/` (3 migrations idempotentes, schéma `management_next`) · `sql/down/` · `sql/restore/post_restore.sql` (étape obligatoire après restauration sélective) · `sql/stubs/` (imitation locale de Supabase, hors migrations) · `sql/seed_*.sql` (données fictives) · `tests/` (pgTAP) · `scripts/` · `evidence/` (sorties).

Prérequis : PostgreSQL 16 + pgTAP + `pg_prove`. Instance isolée utilisée : socket `/var/lib/mgmt_next_poc/sock`, port 54329 (TCP désactivé).
Garde-fous : toute exécution passe par `scripts/lib.sh` (refuse variables de cible distante, PGHOST/PGPORT/PGUSER inattendus, base hors `mgmt_poc_*`, sentinelle absente) ; chaque migration revérifie la sentinelle et l'absence de TCP.

Commandes : `bash scripts/run_all.sh` (tout) · `scripts/run_tests.sh <db>` · `scripts/migrate.sh <db>` · `scripts/migration_independence.sh` · `scripts/backup_restore.sh` · `scripts/mutation_check.sh` · `scripts/open_risks_probe.sh` · `scripts/guard_negative.sh`.
Procédure de restauration sélective : `create schema management_next` → `pg_restore -n management_next` → `psql -f sql/restore/post_restore.sql`.

Corrections de la révision 2 : voir `CORRECTIONS.md`. Test de concurrence : `scripts/race_last_owner.sh`.
Détecter une organisation sans owner actif et la récupérer : voir `CORRECTIONS.md`.
Restauration sélective d'une organisation (contraintes actives) : `scripts/export_org.sh` puis `scripts/restore_org.sh`. Preuves adverses : `scripts/restore_proofs.sh`, `scripts/restore_mutation.sh`. Spécification D3b : `D3B-SPEC.md`.
