begin;
set local search_path = tap, public;
select plan(54);

-- ===== anon =====
select is(tests.state_as('anon', null, 'select 1 from management_next.organizations'), '42501', 'anon : organizations refusé');
select is(tests.state_as('anon', null, 'select 1 from management_next.memberships'),   '42501', 'anon : memberships refusé');
select is(tests.state_as('anon', null, 'select 1 from management_next.projects'),      '42501', 'anon : projects refusé');
select is(tests.state_as('anon', null, 'select 1 from management_next.actions'),       '42501', 'anon : actions refusé');
select is(tests.state_as('anon', null, 'select 1 from management_next.product_access'),'42501', 'anon : product_access refusé');
select is(tests.state_as('anon', null, $q$select management_next.create_organization('x')$q$), '42501', 'anon : RPC create_organization refusé');
select is(tests.state_as('anon', null, $q$select management_next.role_in('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$q$), '42501', 'anon : role_in refusé');
-- authenticated sans identité (uid nul)
select is(tests.count_as('authenticated', null, 'select 1 from management_next.organizations'), 0::bigint, 'authenticated sans sub : 0 organisation');
select is(tests.state_as('authenticated', null, $q$select management_next.create_organization('x')$q$), 'MN004', 'authenticated sans sub : RPC refusée (MN004)');

-- ===== visibilité par rôle (orgs / projets / actions / membres) =====
select is(tests.count_as('authenticated', tests.u('owner_a'),  'select 1 from management_next.organizations'), 1::bigint, 'owner_a : 1 org');
select is(tests.count_as('authenticated', tests.u('owner_a'),  'select 1 from management_next.projects'), 2::bigint, 'owner_a : 2 projets');
select is(tests.count_as('authenticated', tests.u('owner_a'),  'select 1 from management_next.actions'), 4::bigint, 'owner_a : 4 actions');
select is(tests.count_as('authenticated', tests.u('owner_a'),  'select 1 from management_next.memberships'), 4::bigint, 'owner_a : 4 membres visibles');
select is(tests.count_as('authenticated', tests.u('editor_a'), 'select 1 from management_next.actions'), 4::bigint, 'editor_a : 4 actions');
select is(tests.count_as('authenticated', tests.u('viewer_a'), 'select 1 from management_next.actions'), 4::bigint, 'viewer_a : 4 actions (lecture)');
select is(tests.count_as('authenticated', tests.u('owner_b'),  'select 1 from management_next.actions'), 2::bigint, 'owner_b : 2 actions (org B seulement)');
select is(tests.count_as('authenticated', tests.u('multi'),    'select 1 from management_next.organizations'), 2::bigint, 'multi : 2 orgs');
select is(tests.count_as('authenticated', tests.u('multi'),    'select 1 from management_next.actions'), 6::bigint, 'multi : 6 actions (A viewer + B editor)');
select is(tests.count_as('authenticated', tests.u('idle'),     'select 1 from management_next.actions'), 0::bigint, 'idle (accès produit, sans appartenance) : 0');

-- ===== VIEWER : lecture seule partout =====
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','v')$q$), '42501', 'viewer : INSERT projet refusé');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$update management_next.projects set name='hack' where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:0', 'viewer : UPDATE projet = 0 ligne');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$delete from management_next.projects where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:0', 'viewer : DELETE projet = 0 ligne');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$insert into management_next.actions(org_id,project_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','v')$q$), '42501', 'viewer : INSERT action refusé');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$update management_next.actions set title='hack' where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:0', 'viewer : UPDATE action = 0 ligne');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$delete from management_next.actions where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:0', 'viewer : DELETE action = 0 ligne');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', auth.uid(), 'owner')$q$), '42501', 'viewer : auto-ajout owner refusé (RLS)');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$update management_next.memberships set role='owner' where user_id=auth.uid()$q$), 'OK:0', 'viewer : auto-promotion = 0 ligne');
select is((select role from management_next.memberships where user_id=tests.u('viewer_a')), 'viewer', 'viewer_a reste viewer (vérifié en superuser)');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$update management_next.organizations set name='hack'$q$), 'OK:0', 'viewer : renommer org = 0 ligne');
select is(tests.state_as('authenticated', tests.u('viewer_a'), $q$delete from management_next.organizations$q$), 'OK:0', 'viewer : supprimer org = 0 ligne');

