begin;
set local search_path = tap, public;
select plan(28);

-- ===== R1 : le dernier owner actif ne peut ni se rétrograder ni se retirer =====
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$update management_next.memberships set role='viewer' where user_id=auth.uid() and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'MN005', 'dernier owner : auto-rétrogradation refusée (MN005)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$delete from management_next.memberships where user_id=auth.uid() and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'MN005', 'dernier owner : auto-retrait refusé (MN005)');
select is((select count(*) from management_next.memberships where org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and role='owner'), 1::bigint, 'l''org A garde son owner (vérifié en superuser)');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$update management_next.memberships set role='owner' where user_id=tests.u('editor_a')$q$), 'OK:1', 'owner : promotion d''un second owner autorisée');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$update management_next.memberships set role='viewer' where user_id=auth.uid() and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:1', 'avec un second owner : l''ancien peut se rétrograder');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$delete from management_next.memberships where user_id=auth.uid() and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'MN005', 'le nouvel unique owner ne peut pas se retirer (MN005)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.memberships set role='editor' where user_id=auth.uid() and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'MN005', 'idem pour la rétrogradation vers editor (MN005)');
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.memberships set role='owner' where user_id=auth.uid() and org_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$), 'OK:1', 'owner -> owner (sans effet) non bloqué');

-- Un owner dont l'accès produit est retiré n'est plus « actif » : le suivant ne peut plus se retirer
delete from management_next.product_access where user_id = tests.u('editor_a');
select is(tests.state_as('authenticated', tests.u('owner_a'), $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.u('idle'), 'owner')$q$), '42501', 'accès produit retiré à editor_a : owner_a (rétrogradé) ne peut plus agir (RLS)');
insert into management_next.product_access(user_id) values (tests.u('editor_a'));

-- Administration (sans identité) : non bloquée, org récupérable
select is(tests.state_as('postgres', null, $q$update management_next.memberships set role='viewer' where user_id=tests.u('editor_a')$q$), 'OK:1', 'rôle d''administration : rétrogradation du dernier owner autorisée (récupération)');
select is((select count(*) from management_next.organizations o where not exists (select 1 from management_next.memberships m join management_next.product_access a using (user_id) where m.org_id=o.id and m.role='owner')), 1::bigint, 'requête de détection : 1 organisation sans owner actif');
select is(tests.state_as('postgres', null, $q$insert into management_next.memberships(org_id,user_id,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.u('idle'), 'owner')$q$), 'OK:1', 'récupération : nouvel owner posé par l''administration');
select is((select count(*) from management_next.organizations o where not exists (select 1 from management_next.memberships m join management_next.product_access a using (user_id) where m.org_id=o.id and m.role='owner')), 0::bigint, 'détection : plus aucune organisation orpheline');

-- Suppression d'un compte Auth partagé : jamais bloquée par Management (R2)
select is(tests.state_as('postgres', null, $q$delete from auth.users where id = tests.u('owner_b')$q$), 'OK:1', 'suppression du compte Auth du dernier owner de B : non bloquée (cascade)');
select is((select count(*) from management_next.organizations o where not exists (select 1 from management_next.memberships m join management_next.product_access a using (user_id) where m.org_id=o.id and m.role='owner')), 1::bigint, 'org B devenue orpheline : détectée');

-- Suppression d'une organisation vide par son owner : non bloquée par le garde
select is(tests.state_as('authenticated', tests.u('idle'), $q$select management_next.create_organization('Org vide')$q$), 'OK:1', 'création d''une organisation');
select is(tests.state_as('authenticated', tests.u('idle'), $q$delete from management_next.organizations where name='Org vide'$q$), 'OK:1', 'owner : suppression d''une organisation vide autorisée (cascade des appartenances)');

-- ===== R4 : projet archivé = figé =====
select is(tests.state_as('authenticated', tests.u('editor_a'), $q$update management_next.projects set status='archived' where id='a1a1a1a1-0000-4000-8000-000000000002'$q$), 'OK:0', 'editor_a n''est plus editor (rétrogradé) : archivage refusé (0 ligne)');
select is(tests.state_as('authenticated', tests.u('idle'), $q$update management_next.projects set status='archived' where id='a1a1a1a1-0000-4000-8000-000000000002'$q$), 'OK:1', 'owner (idle) : archivage autorisé');
select is(tests.state_as('authenticated', tests.u('idle'), $q$insert into management_next.actions(org_id,project_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000002','dans archivé')$q$), 'MN006', 'projet archivé : INSERT action refusé (MN006)');
select is(tests.state_as('authenticated', tests.u('idle'), $q$update management_next.actions set title='x' where id='a1a1a1a1-0000-4000-8001-000000000003'$q$), 'MN006', 'projet archivé : UPDATE action refusé (MN006)');
select is(tests.state_as('authenticated', tests.u('idle'), $q$delete from management_next.actions where id='a1a1a1a1-0000-4000-8001-000000000003'$q$), 'MN006', 'projet archivé : DELETE action refusé (MN006)');
select is(tests.state_as('postgres', null, $q$update management_next.actions set title='x' where id='a1a1a1a1-0000-4000-8001-000000000003'$q$), 'MN006', 'superuser : UPDATE action en projet archivé refusé aussi (trigger)');
select is(tests.count_as('authenticated', tests.u('idle'), 'select 1 from management_next.actions where project_id=''a1a1a1a1-0000-4000-8000-000000000002'''), 1::bigint, 'lecture des actions d''un projet archivé toujours possible');
select is(tests.state_as('authenticated', tests.u('idle'), $q$update management_next.projects set status='active' where id='a1a1a1a1-0000-4000-8000-000000000002'$q$), 'OK:1', 'réactivation du projet autorisée');
select is(tests.state_as('authenticated', tests.u('idle'), $q$insert into management_next.actions(org_id,project_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1a1a1a1-0000-4000-8000-000000000002','après réactivation')$q$), 'OK:1', 'projet réactivé : INSERT action de nouveau possible');

-- ===== R5 / R7 : surfaces de contournement fermées pour les rôles applicatifs =====
select is(tests.state_as('authenticated', tests.u('idle'), 'set session_replication_role = replica'), '42501', 'authenticated ne peut pas désactiver les triggers (session_replication_role)');
-- (SET ROLE n'est pas testable ici : il s'évalue sur l'utilisateur de SESSION, superuser dans ce banc, authenticator en cloud.)
select ok(not has_function_privilege('service_role','management_next.create_organization(text)','EXECUTE')
          and not has_function_privilege('service_role','management_next.role_in(uuid)','EXECUTE'), 'service_role : aucun EXECUTE sur les fonctions du schéma (R7)');

select * from finish();
rollback;
