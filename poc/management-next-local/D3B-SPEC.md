# D3B-SPEC — Récupération, autorisations et journalisation protégée

**Statut : spécification uniquement. Aucun développement D3b.** Ce document ne crée aucun objet SQL, aucun rôle, aucune table, aucune fonction. Il fixe ce qui devra être construit, prouvé et revu **avant tout usage hébergé**. NO-GO `indxone-Hub`, 0 € et absence de production inchangés.
Décisions entrantes (validées) : **D1** un compte Auth supprimé n'est jamais bloqué par Management · **D2** un projet archivé est figé (actions : ajout, modification, suppression) · **D3a** un détenteur humain unique du rôle d'administration · **D3b** (principe) traçabilité protégée + procédure testée avant tout usage hébergé.

## 1. Rôles et autorisations

| Acteur | Peut | Ne peut pas |
|---|---|---|
| **Détenteur D3a** (humain désigné, unique) | Exécuter les procédures P1–P5 ci-dessous, uniquement via le chemin d'administration journalisé | Agir hors journal ; déléguer sa session ; utiliser `service_role` comme raccourci |
| Owner / editor / viewer d'une organisation | Leurs droits applicatifs (RLS) | Toute procédure d'administration ; lire ou écrire le journal |
| `service_role` | Rien (aucun GRANT, aucun EXECUTE — prouvé par tests 01/05 et mutant M21) | Contourner la RLS pour Management |
| `anon` | Rien | — |
| CI, agents IA (Claude, ChatGPT) | Essais **locaux**, données fictives | Tout accès à un projet hébergé, à ses clés ou à des données réelles |

Principes : moindre privilège ; aucune action d'administration sans ligne de journal (atomicité, §3) ; motif obligatoire ; le détenteur étant **unique**, la séparation des tâches est **impossible aujourd'hui** : elle est compensée par un journal infalsifiable (§3), un ancrage externe de sa tête de chaîne et une **revue différée** par un second acteur (humain ou IA) qui ne détient pas le rôle. À réviser dès qu'il existe un second détenteur.

## 2. Procédures de récupération

Toutes : (a) préconditions vérifiées, (b) exécutées par le détenteur D3a, (c) une entrée de journal **dans la même transaction**, (d) vérification, (e) retour arrière décrit.

**P1 — Détecter une organisation sans owner actif.** Déclencheur : contrôle périodique (au moins quotidien en usage hébergé, hebdomadaire en essai) et après toute suppression de compte Auth. Requête de référence : `CORRECTIONS.md`. Résultat : liste d'identifiants, jamais de contenu. Retour arrière : sans objet (lecture seule). Journal : exécution + nombre de résultats.

