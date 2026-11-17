#!/usr/bin/env bash
# export_org.sh <db> <org-uuid> <dossier> : export logique d'UNE organisation (4 tables, CSV, ordre FK).
source "$(dirname "$0")/lib.sh"
db="${1:?db}"; org="${2:?org}"; dir="${3:?dossier}"
[[ "$org" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || die "uuid d'organisation invalide"
guard_db "$db"; mkdir -p "$dir"
for t in organizations:id memberships:org_id projects:org_id actions:org_id; do
  n=${t%%:*}; c=${t#*:}
  q "$db" -c "copy (select * from management_next.$n where $c='$org' order by 1) to stdout with (format csv)" > "$dir/$n.csv"
done
echo "export $org : $(wc -l < "$dir/organizations.csv") org, $(wc -l < "$dir/memberships.csv") membres, $(wc -l < "$dir/projects.csv") projets, $(wc -l < "$dir/actions.csv") actions"