-- ===== EDITOR : écrit projets/actions, ne gère ni membres ni org =====
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','p editor')$q$), 'OK:1', 'editor : INSERT projet autorisé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.projects set name='renommé' where name='p editor'$q$), 'OK:1', 'editor : UPDATE projet autorisé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$delete from management_next.projects where name='renommé'$q$), 'OK:0', 'editor : DELETE projet refusé (owner seulement)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$insert into management_next.actions(org_id,project_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000001','a editor')$q$), 'OK:1', 'editor : INSERT action autorisé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.actions set title='x editor' where title='a editor'$q$), 'OK:1', 'editor : UPDATE action autorisé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$delete from management_next.actions where title='x editor'$q$), 'OK:1', 'editor : DELETE action autorisé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.u('idle'), 'viewer')$q$), '42501', 'editor : ajout de membre refusé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.memberships set role='owner' where user_id=auth.uid()$q$), 'OK:0', 'editor : auto-promotion owner = 0 ligne');
select is((select role from management_next.memberships where user_id=tests.u('editor_a') and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'editor', 'editor_a reste editor (vérifié en superuser)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.organizations set name='hack'$q$), 'OK:0', 'editor : renommer org refusé');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$delete from management_next.memberships where user_id=tests.u('viewer_a')$q$), 'OK:0', 'editor : retirer un membre refusé');

-- ===== OWNER : gère membres, projets, org =====
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$update management_next.organizations set name='Org A renommée'$q$), 'OK:1', 'owner : renommer org autorisé (sa seule org)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '00000000-0000-4000-8000-0000000000d1', 'viewer')$q$), 'OK:1', 'owner : ajout de membre (avec accès produit) autorisé');
select is(tests.count_as('authenticated', tests.u('idle'), 'select 1 from management_next.actions'), 4::bigint, 'idle voit désormais les 4 actions de A (attribution)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$update management_next.memberships set role='editor' where user_id='00000000-0000-4000-8000-0000000000d1'$q$), 'OK:1', 'owner : changement de rôle autorisé');
select is(tests.state_as('authenticated', tests.u('idle'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','idle ed')$q$), 'OK:1', 'rôle promu editor : peut écrire immédiatement');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$delete from management_next.memberships where user_id='00000000-0000-4000-8000-0000000000d1'$q$), 'OK:1', 'owner : retrait d''appartenance autorisé');
select is(tests.count_as('authenticated', tests.u('idle'), 'select 1 from management_next.actions'), 0::bigint, 'idle perd l''accès (désattribution effective)');
select is(tests.state_as('authenticated', tests.u('idle'), $q$insert into management_next.projects(org_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','after removal')$q$), '42501', 'après retrait : écriture refusée');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.u('family'), 'viewer')$q$), 'MN003', 'owner : ajouter un compte Family sans accès produit refusé (MN003)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.u('idle'), 'admin')$q$), '23514', 'rôle hors liste refusé (CHECK)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$delete from management_next.projects where id='a1a1a1a1-0000-4000-8000-000000000001'$q$), '23503', 'owner : supprimer un projet portant des actions refusé (FK RESTRICT)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$delete from management_next.organizations$q$), '23503', 'owner : supprimer une org non vide refusé (FK RESTRICT)');
select is(tests.count_as('authenticated', tests.u('owner_a'), 'select 1 from management_next.organizations where id=''bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'''), 0::bigint, 'owner_a ne voit pas l''org B');

select * from finish();
rollback;