**P2 — Rétablir un owner.** Préconditions : org identifiée par P1 ; candidat = compte existant **avec accès produit** ; demande du candidat ou d'un membre de l'org tracée (motif). Étape : poser une appartenance `owner` pour le candidat (la garde du dernier owner ne s'applique pas à l'administration, par D1). Vérification : P1 ne remonte plus l'org ; le candidat voit l'org. Retour arrière : retirer cette appartenance (seul cas où la garde du dernier owner n'interdit pas l'opération car l'administration n'a pas d'identité). Journal : org, candidat, motif, avant/après.

**P3 — Restaurer une organisation (sélectif).** Procédure prouvée localement : `scripts/export_org.sh` puis `scripts/restore_org.sh`. Préconditions : sauvegarde identifiée (date, empreinte), comptes membres présents dans l'Auth cible **et** dans `product_access`, organisation absente de la cible (sinon refus `MN007`). Contraintes PostgreSQL **actives** : projets restaurés actifs, actions, puis réarchivage ; aucun `session_replication_role`, aucun trigger ni FK désactivé ; refus `MN008` si le mode de session n'est pas `origin`. Tout ou rien (transaction unique, verrou consultatif par organisation, contrôles d'intégrité avant COMMIT). Vérification : empreintes des quatre tables, autres organisations inchangées, rôles revérifiés. Retour arrière : la transaction échouée ne laisse rien ; après succès, supprimer l'organisation par la séquence d'incident documentée (réactivation des projets archivés, suppression, sans contournement). Journal : org, source de sauvegarde, empreintes avant/après.

**P4 — Restaurer le schéma `management_next` complet.** `pg_restore -n management_next` sur une cible dont les comptes Auth existent, puis **étape obligatoire** `sql/restore/post_restore.sql` (l'ACL du schéma n'est pas restaurée). Vérification : empreinte DDL identique, suites de tests de droits. Retour arrière : restaurer l'état précédent depuis la sauvegarde pré-opération (qui doit exister : précondition). Journal : idem.

**P5 — Révoquer ou rétablir l'accès produit d'un compte.** Seule coupure immédiate d'un compte sur Management sans toucher à l'Auth partagé (prouvée par test 03). Journal : compte, motif, avant/après.

## 3. Journalisation protégée (cible à construire en D3b)

**Données par entrée** : identifiant monotone, horodatage serveur, identifiant de transaction, acteur (rôle de session + identifiant de session applicatif), procédure (P1–P5), organisation et/ou compte visés (UUID uniquement : pas d'e-mail ni de contenu métier), motif (référence de demande obligatoire), résumé avant/après (empreintes, comptes), empreinte de l'entrée précédente et empreinte de l'entrée (chaînage).

**Protections exigées**
1. **Écriture atomique** : l'action d'administration et son entrée de journal sont dans la même transaction ; sans entrée valide, l'action échoue.
2. **Ajout seul** : aucun rôle applicatif (`anon`, `authenticated`, `service_role`) ne peut lire, modifier, supprimer ni tronquer ; mise à jour, suppression et `TRUNCATE` refusés pour tous les rôles non-superuser, y compris le propriétaire de la table ; le journal n'est exposé ni par l'API de données ni par le temps réel.
3. **Chaînage** : chaque entrée engage l'empreinte de la précédente ; une fonction de vérification recalcule la chaîne et signale la première rupture. Verrou de chaîne pour que deux actions simultanées n'engendrent pas de bifurcation.
4. **Ancrage externe** : la tête de chaîne (numéro + empreinte) est publiée hors de l'instance à chaque session d'administration et au moins hebdomadairement (commentaire horodaté sur l'issue de suivi, 0 €). Cela détecte une réécriture complète par un superuser, que le chaînage seul ne détecte pas.
5. **Sauvegarde du journal hors instance**, chiffrée, avec la même procédure de restauration vérifiée que P3/P4.
6. **Données personnelles** : UUID seulement ; durée de conservation à décider (D3c) ; l'effacement d'un compte ne réécrit pas le journal : pseudonymisation par construction.

**Limites assumées** : un superuser de base peut réécrire tout le journal et sa chaîne ; seul l'ancrage externe le révèle, après coup. `session_replication_role` désactive les triggers de refus : cette option doit être interdite aux rôles d'exploitation (à vérifier en cloud, §5).

## 4. Plan de tests d'acceptation (à exécuter lors de l'implémentation D3b)

| ID | Preuve attendue | Type |
|---|---|---|
| T1 | Aucun rôle applicatif ne lit/écrit/supprime/tronque le journal ; absent de l'API | sécurité |
| T2 | Action d'administration sans entrée valide : refusée et sans effet (atomicité) | intégrité |
| T3 | Altération d'une entrée, suppression d'une entrée, insertion intercalée : la vérification de chaîne détecte la première rupture | intégrité |
| T4 | Deux actions d'administration simultanées : chaîne linéaire, aucun doublon de numéro | concurrence |
| T5 | Restauration du journal depuis sauvegarde : chaîne valide, tête = dernière ancre | restauration |
| T6 | Retour arrière de la migration D3b : schéma identique à l'état précédent, journal archivé avant suppression | retour arrière |
| T7 | P2, P3, P5 rejouées avec journal : une entrée par action, motif obligatoire, refus sans motif | procédures |
| T8 | Mutations : retirer chaque protection (trigger, GRANT, verrou, chaînage) fait échouer la suite | qualité |
| T9 | Rejeu complet sur Supabase CLI + Docker, puis sur une instance jetable validée par l'humain | cloud |

## 5. Non vérifié à ce jour (bloquant pour l'hébergé)
Nom, privilèges et limites réels du rôle d'administration en cloud (peut-il poser une appartenance sans identité ? modifier `session_replication_role` ?) ; exposition réelle de l'API de données au schéma `management_next` ; sauvegardes disponibles sur le plan Free et leur restauration ; comportement de l'Auth partagé à la suppression de compte ; lieu et chiffrement des sauvegardes hors instance à 0 €.

## 6. Journalisation transitoire (avant D3b) et gates
Tant que D3b n'est pas implémenté : **aucune procédure P1–P5 sur un projet hébergé**. En local (données fictives), la trace est le dépôt des sorties de tests (`evidence/`) et le commentaire de preuve sur l'issue de suivi.
Gates avant tout GO hébergé : D3b implémentée et T1–T9 PASS · revue de sécurité indépendante rendue · §5 levé · GO humain distinct.

## 7. Questions ouvertes pour l'humain
- **D3c** durée de conservation du journal et des sauvegardes ; **D3d** lieu et chiffrement des sauvegardes hors instance (0 €) ; **D3e** identité du second acteur de revue différée ; **D3f** fréquence de P1 en usage hébergé.
