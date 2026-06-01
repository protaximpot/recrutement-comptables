# J19 — Checkpoint : couche finance quotidienne + dashboard #15

**Date :** 2026-06-01
**Auteur :** CHAT (analyse)
**Exécutant :** CODE (VPS PostgreSQL + Metabase)
**Mode :** additif, réversible. Aucune modification des tables sources.

## Objectif

Passer de l'analyse (3 rapports Z validés) à un **livrable Metabase interactif** :
dollars officiels visibles **avec niveau de fiabilité explicite**, filtres type Power BI,
et explications pour Sammy.

## Ce qui est livré (versionné dans le repo)

| Fichier | Rôle |
|---|---|
| `sql/00_audit_vente_article.sql` | **Étape 0 bloquante** — tranche la source de `obrien_vente_article` |
| `sql/10_v_finance_journee_calculee.sql` | Vue `epilys_bi.v_finance_journee_calculee` |
| `sql/99_rollback.sql` | Rollback PostgreSQL ciblé |
| `metabase/dashboard_finance_quotidienne.md` | Spec dashboard #15 : 12 cartes + filtres + textes Sammy |

## Règles de fiabilité (statut_fiabilite)

- `CONFIRME_BEST` — un Z existe → dollars officiels (CA, taxes, TTC, profit).
- `ESTIME_BASE` — pas de Z, estimation Access plausible → **non officiel, jamais fiscal**.
- `ECART_A_VERIFIER` — estimation Access douteuse/aberrante → à investiguer.
- `NON_MESURABLE` — ni Z ni Access exploitable.
- (+ `flag_calibration` = ECART_ELEVE/OK sur les jours témoins où Z **et** Access existent.)

## Faits confirmés (recoupés sur les PDF BEST)

| Date | CA HT | TPS | TVQ | TTC | Profit | Marge |
|---|---|---|---|---|---|---|
| 2026-01-01 | 180 193,55 | 694,59 | 1 389,29 | 182 534,71 | 84 823,82 | 47,1 % |
| 2026-02-01 | 182 816,25 | 707,90 | 1 415,61 | 185 276,86 | 89 308,49 | 48,9 % |
| 2026-05-06 | 16 057,00 | 45,69 | 91,50 | 16 213,69 | 7 356,11 | 45,8 % |

Rapprochement GL : écart +1,83 $ (01-01) / +1,52 $ (02-01) = **arrondissement caisse**.

## Points de vigilance (à régler par CODE avant publication)

1. **Schéma réel inconnu de CHAT** → confirmer les colonnes (`information_schema`) et ajuster les alias marqués `[VERIFIER]` dans la vue.
2. **Nom de la table Access** (`obrien_transaction` = placeholder) → mettre le vrai nom.
3. **`obrien_vente_article` à auditer** → exécuter `00_audit...` et renvoyer le verdict à CHAT/Yahia. Ne pas publier la couverture 65,5 % avant.
4. **Infra** : dernier round LEAD signale ERP/relay-api HTTP DOWN (3005/3456). Vérifier que Metabase (3003) est up avant build.

## Garde-fous respectés

- Aucun DROP/TRUNCATE/UPDATE sur les tables sources.
- Schéma dédié `epilys_bi` (isolé), vue `CREATE OR REPLACE`.
- Rollback fourni (SQL + Metabase `/tmp/j19_finance_rollback.sql` à générer par CODE).
- Tester les 12 requêtes avant création des cartes.
- **Pas de promotion prod sans validation Yahia.**

## Verdict global

- **Dollars officiels (Z, taxes, TTC, profit, rapprochement GL)** : fiables, prêts.
- **Couverture Vente article** : **à vérifier** (étape 0 bloquante).
- **CA estimé Access** : à afficher uniquement avec badge `ESTIME_BASE`, non officiel.
- **Statut** : prêt à exécuter par CODE après étape 0 ; attente validation Yahia avant prod.
