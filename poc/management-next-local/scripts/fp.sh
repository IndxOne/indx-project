#!/usr/bin/env bash
# fp.sh <db> <public|mn> : empreinte (md5) du schéma (DDL + ACL + policies) et des données.
source "$(dirname "$0")/lib.sh"
db="$1"; what="$2"; guard_db "$db"
dump() { pg_dump -h "$POC_SOCK" -p "$POC_PORT" -U postgres -d "$db" "$@" | grep -vE '^\\(un)?restrict '; }  # jeton aléatoire par dump (pg_dump >= 16.10)
case "$what" in
  public) # produit voisin + Auth : ne doit JAMAIS bouger du fait de management_next
    ddl=$(dump -s -n public -n auth | md5sum | cut -c1-12)
    dat=$(q "$db" -c "select md5(coalesce(string_agg(t::text,'|' order by t::text),'')) from (select * from auth.users union all select id,body,null from public.family_notes union all select user_id,display_name,null from public.identity_profiles) t" | cut -c1-12)
    echo "ddl=$ddl data=$dat" ;;
  mn_ddl)  echo "ddl=$(dump -s -n management_next | md5sum | cut -c1-12)" ;;
  mn_data) q "$db" -c "select 'orgs='||(select md5(coalesce(string_agg(o::text,'|' order by id),'')) from management_next.organizations o)
     ||' mem='||(select md5(coalesce(string_agg(m::text,'|' order by org_id,user_id),'')) from management_next.memberships m)
     ||' prj='||(select md5(coalesce(string_agg(p::text,'|' order by id),'')) from management_next.projects p)
     ||' act='||(select md5(coalesce(string_agg(a::text,'|' order by id),'')) from management_next.actions a)
     ||' pa='||(select md5(coalesce(string_agg(x::text,'|' order by user_id),'')) from management_next.product_access x)" | sed -E 's/=([0-9a-f]{12})[0-9a-f]*/=\1/g' ;;
esac
