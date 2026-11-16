begin;
set local search_path = tap, public;
select plan(21);

-- ===== Action terminée : irréversible, niveau base =====
select is(tests.state_as('postgres', null, $q$update management_next.actions set status='open', done_at=null where id='a1a1a1a1-0000-4000-8001-000000000002'$q$), 'MN002', 'superuser : done -> open refusé (MN002)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$update management_next.actions set status='open' where id='a1a1a1a1-0000-4000-8001-000000000002'$q$), 'MN002', 'owner : done -> open refusé (MN002)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.actions set status='open' where id='a1a1a1a1-0000-4000-8001-000000000002'$q$), 'MN002', 'editor : done -> open refusé (MN002)');
select is(tests.state_as('postgres', null, $q$update management_next.actions set done_at=now() where id='a1a1a1a1-0000-4000-8001-000000000002'$q$), 'MN002', 'superuser : redater une action terminée refusé (MN002)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.actions set done_at=now() where id='a1a1a1a1-0000-4000-8001-000000000002'$q$), '42501', 'editor : écrire done_at refusé (privilège colonne)');
select is((select status from management_next.actions where id='a1a1a1a1-0000-4000-8001-000000000002'), 'done', 'l''action reste done (vérifié)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.actions set status='done' where id='a1a1a1a1-0000-4000-8001-000000000001'$q$), 'OK:1', 'editor : open -> done autorisé');
select ok((select done_at is not null from management_next.actions where id='a1a1a1a1-0000-4000-8001-000000000001'), 'done_at posé par la base à la clôture');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.actions set status='open' where id='a1a1a1a1-0000-4000-8001-000000000001'$q$), 'MN002', 'action tout juste terminée : réouverture refusée');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$insert into management_next.actions(org_id,project_id,title,status) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','née terminée','done')$q$), 'OK:1', 'insertion directe en done autorisée');
select ok((select done_at is not null from management_next.actions where title='née terminée'), 'done_at posé par défaut à l''insertion');
select is(tests.state_as('postgres', null, $q$insert into management_next.actions(org_id,project_id,title,status,done_at,created_by) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','x','open', now(), tests.u('owner_a'))$q$), '23514', 'CHECK : open avec done_at refusé');

-- ===== Identifiants immuables =====
select is(tests.state_as('postgres', null, $q$update management_next.projects set id=gen_random_uuid() where id='a1a1a1a1-0000-4000-8000-000000000002'$q$), 'MN001', 'id projet immuable (MN001)');
select is(tests.state_as('postgres', null, $q$update management_next.actions set project_id='a1a1a1a1-0000-4000-8000-000000000002' where id='a1a1a1a1-0000-4000-8001-000000000004'$q$), 'MN001', 'project_id action immuable, même intra-org (MN001)');
select is(tests.state_as('postgres', null, $q$update management_next.memberships set user_id=tests.u('idle') where user_id=tests.u('viewer_a')$q$), 'MN001', 'user_id d''appartenance immuable (MN001)');

-- ===== Contraintes d'intégrité =====
select is(tests.state_as('postgres', null, $q$insert into management_next.projects(org_id,name,status,created_by) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','x','zombie', tests.u('owner_a'))$q$), '23514', 'statut projet hors liste refusé');
select is(tests.state_as('postgres', null, $q$insert into management_next.actions(org_id,project_id,title,created_by) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-0000000000ff','orpheline', tests.u('owner_a'))$q$), '23503', 'action sans projet existant refusée (FK)');
select is(tests.state_as('authenticated', tests.u('idle'), $q$select management_next.create_organization('   ')$q$), '23514', 'nom d''organisation vide refusé');
select is(tests.state_as('postgres', null, $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.u('editor_a'), 'viewer')$q$), '23505', 'appartenance en double refusée');
-- Création d'organisation par le seul chemin autorisé
select is(tests.state_as('authenticated', tests.u('idle'), $q$select management_next.create_organization('Org idle')$q$), 'OK:1', 'RPC create_organization : OK pour un compte avec accès produit');
select is(tests.count_as('authenticated', tests.u('idle'), 'select 1 from management_next.memberships where role=''owner'''), 1::bigint, 'le créateur devient owner de sa nouvelle organisation');

select * from finish();
rollback;
