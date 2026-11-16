\set ON_ERROR_STOP on
-- Volume synthétique pour mesurer sauvegarde/restauration : 50 orgs × 20 projets × 40 actions = 40 000 actions.
insert into auth.users(id,email)
  select ('10000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid, 'bulk'||g||'@example.invalid' from generate_series(1,50) g;
insert into management_next.product_access(user_id)
  select ('10000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid from generate_series(1,50) g;
insert into management_next.organizations(id,name,created_by)
  select ('20000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid, 'Org bulk '||g,
         ('10000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid from generate_series(1,50) g;
insert into management_next.memberships(org_id,user_id,role)
  select ('20000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid,
         ('10000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid, 'owner' from generate_series(1,50) g;
insert into management_next.projects(id,org_id,name,created_by)
  select ('30000000-0000-4000-' || lpad(to_hex(g),4,'0') || '-' || lpad(to_hex(p),12,'0'))::uuid,
         ('20000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid, 'Projet '||g||'-'||p,
         ('10000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid
  from generate_series(1,50) g, generate_series(1,20) p;
insert into management_next.actions(id,org_id,project_id,title,status,done_at,created_by)
  select ('40000000-' || lpad(to_hex(g),4,'0') || '-4000-' || lpad(to_hex(p),4,'0') || '-' || lpad(to_hex(a),12,'0'))::uuid,
         ('20000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid,
         ('30000000-0000-4000-' || lpad(to_hex(g),4,'0') || '-' || lpad(to_hex(p),12,'0'))::uuid,
         'Action '||g||'-'||p||'-'||a,
         case when a % 4 = 0 then 'done' else 'open' end,
         case when a % 4 = 0 then timestamptz '2026-02-01 08:00:00+00' + (a || ' minutes')::interval end,
         ('10000000-0000-4000-8000-' || lpad(to_hex(g),12,'0'))::uuid
  from generate_series(1,50) g, generate_series(1,20) p, generate_series(1,40) a;
