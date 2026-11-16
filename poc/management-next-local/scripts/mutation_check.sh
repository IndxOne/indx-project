#!/usr/bin/env bash
# mutation_check.sh : casse volontairement un garde-fou à la fois (base jetable) ; la suite pgTAP DOIT échouer.
# Prouve que les tests ne sont pas vacuaux. Un mutant « survivant » (suite verte) = trou de couverture.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; DB=mgmt_poc_mut; fail=0; surv=0; tot=0
mutants=(
"M1|trigger anti-réouverture supprimé|drop trigger mn_guard_actions on management_next.actions"
"M2|trigger immutabilité projet supprimé|drop trigger mn_guard_projects on management_next.projects"
"M3|trigger immutabilité appartenance supprimé|drop trigger mn_guard_memberships on management_next.memberships"
"M4|trigger accès-produit à l'ajout de membre supprimé|drop trigger mn_member_requires_access on management_next.memberships"
"M5|FK composite action→projet(org) supprimée|alter table management_next.actions drop constraint actions_project_id_org_id_fkey"
"M6|policy act_insert ouverte (true)|alter policy act_insert on management_next.actions with check (true)"
"M7|policy act_select ouverte (true)|alter policy act_select on management_next.actions using (true)"
"M8|policy mem_insert ouverte aux editors|alter policy mem_insert on management_next.memberships with check ((select management_next.role_in(org_id)) in ('owner','editor'))"
"M9|policy prj_delete ouverte aux editors|alter policy prj_delete on management_next.projects using ((select management_next.role_in(org_id)) in ('owner','editor'))"
"M10|GRANT SELECT anon sur actions|grant select on management_next.actions to anon"
"M11|GRANT UPDATE(org_id) sur projects|grant update (org_id) on management_next.projects to authenticated"
"M12|GRANT UPDATE(done_at) sur actions|grant update (done_at) on management_next.actions to authenticated"
"M13|EXECUTE PUBLIC sur create_organization|grant execute on function management_next.create_organization(text) to public"
"M14|RLS désactivée sur projects|alter table management_next.projects disable row level security"
"M15|role_in sans contrôle product_access|create or replace function management_next.role_in(p_org uuid) returns text language sql stable security definer set search_path = '' as \$f\$ select m.role from management_next.memberships m where m.org_id = p_org and m.user_id = auth.uid() \$f\$"
"M16E|create_organization sans contrôle product_access (candidat équivalent)|create or replace function management_next.create_organization(p_name text) returns uuid language plpgsql security definer set search_path = '' as \$f\$ declare v_uid uuid := auth.uid(); v_org uuid; begin if v_uid is null then raise exception 'MN004' using errcode='MN004'; end if; insert into management_next.organizations(name, created_by) values (p_name, v_uid) returning id into v_org; insert into management_next.memberships(org_id,user_id,role) values (v_org,v_uid,'owner'); return v_org; end \$f\$"
"M17|search_path non figé sur role_in|alter function management_next.role_in(uuid) reset search_path"
"M18|garde dernier owner (UPDATE) supprimée|drop trigger mn_guard_last_owner_upd on management_next.memberships"
"M19|garde dernier owner (DELETE) supprimée|drop trigger mn_guard_last_owner_del on management_next.memberships"
"M20|garde projet archivé supprimée|drop trigger mn_guard_archived_project on management_next.actions"
"M21|GRANT EXECUTE service_role sur create_organization|grant execute on function management_next.create_organization(text) to service_role"
)
for m in "${mutants[@]}"; do
  id=${m%%|*}; rest=${m#*|}; desc=${rest%%|*}; sql=${rest#*|}; tot=$((tot+1))
  bash $S/create_db.sh $DB >/dev/null; bash $S/migrate.sh $DB >/dev/null
  psql -X -v ON_ERROR_STOP=1 -q -d $DB -f $POC_ROOT/sql/seed_synthetic.sql
  q $DB -c "$sql" >/dev/null 2>$POC_ROOT/work/mut_err.log || { echo "ERREUR d'application du mutant $id: $(cat $POC_ROOT/work/mut_err.log)"; fail=1; continue; }
  out=$(bash $S/run_tests.sh $DB 2>&1); rc=$?
  nf=$(echo "$out" | grep -c "^not ok"); 
  if [ $rc -eq 0 ] && [[ "$id" == *E ]]; then
    # Mutant candidat « équivalent » : on vérifie qu'un compte sans accès produit reste refusé ET qu'aucune organisation orpheline n'est créée.
    before=$(q $DB -c "select count(*) from management_next.organizations")
    st=$(q $DB -c "select tests.state_as('authenticated', tests.u('family'), \$\$select management_next.create_organization('squat')\$\$)")
    after=$(q $DB -c "select count(*) from management_next.organizations")
    if [ "$st" = "MN003" ] && [ "$before" = "$after" ]; then echo "ÉQUIVALENT $id  $desc -> refus MN003 conservé par la couche redondante (trigger), orgs $before=$after (statement atomique)"; else echo "SURVIVANT $id  $desc (état=$st orgs $before->$after)"; surv=$((surv+1)); fail=1; fi
  elif [ $rc -ne 0 ]; then echo "TUÉ       $id  $desc  (tests en échec : $nf ; ex. « $(echo "$out" | grep -m1 '^not ok' | cut -c1-90) »)"; else echo "SURVIVANT $id  $desc"; surv=$((surv+1)); fail=1; fi
done
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $DB
echo; echo "Mutants : $tot, survivants réels : $surv (les « ÉQUIVALENT » sont des couches redondantes vérifiées)"
[ $fail -eq 0 ] && echo "RÉSULTAT mutation : PASS (tous les mutants détectés)" || echo "RÉSULTAT mutation : FAIL"
exit $fail
