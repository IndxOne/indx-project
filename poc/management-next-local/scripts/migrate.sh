#!/usr/bin/env bash
# migrate.sh <db> : applique sql/migrations/*.sql dans l'ordre, registre propre à management_next
# (management_next.schema_migrations), aucune dépendance à supabase_migrations ni à l'ancien Management.
# Drift : un fichier déjà appliqué dont le checksum change fait échouer le script.
source "$(dirname "$0")/lib.sh"
db="${1:?usage: migrate.sh <mgmt_poc_*> [préfixe-max]}"; upto="${2:-}"   # préfixe-max : s'arrêter après cette migration (ex. 20261116000003)
guard_db "$db"
q "$db" -c "create schema if not exists management_next; create table if not exists management_next.schema_migrations (name text primary key, checksum text not null, applied_at timestamptz not null default now());" >/dev/null
for f in "$POC_ROOT"/sql/migrations/*.sql; do
  name="$(basename "$f")"; if [ -n "$upto" ] && [[ "${name%%_*}" > "$upto" ]]; then continue; fi; sum="$(sha256sum "$f" | cut -d' ' -f1)"
  have="$(q "$db" -c "select checksum from management_next.schema_migrations where name='$name'")"
  if [ -z "$have" ]; then
    psql -X -v ON_ERROR_STOP=1 -q -1 -d "$db" -f "$f" >/dev/null
    q "$db" -c "insert into management_next.schema_migrations(name,checksum) values ('$name','$sum')" >/dev/null
    echo "appliquée : $name"
  elif [ "$have" = "$sum" ]; then
    echo "déjà appliquée (checksum identique) : $name"
  else
    die "DRIFT sur $name (checksum $sum ≠ registre $have)"
  fi
done
