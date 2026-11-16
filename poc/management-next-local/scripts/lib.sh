#!/usr/bin/env bash
# lib.sh — garde-fous communs (source uniquement). Toute exécution SQL du POC passe par ici.
# Refuse : variables de cible distante, hôte/port différents du socket local POC,
# base hors convention mgmt_poc_*, sentinelle absente, répertoire de données inattendu.
set -euo pipefail
POC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POC_SOCK=/var/lib/mgmt_next_poc/sock
POC_PORT=54329
POC_DATADIR=/var/lib/mgmt_next_poc/pgdata
SENTINEL=MANAGEMENT_NEXT_LOCAL_POC

die() { echo "REFUS: $*" >&2; exit 90; }

for v in DATABASE_URL SUPABASE_URL SUPABASE_DB_URL SUPABASE_ACCESS_TOKEN SUPABASE_SERVICE_ROLE_KEY PGSERVICE PGSERVICEFILE PGPASSWORD PGHOSTADDR PGSSLMODE; do
  [ -z "${!v:-}" ] || die "variable $v définie (risque de cible distante)"
done
case "${PGHOST:-}" in ""|"$POC_SOCK") ;; *) die "PGHOST='${PGHOST}' différent du socket local POC" ;; esac
case "${PGPORT:-}" in ""|"$POC_PORT") ;; *) die "PGPORT='${PGPORT}' différent du port POC $POC_PORT" ;; esac
case "${PGUSER:-}" in ""|postgres) ;; *) die "PGUSER='${PGUSER}' inattendu" ;; esac
export PGHOST="$POC_SOCK" PGPORT="$POC_PORT" PGUSER=postgres PGOPTIONS="-c client_min_messages=warning"

guard_server() {
  [ -S "$POC_SOCK/.s.PGSQL.$POC_PORT" ] || die "socket POC absent ($POC_SOCK)"
  local out
  out=$(psql -X -qAt -d postgres -c "select current_setting('data_directory')||'|'||coalesce(inet_server_addr()::text,'socket')||'|'||current_setting('port')") || die "serveur illisible"
  [ "$out" = "$POC_DATADIR|socket|$POC_PORT" ] || die "serveur inattendu: $out"
}

guard_db() {
  local db="$1"
  case "$db" in mgmt_poc_*) ;; *) die "base '$db' hors convention mgmt_poc_*" ;; esac
  guard_server
  local out
  out=$(psql -X -qAt -d "$db" -c "select (select value from public.__poc_sentinel limit 1)" 2>/dev/null) || die "sentinelle illisible dans '$db'"
  [ "$out" = "$SENTINEL" ] || die "sentinelle inattendue dans '$db': '$out'"
}

q()   { local db="$1"; shift; psql -X -v ON_ERROR_STOP=1 -qAt -d "$db" "$@"; }
now() { date +%s.%N; }
