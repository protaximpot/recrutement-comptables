# J28 — Porte de sécurité d'import BEST POS (spécification exécutable)

**Auteur :** CHAT (architecte/QA) · **Exécutant :** CODE/CODEX · **Statut :** spec à valider par Yahia avant codage.
**Principe :** rien ne s'importe ni ne se publie automatiquement. Tout fichier douteux part en **quarantaine** avec un rapport lisible. Aucune écriture en production sans validation Yahia.

---

## 1. Table de contrôle `import_registry` (vérité de ce qui est importé)

| Colonne | Type | Rôle |
|---|---|---|
| id | serial | clé |
| fichier_nom | text | nom exact du .mdb |
| fichier_md5 | text | empreinte unique (anti-doublon) |
| magasin_detecte | text | OBRIEN / PIE9 (détecté par CONTENU) |
| type_base | text | inventaire / transaction |
| date_min, date_max | date | plage couverte par le fichier |
| nb_lignes_source | bigint | total lignes lues à la source |
| nb_tables | int | nb de tables trouvées |
| date_reception | timestamptz | dépôt |
| operateur | text | qui a déposé |
| statut | text | RECU / QUARANTAINE / VALIDE / IMPORTE / REJETE |
| motif | text | raison si quarantaine/refus |
| batch_id | uuid | lot d'import (permet rollback données) |
| drive_archive_id | text | id Google Drive de l'original archivé |
| checksum_post | text | somme de contrôle après import (fidélité) |

---

## 2. Porte de sécurité — contrôles PRÉ-import (dans l'ordre, bloquants)

Chaque échec → **QUARANTAINE** (ou REFUS) + ligne `import_registry` + rapport Yahia. On NE passe à l'étape suivante que si la précédente est PASS.

| # | Contrôle | Règle | Décision si échec |
|---|---|---|---|
| G1 | **Lisibilité** | le .mdb s'ouvre, tables attendues présentes, non corrompu | QUARANTAINE « fichier illisible/corrompu » |
| G2 | **Doublon** | `fichier_md5` déjà en statut IMPORTE ? | STOP « doublon déjà importé » (ignore, pas une erreur) |
| G3 | **Magasin par contenu** | marqueur interne (ex. en-tête « Pour Epilyspieix », ID magasin) == magasin déclaré | QUARANTAINE « magasin incohérent (fichier vs contenu) » |
| G4 | **Bon client/structure** | empreinte tables+colonnes == fingerprint EPILYS BEST POS connu | QUARANTAINE « structure/client inattendu » |
| G5 | **Anti-base périmée** | `date_max(fichier)` ≥ `date_max(prod)` du magasin | REFUS « base plus ancienne que la production » |
| G6 | **Plage de dates** | `date_min ≤ date_max`, pas de date future > J+1, pas de date < plancher (ex. 2019) | QUARANTAINE « dates aberrantes » |
| G7 | **Volume plausible** | `nb_lignes` dans ±50 % de la moyenne historique du magasin | QUARANTAINE « volume anormal, vérifier » |
| G8 | **Espace disque** | espace libre ≥ 2 × taille SQL projetée (index+temp) | REFUS « espace insuffisant » |
| G9 | **Encodage** | conversion CP1252→UTF-8 forcée ; zéro caractère `�` dans les libellés | QUARANTAINE « encodage à corriger » |

> **Note G9 (bug déjà visible)** : les CSV Z montrent `Quantit�` → la source est en Windows-1252, pas UTF-8. Sans forçage, les noms d'articles/rayons se corrompent et cassent les jointures.

**Décision finale :** G1→G9 tous PASS ⇒ statut **VALIDE** ⇒ import en **staging** (jamais direct en prod).

---

## 3. Contrôles POST-conversion — prouver que rien n'a changé (fidélité)

Objectif : répondre à la crainte de Yahia « la conversion a-t-elle changé mes chiffres ? ». On **sépare** deux preuves :

