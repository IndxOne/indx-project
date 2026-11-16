# Corrections préparées — Management Next POC local (révision 2, 16/11/2026)

Statut : **préparé et prouvé en local uniquement**. Rien n'est fusionné, rien n'est appliqué sur un projet Supabase hébergé, aucune production, aucune dépense. Branche `fix/management-next-owner-archive-guards`, aucune PR. Les migrations 0001–0003 déjà prouvées ne sont pas modifiées : la correction est la migration additive `20261116000004_mn_owner_archive_guards.sql`.

| Risque | Correction préparée | Preuve |
|---|---|---|
| **R1** dernier owner qui se rétrograde ou se retire | Trigger `mn_guard_last_owner` (UPDATE de `role`, DELETE) : refus `MN005` si aucun autre owner **actif** (avec accès produit). Verrou consultatif par organisation. | Tests 05 (1–15). Course à deux sessions : avec verrou 1 owner reste ; **sans verrou 0** (témoin) — `evidence/55_*.log`. Mutants M18/M19 tués. |
| **R2** compte Auth du dernier owner supprimé | **Volontairement non bloquant** : supprimer un compte Family/Identity ne doit jamais échouer à cause de Management (indépendance des produits). Garde appliquée seulement aux actions avec identité (JWT). Org orpheline = **détectable** et **récupérable** par rôle d'administration. | Tests 05 (suppression de compte, requête de détection, récupération). |
| **R4** actions dans un projet archivé | Trigger `mn_guard_archived_project` (INSERT/UPDATE/DELETE d'actions) : refus `MN006`, même pour le superuser. Réactiver le projet pour modifier. | Tests 05 (16–24). Mutant M20 tué. |
| **R5** désactivation des triggers | Non corrigeable en SQL applicatif. Test : `authenticated` ne peut pas `SET session_replication_role`. À interdire côté rôles cloud. | Test 05 (27). Limite : `SET ROLE` non testable dans ce banc (évalué sur l'utilisateur de session, superuser ici). |
| **R7** `service_role` | Aucun GRANT ni EXECUTE accordé ; test + mutant M21. Toute Edge Function exigera une revue explicite. | Test 05 (28), M21 tué. |
| **R3** oracle du droit produit | **Accepté** en l'état (2 réponses distinctes seulement ; l'existence d'un compte n'est pas révélée). | `evidence/70_*.log`. |

Détection d'une organisation sans owner actif :
`select o.id from management_next.organizations o where not exists (select 1 from management_next.memberships m join management_next.product_access a using (user_id) where m.org_id = o.id and m.role = 'owner');`
Récupération (rôle d'administration, hors JWT) : insérer une appartenance `owner` pour un utilisateur ayant l'accès produit.

## Conséquence mesurée (à connaître)
Restaurer une organisation contenant un **projet archivé** échoue en mode normal (`MN006`, atomique, rien de restauré à moitié). Procédure : transaction avec `set local session_replication_role = replica`, puis **contrôle d'intégrité** (0 action orpheline, les clés étrangères n'étant pas vérifiées dans ce mode). Prouvé : `evidence/50_*.log` partie 2b.

## Décisions à prendre par l'humain
- **D1** Confirmer que supprimer un compte Auth ne doit **jamais** être bloqué par Management (recommandé : oui, org orpheline récupérable).
- **D2** Confirmer « projet archivé = figé » y compris suppression d'actions (recommandé : oui ; sinon relâcher le DELETE).
- **D3** Qui détient le rôle d'administration et la procédure de récupération en cloud (non défini ici).

## Toujours non fait
Rejeu sur Supabase CLI + Docker ; comportements cloud réels (privilèges par défaut, PostgREST, JWT, Storage, quotas) ; audit de sécurité indépendant ; relevé d'usage en lecture seule.

## Résultats de la révision
148 assertions pgTAP (+28) ; 21 mutants, 0 survivant réel ; course à deux sessions ; restauration sélective (org A, org avec projet archivé) ; migrations indépendantes (4) ; garde de cible (12 refus). Toutes les traces : `evidence/`.
