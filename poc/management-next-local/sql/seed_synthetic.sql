\set ON_ERROR_STOP on
-- DONNÉES 100 % FICTIVES (UUID fixes lisibles, e-mails @example.invalid). Exécuté en superuser local.
insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000a1','owner_a@example.invalid'),
 ('00000000-0000-4000-8000-0000000000a2','editor_a@example.invalid'),
 ('00000000-0000-4000-8000-0000000000a3','viewer_a@example.invalid'),
 ('00000000-0000-4000-8000-0000000000b1','owner_b@example.invalid'),
 ('00000000-0000-4000-8000-0000000000c1','multi@example.invalid'),
 ('00000000-0000-4000-8000-0000000000d1','idle@example.invalid'),
 ('00000000-0000-4000-8000-0000000000f1','family_only@example.invalid');
-- family_only : compte Auth valide, produit Family uniquement, AUCUN accès Management.
insert into management_next.product_access(user_id) values
 ('00000000-0000-4000-8000-0000000000a1'),('00000000-0000-4000-8000-0000000000a2'),
 ('00000000-0000-4000-8000-0000000000a3'),('00000000-0000-4000-8000-0000000000b1'),
 ('00000000-0000-4000-8000-0000000000c1'),('00000000-0000-4000-8000-0000000000d1');
insert into management_next.organizations(id,name,created_by) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Org A (fictive)','00000000-0000-4000-8000-0000000000a1'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Org B (fictive)','00000000-0000-4000-8000-0000000000b1');
insert into management_next.memberships(org_id,user_id,role) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','00000000-0000-4000-8000-0000000000a1','owner'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','00000000-0000-4000-8000-0000000000a2','editor'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','00000000-0000-4000-8000-0000000000a3','viewer'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','00000000-0000-4000-8000-0000000000c1','viewer'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','00000000-0000-4000-8000-0000000000b1','owner'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','00000000-0000-4000-8000-0000000000c1','editor');
insert into management_next.projects(id,org_id,name,created_by) values
 ('a1a1a1a1-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Projet A1','00000000-0000-4000-8000-0000000000a1'),
 ('a1a1a1a1-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Projet A2','00000000-0000-4000-8000-0000000000a1'),
 ('b1b1b1b1-0000-4000-8000-000000000001','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Projet B1','00000000-0000-4000-8000-0000000000b1');
insert into management_next.actions(id,org_id,project_id,title,status,done_at,created_by) values
 ('a1a1a1a1-0000-4000-8001-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','A1 ouverte','open',null,'00000000-0000-4000-8000-0000000000a1'),
 ('a1a1a1a1-0000-4000-8001-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','A1 terminée','done','2026-01-02T10:00:00Z','00000000-0000-4000-8000-0000000000a1'),
 ('a1a1a1a1-0000-4000-8001-000000000003','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000002','A2 ouverte','open',null,'00000000-0000-4000-8000-0000000000a1'),
 ('a1a1a1a1-0000-4000-8001-000000000004','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','A1 ouverte bis','open',null,'00000000-0000-4000-8000-0000000000a1'),
 ('b1b1b1b1-0000-4000-8001-000000000001','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','b1b1b1b1-0000-4000-8000-000000000001','B1 ouverte','open',null,'00000000-0000-4000-8000-0000000000b1'),
 ('b1b1b1b1-0000-4000-8001-000000000002','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','b1b1b1b1-0000-4000-8000-000000000001','B1 terminée','done','2026-01-03T10:00:00Z','00000000-0000-4000-8000-0000000000b1');
-- Produit voisin : family_only et owner_a ont chacun UNE note Family.
insert into public.family_notes(id,user_id,body) values
 ('f0f0f0f0-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000000f1','note family_only'),
 ('f0f0f0f0-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000000a1','note owner_a (produit Family)');
insert into public.identity_profiles(user_id,display_name) values
 ('00000000-0000-4000-8000-0000000000f1','Family Only'),('00000000-0000-4000-8000-0000000000a1','Owner A');
