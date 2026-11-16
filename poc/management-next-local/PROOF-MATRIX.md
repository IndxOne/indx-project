# Management Next — POC local : matrice de preuves (16/11/2026, révision 2)

> **Révision 2** : corrections R1/R2/R4/R5/R7 préparées (migration 0004), voir `CORRECTIONS.md`. Chiffres à jour : 148 assertions pgTAP, 21 mutants, course à deux sessions. Les lignes ci-dessous décrivent la révision 1 ; les risques R1/R4 y sont désormais corrigés.

Cible : PostgreSQL 16.15 **local**, socket Unix uniquement (`listen_addresses=''`), port 54329, pgTAP 1.3.2. Données 100 % fictives.
**Ce n'est pas Supabase** : pas de Docker ni de CLI Supabase ici ; rôles `anon/authenticated/service_role`, `auth.users` et `auth.uid()` sont des *stubs* (`sql/stubs/`). Hub, Synrel, Family, Identity et le dépôt legacy n'ont pas été contactés.
Rejouer : `bash scripts/run_all.sh` (sorties archivées dans `evidence/`).

| # | Preuve demandée | Verdict | Trace |
|---|---|---|---|
| 1 | Isolation RLS entre organisations et produits | **PASS (local)** | `evidence/30_*.log` tests 02/03 : owner d'une org vs autre org (lecture, insert, update, delete, auto-promotion, pivot via FK composite) ; compte Family sans droit Management : 0 ligne, création d'org refusée (MN003), auto-octroi refusé ; produit voisin lisible uniquement par son propriétaire ; empreinte `public+auth` identique avant/après migration, down, restauration |
| 2 | Rôles owner / editor / viewer | **PASS (local)** | 54 assertions : viewer = lecture seule partout ; editor = écrit projets/actions, ne gère ni membres, ni org, ne supprime pas de projet ; owner gère membres/rôles ; retrait d'appartenance et retrait du droit produit = perte d'accès immédiate ; un compte, deux rôles selon l'org |
| 3 | Intégrité projets / actions | **PASS (local)** | done→open refusé **au niveau base** (`MN002`, même superuser) ; `done_at` posé par la base et immuable ; `org_id/project_id/id` immuables (`MN001`, même superuser) ; FK composite `(project_id, org_id)` ; FK RESTRICT ; CHECK statuts/noms |
| 4 | Migrations indépendantes | **PASS (local)** | `evidence/40_*.log` (17 contrôles) : zéro référence legacy ; seule dépendance externe = `auth.users` ; idempotence (re-run runner, double exécution directe) ; down puis up = DDL identique ; drift de checksum refusé ; ordre voisin/management_next indifférent ; garde de cible : 12 refus (PGHOST distant, TCP, port 5432, `DATABASE_URL`, base hors convention, sans sentinelle, migration lancée à la main) |
| 5 | Sauvegarde / restauration sélective | **PASS (local)** | `evidence/50_*.log` (19 contrôles) : 40 006 actions ; dump schéma seul 0,14 s / 328 Ko ; restauration sur voisin déjà peuplé 0,29 s ; DDL+ACL+policies+données identiques, voisin inchangé ; restauration d'**une org** après incident en 0,04 s sans écraser les changements postérieurs des autres orgs ; droits revérifiés (pgTAP 01-04 + oracle par utilisateur) |
| — | Qualité des tests | **PASS** | 120 assertions pgTAP ; mutation : 17 mutants, 16 tués, 1 équivalent démontré (couche redondante) |
| 6 | Usage/quota Supabase (lecture seule) | **NON FAIT** | non demandé dans ce lot ; aucune connexion à Hub. Ne pas déduire de marges du POC local |
| 7 | Audit sécurité indépendant | **À FAIRE (autre acteur)** | je suis l'auteur : revue ChatGPT puis arbitrage humain |

## Défauts trouvés et corrigés pendant l'exécution (pour transparence)
- Mes tests : colonnes non accordées passées dans des INSERT, `created_by` oublié en superuser, ordre RLS/PK mal attendu → **corrigés dans les tests, contrats inchangés**.
- Garde SQL qui échouait fermé mais par erreur de compilation → réécrite avec un `REFUS` explicite.
- Empreintes instables : `pg_dump` ≥ 16.10 insère un jeton aléatoire `\restrict` → filtré. Un comparateur acceptait deux valeurs vides → durci.
- **Trouvaille réelle de procédure** : `pg_restore -n management_next` ne recrée ni le schéma ni son ACL ; sans correctif `authenticated` perd tout accès (échec fermé, pas de fuite). Étape obligatoire ajoutée : `sql/restore/post_restore.sql`.

## Risques ouverts (constatés, non corrigés — décisions produit/sécurité requises)
Voir `evidence/70_*.log`.
- **R1** le dernier owner peut se rétrograder → org sans owner. **R2** suppression du compte Auth du dernier owner (cascade) → org orpheline. → règle « dernier owner » à décider.
- **R3** oracle limité : un owner distingue « accès produit » de « pas d'accès/inexistant » (l'existence d'un compte n'est pas révélée).
- **R4** aucune règle sur les projets archivés (une action peut y être ajoutée).
- **R5** `session_replication_role=replica` désactive les triggers pour un superuser : interdire ce privilège aux rôles cloud.
- **R7** `service_role` contourne la RLS en cloud : n'accorder aucun GRANT sans revue.

## Limites local ≠ cloud (non prouvé ici)
Privilèges par défaut réels de Supabase pour les nouveaux schémas/fonctions ; exposition PostgREST (`db-schemas`) et Realtime ; claims JWT réels (ici GUC posés à la main) ; Auth partagé (cascade `auth.users`, extraction des IDs, SMTP) ; **Storage non couvert** (aucun objet en V0) ; sauvegardes/PITR et quotas du plan Free ; event trigger `ensure_rls` de Hub ; 61 migrations existantes de Hub (collisions de noms de rôles/fonctions non testées).
Le brouillon `management-next-poc-cadrage.zip` n'était pas accessible dans mon environnement : contrats écrits depuis zéro d'après le GO. La vision V0–V3 n'a pas été lue : le modèle V0 minimal (organisations, appartenances, projets, actions) est le mien.

## Décision proposée (avis de l'auteur, à contre-revoir)
**GO conditionnel** pour une *recette de préproduction hors données réelles* ; **NO-GO maintenu** pour l'hébergement sur `indxone-Hub` et toute production tant que : (a) revue sécurité indépendante rendue ; (b) R1/R2 tranchés ; (c) les écarts cloud ci-dessus sont rejoués sur un Supabase local officiel (CLI+Docker) puis une instance jetable validée par vous ; (d) mesures de quota Free relevées en lecture seule.
