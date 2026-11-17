#!/usr/bin/env bash
# restore_mutation.sh : mutation de la PROCÉDURE de restauration elle-même (sur une copie, jamais l'original).
# Chaque mutant retire une protection ; restore_proofs.sh DOIT échouer. Sinon : trou de couverture.
source "$(dirname "$0")/lib.sh"; set +e
M="$POC_ROOT/work/restmut-$(date +%Y%m%dT%H%M%S)-$$"; mkdir -p "$M"; fail=0; tot=0; surv=0
mutants=(
"R1|contrôle du mode de session (origin) retiré|current_setting('session_replication_role') <> 'origin'|false"
"R2|verrou consultatif retiré|perform pg_advisory_xact_lock(hashtextextended('\$org', 0));|"
"R3|projets restaurés avec leur statut d'origine (sans étape active)|select id, org_id, name, 'active', created_by, created_at from _stage_projects|select id, org_id, name, status, created_by, created_at from _stage_projects"
"R4|contrôle d'organisation déjà présente retiré|if exists (select 1 from management_next.organizations where id = '\$org') then|if false then"
)
for m in "${mutants[@]}"; do
  IFS='|' read -r id desc from to <<< "$m"; tot=$((tot+1))
  R="$M/$id"; mkdir -p "$R"; cp -r "$POC_ROOT/scripts" "$POC_ROOT/sql" "$POC_ROOT/tests" "$R/"
  python3 -I - "$R/scripts/restore_org.sh" "$from" "$to" <<'PY'
import sys
f,a,b=sys.argv[1:4]; s=open(f).read(); assert a in s,("motif absent",a); open(f,"w").write(s.replace(a,b))
PY
  out=$(bash "$R/scripts/restore_proofs.sh" 2>&1); rc=$?
  nf=$(echo "$out" | grep -c '^FAIL')
  if [ $rc -ne 0 ]; then echo "TUÉ       $id  $desc  ($nf contrôle(s) en échec ; ex. « $(echo "$out" | grep -m1 '^FAIL' | cut -c1-110) »)"; else echo "SURVIVANT $id  $desc"; surv=$((surv+1)); fail=1; fi
done
echo; echo "Mutants de restauration : $tot, survivants : $surv"
# Témoin de l'analyse statique : une désactivation injectée DOIT être vue
mkdir -p "$M/static"; cp "$POC_ROOT/scripts/restore_org.sh" "$M/static/restore_org.sh"; echo "set local session_replication_role = replica;" >> "$M/static/restore_org.sh"
n=$(grep -nE "session_replication_role|disable trigger|NOT VALID|set constraints" "$M/static/restore_org.sh" | grep -vE "current_setting\('session_replication_role'\) <> 'origin'|session_replication_role.*interdite|mode de session|^.*#" | wc -l)
[ "$n" -ge 1 ] && echo "TUÉ       S1  désactivation injectée dans la procédure : détectée par l'analyse statique ($n ligne)" || { echo "SURVIVANT S1  analyse statique aveugle"; fail=1; }
[ $fail -eq 0 ] && echo "RÉSULTAT mutation restauration : PASS" || echo "RÉSULTAT mutation restauration : FAIL"
exit $fail
