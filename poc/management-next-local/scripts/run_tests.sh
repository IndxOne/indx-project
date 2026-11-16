#!/usr/bin/env bash
# run_tests.sh <db> [fichiers...] : installe les aides de test puis lance pg_prove (verbose).
source "$(dirname "$0")/lib.sh"
db="${1:?usage: run_tests.sh <mgmt_poc_*> [tests...]}"; shift || true
guard_db "$db"
psql -X -v ON_ERROR_STOP=1 -q -d "$db" -f "$POC_ROOT/tests/00_helpers.sql" >/dev/null
files=("$@"); [ ${#files[@]} -gt 0 ] || files=("$POC_ROOT"/tests/0[1-4]_*.test.sql)
pg_prove -h "$POC_SOCK" -p "$POC_PORT" -U postgres -d "$db" --verbose "${files[@]}"
