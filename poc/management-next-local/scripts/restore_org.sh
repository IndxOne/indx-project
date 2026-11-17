#!/usr/bin/env bash
# restore_org.sh <db> <org-uuid> <dossier> : restauration sélective d'UNE organisation, TOUTES contraintes actives.
# Principe (aucun session_replication_role, aucun trigger ni FK désactivé) :
#   1. verrou consultatif de l'organisation (même clé que la garde du dernier owner) ;
#   2. refus si l'organisation existe déjà ou si le mode de session n'est pas 'origin' ;
#   3. organisation, appartenances ; projets insérés ACTIFS (via table temporaire) ; actions ; puis réarchivage ;
#   4. contrôles d'intégrité dans la même transaction ; tout ou rien (COMMIT seulement si tout passe).
# RESTORE_HOLD_SECONDS : crochet de TEST de concurrence (pause après prise du verrou), 0 par défaut.
source "$(dirname "$0")/lib.sh"
db="${1:?db}"; org="${2:?org}"; dir="${3:?dossier}"; hold="${RESTORE_HOLD_SECONDS:-0}"
[[ "$org" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || die "uuid d'organisation invalide"
[[ "$hold" =~ ^[0-9]+$ ]] || die "RESTORE_HOLD_SECONDS invalide"
for f in organizations memberships projects actions; do [ -r "$dir/$f.csv" ] || die "fichier manquant: $dir/$f.csv"; done
guard_db "$db"
psql -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -d "$db" <<SQL
begin;
do \$\$ begin perform pg_advisory_xact_lock(hashtextextended('$org', 0)); perform pg_sleep($hold); end \$\$;
do \$\$ declare v text;
begin
  if inet_server_addr() is not null then raise exception 'REFUS: cible non locale POC (connexion TCP)'; end if;
  if to_regclass('public.__poc_sentinel') is null then raise exception 'REFUS: cible non locale POC (sentinelle absente)'; end if;
  execute 'select value from public.__poc_sentinel limit 1' into v;
  if v is distinct from 'MANAGEMENT_NEXT_LOCAL_POC' then raise exception 'REFUS: cible non locale POC (sentinelle inattendue)'; end if;
  if current_setting('session_replication_role') <> 'origin' then
    raise exception 'MN008: restauration interdite hors mode origin (contraintes actives obligatoires)' using errcode = 'MN008';
  end if;
  if exists (select 1 from management_next.organizations where id = '$org') then
    raise exception 'MN007: organisation déjà présente, restauration annulée' using errcode = 'MN007';
  end if;
end \$\$;
create temp table _stage_projects (like management_next.projects) on commit drop;
\copy management_next.organizations from '$dir/organizations.csv' with (format csv)
\copy management_next.memberships from '$dir/memberships.csv' with (format csv)
\copy _stage_projects from '$dir/projects.csv' with (format csv)
insert into management_next.projects (id, org_id, name, status, created_by, created_at)
  select id, org_id, name, 'active', created_by, created_at from _stage_projects;
\copy management_next.actions from '$dir/actions.csv' with (format csv)
update management_next.projects p set status = s.status from _stage_projects s where p.id = s.id and s.status <> 'active';
do \$\$ declare n bigint;
begin
  if current_setting('session_replication_role') <> 'origin' then raise exception 'MN008: mode de session modifié pendant la restauration' using errcode = 'MN008'; end if;
  select count(*) into n from management_next.actions a left join management_next.projects p on p.id = a.project_id and p.org_id = a.org_id
    where a.org_id = '$org' and p.id is null;
  if n > 0 then raise exception 'MN009: % action(s) orpheline(s) après restauration', n using errcode = 'MN009'; end if;
  select count(*) into n from pg_constraint where connamespace = 'management_next'::regnamespace and not convalidated;
  if n > 0 then raise exception 'MN009: % contrainte(s) non validée(s)', n using errcode = 'MN009'; end if;
  if (select count(*) from management_next.projects where org_id = '$org') <> (select count(*) from _stage_projects) then
    raise exception 'MN009: nombre de projets restaurés différent de la sauvegarde' using errcode = 'MN009';
  end if;
end \$\$;
commit;
SQL
