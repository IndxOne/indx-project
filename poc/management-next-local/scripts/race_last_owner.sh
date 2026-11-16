#!/usr/bin/env bash
# race_last_owner.sh : deux owners se rétrogradent EN MÊME TEMPS. Avec le verrou consultatif, le second est
# sérialisé puis refusé (MN005) : il reste un owner. Sans verrou (mutant), les deux passent : org sans owner.
source "$(dirname "$0")/lib.sh"; set +e
S="$POC_ROOT/scripts"; DB=mgmt_poc_race; fail=0
ORG=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
run_phase() { # $1 = avec|sans verrou
  bash $S/create_db.sh $DB >/dev/null; bash $S/migrate.sh $DB >/dev/null
  psql -X -v ON_ERROR_STOP=1 -q -d $DB -f $POC_ROOT/sql/seed_synthetic.sql; psql -X -q -d $DB -f $POC_ROOT/tests/00_helpers.sql >/dev/null
  if [ "$1" = "sans" ]; then sed '/pg_advisory_xact_lock/d' $POC_ROOT/sql/migrations/20261116000004_mn_owner_archive_guards.sql | psql -X -v ON_ERROR_STOP=1 -q -d $DB >/dev/null; fi
  q $DB -c "update management_next.memberships set role='owner' where user_id=tests.u('editor_a')" >/dev/null
  W="$POC_ROOT/work"; mkdir -p "$W"
  demote() { psql -X -q -d $DB <<SQL
begin;
select tests.set_ctx(tests.u('$1'));
set local role authenticated;
update management_next.memberships set role='viewer' where user_id = tests.u('$1') and org_id='$ORG';
select pg_sleep($2);
commit;
SQL
  }
  demote owner_a 3 > $W/race_s1.log 2>&1 &
  p1=$!; sleep 1; t0=$(now)
  demote editor_a 0 > $W/race_s2.log 2>&1 &
  p2=$!; wait $p1 $p2; t1=$(now)
  owners=$(q $DB -c "select count(*) from management_next.memberships where org_id='$ORG' and role='owner'")
  echo "[$1 verrou] owners restants : $owners ; session 2 : $(grep -oE 'MN005|UPDATE 1|ERROR' $W/race_s2.log | tr '\n' ' ') ; attente de la session 2 : $(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.1f s",b-a}')"
  RESULT=$owners
}
run_phase avec; [ "$RESULT" = "1" ] && echo "PASS  avec verrou : un owner reste, le second est refusé" || { echo "FAIL  avec verrou : owners=$RESULT"; fail=1; }
run_phase sans; [ "$RESULT" = "0" ] && echo "PASS  témoin : SANS verrou la course produit une org sans owner (le test détecte l'absence de verrou)" || { echo "FAIL  témoin : sans verrou owners=$RESULT (test non discriminant)"; fail=1; }
dropdb -h "$POC_SOCK" -p "$POC_PORT" -U postgres --if-exists $DB
exit $fail