**(A) Fidélité brute** (la conversion n'altère pas la donnée) :
- `nb_lignes_SQL == nb_lignes_source` par table.
- `SUM(colonne_montant_brute)` source == SQL (au cent près).
- nb colonnes + types attendus respectés.
- échantillon aléatoire de N lignes comparé champ par champ.
- échec ⇒ **ROLLBACK** du `batch_id`, statut REJETE.

**(B) Couche BI** (le calcul des dollars est correct) :
- pour chaque jour avec un **rapport Z** : comparer l'agrégat SQL vs Z, **par jour + rayon + paiement**.
- statut par ligne : `OFFICIEL_Z` / `ACCESS_VOLUME` / `NON_CALCULABLE` / `A_CORRIGER` + écart $ / % / cause.
- **Limite connue :** $ non reconstructible depuis les transactions Access (ex. 10-fév : 4959/5934 lignes VE à prix 0). ⇒ **dollars officiels = Z uniquement** ; Access = volumes/tendances. **TPS/TVQ jamais estimé depuis Access.**

---

## 4. Liste des tests MINIMUMS avant tout import réel (acceptation)

| # | Test | Attendu |
|---|---|---|
| T1 | Re-déposer le même MD5 | refusé « doublon » |
| T2 | Base PIE9 étiquetée OBRIEN | quarantaine « magasin incohérent » |
| T3 | Base dont `date_max` < prod | refus « base périmée » |
| T4 | .mdb d'une autre structure | quarantaine « client/structure inattendu » |
| T5 | Accents post-conversion | é/è corrects, **zéro `�`** |
| T6 | Fidélité (base témoin) | nb lignes + somme montant source == SQL |
| T7 | Disque plein simulé | refus propre, pas de demi-import |
| T8 | Relancer 2× le même import | pas de doublon de lignes (idempotent) |
| T9 | Réconciliation Z | écart SQL vs Z documenté par jour/rayon |
| T10 | Rollback d'un `batch_id` | données retirées, prod intacte |
| T11 | Fichier quarantainé | n'altère **rien** en prod |
| T12 | Metabase | #13 / #14 / #15 intacts après import |

---

## 5. Ordre de construction (rappel)

1. `import_registry` + porte de sécurité (G1–G9) + quarantaine.
2. Conversion .mdb standardisée (1 hôte, UTF-8, cast types, checksum).
3. Import des **7 Z PIE9 vérifiés** comme tables OFFICIEL_Z (étalon — prêts).
4. Vue de réconciliation (contrôles A + B).
5. Metabase staging → validation Yahia → prod.

---

## 6. Pour Yahia — à valider en français simple

La « porte de sécurité » **refuse automatiquement** une base si :
- c'est **la même** déjà importée (doublon) ;
- c'est le **mauvais magasin** (vérifié dans le contenu, pas juste le nom) ;
- c'est une base **plus vieille** que ce qu'on a déjà (éviter d'écraser du récent) ;
- ce n'est **pas le bon logiciel/client** (structure inconnue) ;
- les **dates sont aberrantes** ou le **volume anormal** ;
- il n'y a **pas assez d'espace disque** ;
- les **accents sont cassés** (encodage).

Tout fichier refusé va en **quarantaine** avec une note expliquant pourquoi — **rien n'est importé ni publié sans ton feu vert**.

👉 **VALIDÉ PAR YAHIA (2026-06-02) :** les 7 motifs de refus/quarantaine sont acceptés, et le seuil de volume **±50 %** est retenu pour le pilote. Règle confirmée : tout fichier douteux → quarantaine, **aucune publication Metabase sans validation Yahia**.

## 7. Artefacts exécutables livrés
- `sql/import_registry.sql` — schéma `epilys_ops` : table `import_registry`, table `reconciliation_jour`, vue `v_import_dernier`.
- `porte_securite.py` — implémentation de référence des contrôles G1–G9 (à brancher sur PostgreSQL côté hôte ; éléments schéma marqués `[VERIFIER]`).
- `tests_minimum_import.md` — les 12 tests d'acceptation (T1–T12) + squelette pytest + données de référence Z.
