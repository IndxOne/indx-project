#!/usr/bin/env bash
# create_db.sh <db> [--with-family] : recrée une base POC vierge (stubs Supabase locaux + produit Family fictif).
source "$(dirname "$0")/lib.sh"
db="${1:?usage: create_db.sh <mgmt_poc_*>}"
case "$db" in mgmt_poc_*) ;; *) die "base '$db' hors convention mgmt_poc_*" ;; esac
guard_server
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists "$db"
createdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres "$db"
psql -X -v ON_ERROR_STOP=1 -qAt -d "$db" -f "$POC_ROOT/sql/stubs/00_supabase_local_stubs.sql" >/dev/null
guard_db "$db"
if [ "${2:-}" != "--no-family" ]; then
  psql -X -v ON_ERROR_STOP=1 -qAt -d "$db" -f "$POC_ROOT/sql/stubs/10_family_product_stub.sql" >/dev/null
fi
echo "base $db créée (sentinelle OK)"
