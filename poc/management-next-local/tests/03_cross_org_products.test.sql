begin;
set local search_path = tap, public;
select plan(27);

-- ===== Autre organisation (owner_b) face aux données de l'org A =====
select is(tests.count_as('authenticated', tests.u('owner_b'), 'select 1 from management_next.actions where org_id=''aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'''), 0::bigint, 'owner_b : 0 action de A visible');
select is(tests.count_as('authenticated', tests.u('owner_b'), 'select 1 from management_next.memberships where org_id=''aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'''), 0::bigint, 'owner_b : 0 membre de A visible');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$insert into management_next.actions(org_id,project_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','intrusion')$q$), '42501', 'owner_b : INSERT action dans A refusé (RLS)');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','intrusion')$q$), '42501', 'owner_b : INSERT projet dans A refusé (RLS)');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', auth.uid(), 'owner')$q$), '42501', 'owner_b : se déclarer owner de A refusé (RLS)');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$update management_next.actions set title='hack' where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:0', 'owner_b : UPDATE A = 0 ligne');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$delete from management_next.actions where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:0', 'owner_b : DELETE A = 0 ligne');
select is((select count(*) from management_next.actions where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 4::bigint, 'actions de A intactes (vérifié en superuser)');
-- Fraude à l'appartenance : action déclarée dans B mais rattachée à un projet de A
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$insert into management_next.actions(org_id,project_id,title) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','a1a1a1a1-0000-4000-8000-000000000001','pivot')$q$), '23503', 'owner_b : action B -> projet A refusée (FK composite)');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$update management_next.actions set project_id='a1a1a1a1-0000-4000-8000-000000000001' where id='b1b1b1b1-0000-4000-8001-000000000001'$q$), '42501', 'owner_b : déplacer une action vers un projet de A refusé (privilège colonne)');
select is(tests.state_as('authenticated', tests.u('owner_b'), $q$update management_next.projects set org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' where id='b1b1b1b1-0000-4000-8000-000000000001'$q$), '42501', 'owner_b : transférer un projet B vers A refusé (privilège colonne)');
-- Même invariant au niveau base pour un rôle qui AURAIT le privilège (superuser, hors RLS/GRANT)
select is(tests.state_as('postgres', null, $q$update management_next.projects set org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' where id='b1b1b1b1-0000-4000-8000-000000000001'$q$), 'MN001', 'superuser : transfert de projet inter-org refusé (trigger MN001)');
select is(tests.state_as('postgres', null, $q$update management_next.actions set org_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', project_id='b1b1b1b1-0000-4000-8000-000000000001' where id='a1a1a1a1-0000-4000-8001-000000000001'$q$), 'MN001', 'superuser : déplacement d''action A->B (org+projet) refusé (MN001)');
select is(tests.state_as('postgres', null, $q$update management_next.actions set org_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where id='a1a1a1a1-0000-4000-8001-000000000001'$q$), 'MN001', 'superuser : changement d''org seul refusé (MN001 avant FK)');
select is(tests.state_as('postgres', null, $q$update management_next.memberships set org_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where user_id=tests.u('viewer_a')$q$), 'MN001', 'superuser : transfert d''appartenance inter-org refusé (MN001)');

-- ===== Un même compte, deux rôles selon l'organisation (multi = viewer A, editor B) =====
select is(tests.state_as('authenticated', tests.u('multi'), $q$insert into management_next.actions(org_id,project_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','m')$q$), '42501', 'multi : écriture dans A (viewer) refusée');
select is(tests.state_as('authenticated', tests.u('multi'), $q$insert into management_next.actions(org_id,project_id,title) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','b1b1b1b1-0000-4000-8000-000000000001','m')$q$), 'OK:1', 'multi : écriture dans B (editor) autorisée');

-- ===== Family / Identity : compte Auth valide SANS droit Management =====
select is(tests.count_as('authenticated', tests.u('family'), 'select 1 from management_next.organizations'), 0::bigint, 'family : 0 organisation');
select is(tests.count_as('authenticated', tests.u('family'), 'select 1 from management_next.actions'), 0::bigint, 'family : 0 action');
select is(tests.state_as('authenticated', tests.u('family'), $q$select management_next.create_organization('squat')$q$), 'MN003', 'family : création d''organisation refusée (MN003)');
select is(tests.state_as('authenticated', tests.u('family'), $q$insert into management_next.product_access(user_id) values (auth.uid())$q$), '42501', 'family : auto-octroi d''accès produit refusé');
select is(tests.count_as('authenticated', tests.u('family'), 'select 1 from public.family_notes'), 1::bigint, 'family : voit SA note Family (produit voisin intact)');
select is(tests.count_as('authenticated', tests.u('owner_a'), 'select 1 from public.family_notes'), 1::bigint, 'owner_a : voit uniquement SA note Family (pas celle de family_only)');
select is(tests.count_as('authenticated', tests.u('owner_a'), 'select 1 from public.identity_profiles'), 1::bigint, 'owner_a : Identity limité à son profil');

-- ===== Retrait du droit produit = coupure immédiate malgré les appartenances =====
delete from management_next.product_access where user_id = tests.u('editor_a');
select is(tests.count_as('authenticated', tests.u('editor_a'), 'select 1 from management_next.actions'), 0::bigint, 'accès produit retiré : 0 action visible');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','x')$q$), '42501', 'accès produit retiré : écriture refusée');
-- Auth partagé : suppression du compte = appartenances et accès supprimés en cascade
delete from auth.users where id = tests.u('viewer_a');
select is((select count(*) from management_next.memberships where user_id = tests.u('viewer_a')), 0::bigint, 'suppression du compte Auth : appartenances supprimées en cascade');

select * from finish();
rollback;
