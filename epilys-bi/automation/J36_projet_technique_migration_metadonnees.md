# J36 — Projet technique : Migration SQL + métadonnées (pipeline d'ingestion gouverné)

**Auteur :** CHAT (architecte/QA) · **Exécutant :** CODE/CODEX · **Statut :** spec, aucun changement prod.
**Périmètre :** CHANTIER 2, **séparé du cockpit Sammy**. Sammy voit un tableau simple ; Yahia voit l'outil de contrôle complet (migration, sources, anomalies, fiabilité).
**S'appuie sur :** J28 (porte de sécurité G1–G9 + `import_registry`), J29 (calibration Access↔Z), J30 (confiance migration), J35 (matrice source → fiabilité).

---

## 0. En une phrase
Quand Yahia branche une **nouvelle base Access BEST POS**, le système doit l'**identifier, la vérifier, la convertir, la tracer et l'archiver** — sans jamais écraser l'existant ni publier dans Metabase sans contrôle, et en gardant pour **chaque chiffre** sa source, sa date et sa fiabilité.

---

## 1. Le pipeline en 8 étapes (du USB au dashboard)

```
[USB / .mdb]
   │
   ▼
(1) RÉCEPTION        → copie en zone de dépôt, calcul MD5, ligne import_registry = RECU
   │
   ▼
(2) IDENTIFICATION   → magasin par CONTENU (G3) + type base + plage dates + nb tables/lignes
   │
   ▼
(3) PORTE SÉCURITÉ   → G1..G9 (J28). Échec → QUARANTAINE + rapport. Aucun import.
   │   ├─ déjà importée ?  (G2 doublon MD5)
   │   ├─ trop ancienne ?  (G5 anti-base périmée)
   │   └─ mauvais client / mauvaise clé ? (G3 magasin, G4 structure)
   │
   ▼
(4) CONVERSION       → Access → PostgreSQL en STAGING (jamais prod), UTF-8, cast types, batch_id
   │
   ▼
(5) CONTRÔLE FIDÉLITÉ→ nb lignes + sommes source == SQL (A) ; réconciliation Z (B). Échec → ROLLBACK
   │
   ▼
(6) ARCHIVAGE        → .mdb original déposé dans Google Drive (lecture seule), drive_archive_id stocké
   │
   ▼
(7) VALIDATION YAHIA → revue du rapport d'import (écarts, anomalies). Feu vert manuel.
   │
   ▼
(8) PUBLICATION      → bascule staging → prod → Metabase. statut = IMPORTE. Historique conservé.
```

---

## 2. Mapping des 10 objectifs → mécanisme → statut

| # | Objectif demandé | Mécanisme | Où | Statut |
|---|---|---|---|---|
| 1 | **Identifier le magasin** | détection par CONTENU (marqueur interne), pas par nom de fichier | G3 (J28) | ✅ spécifié |
| 2 | **Nouvelle ou déjà importée ?** | empreinte `fichier_md5` vs `import_registry` (statut IMPORTE) | G2 (J28) | ✅ spécifié |
| 3 | **Ancienne base / mauvais client / mauvaise clé** | anti-base périmée (`date_max` < prod) + fingerprint structure + magasin incohérent | G5 + G4 + G3 | ✅ spécifié |
| 4 | **Convertir Access → PostgreSQL** | conversion standardisée 1 hôte, UTF-8 (CP1252→UTF-8), cast types, en **staging** | étape (4) + G9 | ✅ spécifié |
| 5 | **Garder les métadonnées** | `import_registry` : fichier, MD5, magasin, type, date_min/max, nb_tables, nb_lignes, date_reception, opérateur, batch_id | table J28 §1 | ✅ spécifié (+ colonnes à ajouter, voir §3) |
| 6 | **Ne jamais écraser sans validation** | import en staging + `batch_id` rollbackable + bascule prod **manuelle** (Yahia) | étapes (4)(7)(8) | ✅ spécifié |
| 7 | **Archiver l'Access original dans Drive** | dépôt lecture seule + `drive_archive_id` dans le registre | étape (6) | 🟡 **à détailler (ce doc §4)** |
| 8 | **Publier Metabase seulement après contrôle** | staging → validation → prod ; aucune carte branchée sur staging | étape (8) + J28 §5 | ✅ spécifié |
| 9 | **Historique des imports et des écarts** | `import_registry` (tous statuts conservés) + `reconciliation_jour` (écarts SQL vs Z) | J28 §1 + sql | ✅ spécifié |
| 10 | **Par KPI : source, date, fiabilité** | couche métadonnée KPI : chaque mesure porte `source`, `date_donnee`, `badge_fiabilite`, `import_id` | **nouveau, ce doc §5** | 🟡 **à ajouter** |

> Conclusion : **8/10 déjà couverts** par J28–J35. Restent à formaliser : **§4 archivage Drive** et **§5 traçabilité fiabilité par KPI**. C'est l'objet de ce document.

---

## 3. Métadonnées d'import — colonnes à ajouter à `import_registry`

J28 §1 couvre l'essentiel. On complète pour répondre pleinement à l'objectif 5 (anomalies) et 7 (archivage) :

| Colonne (ajout) | Type | Rôle |
|---|---|---|
| `nb_anomalies` | int | nb de lignes/contrôles en anomalie détectés à l'import |
| `anomalies_detail` | jsonb | liste structurée (type, table, exemple, gravité) |
| `tables_detail` | jsonb | par table : nom, nb_lignes, nb_colonnes, somme_montant |
| `scale_detecte` | int | facteur d'échelle figé (1 ou 10000) par sanity check |
| `periode_label` | text | libellé humain (ex. « OBRIEN 2026-01 → 2026-04 ») |
| `drive_archive_url` | text | lien Drive lisible (complément de `drive_archive_id`) |
| `valide_par` | text | qui a donné le feu vert (objectif 6) |
| `valide_le` | timestamptz | quand |
| `publie_le` | timestamptz | bascule prod/Metabase (objectif 8) |

---

## 4. Archivage de l'Access original dans Google Drive (objectif 7)

**But :** garder la preuve d'origine, intacte, jamais ré-écrite.

**Arborescence cible (Drive partagé) :**
```
1 COMPAGNIE / epilys / BEST / 05_ARCHIVES_ACCESS /
   └─ <MAGASIN> / <AAAA> / <AAAAMMJJ_HHMM>_<nom-fichier>.mdb
```

**Règles :**
- Dépôt **après** conversion réussie + contrôle fidélité PASS (étape 6, avant publication).
- **Lecture seule** ; un MD5 déjà archivé n'est jamais redéposé (cohérent avec G2).
- Le nom inclut **magasin + période + horodatage de réception** → retrouvable sans ouvrir le fichier.
- `import_registry.drive_archive_id` + `drive_archive_url` renseignés → chaque ligne SQL est rattachable à son `.mdb` source.
- **Connecteur Drive = CREATE-ONLY** dans notre environnement : on **crée** l'archive, on ne **remplace** jamais (donc pas d'écrasement possible — propriété recherchée).
- Si l'upload Drive échoue : statut reste `VALIDE` (non publié), motif « archivage Drive à refaire » — **on ne publie pas tant que l'original n'est pas archivé**.

---

## 5. Traçabilité par KPI : source · date · fiabilité (objectif 10)

C'est le **lien entre le pipeline (J36) et le cockpit (J33/J34) via la matrice J35**. Chaque mesure affichée doit pouvoir répondre : *d'où vient ce chiffre, de quelle date, à quel point est-il fiable ?*

**Principe :** toute table de faits BI porte 3 colonnes de gouvernance, en plus de la donnée :

| Colonne | Exemple | Rôle |
|---|---|---|
| `source_ref` | `Z/Day` · `Inventaire.mdb` · `Transaction.mdb` | d'où vient la valeur (cf. J35) |
| `import_id` | FK → `import_registry.id` | quel import / quel `.mdb` / quel MD5 |
| `badge_fiabilite` | `OFFICIEL_Z` · `CALCULE_DAY_A_VALIDER` · `VOLUME_FIABLE` · `ESTIME_CALIBRE` · `A_CHERCHER` | niveau de confiance (vocabulaire unique J30/J35) |

**Vue de service `v_kpi_provenance`** (lecture, pour Metabase admin) :
```
KPI | valeur | source_ref | date_donnee | badge_fiabilite | import_id | fichier_source | importe_le
```
→ Permet, sous chaque carte Yahia, d'afficher la phrase de fiabilité (J33 §8) et de cliquer jusqu'au `.mdb` d'origine.

**Règle d'or (reprise de J35 / diapo Sammy) :**
> On ne mélange pas les chiffres officiels, estimés et incomplets : chaque KPI a une source et un niveau de fiabilité.

---

## 5.ter Règle du « jour incomplet » (exclusion par défaut) — ajout 2026-06-04

**Problème :** le jour où la clé USB est apportée / la base est téléchargée est souvent une **journée partielle** (la caisse n'a pas fini de tourner, le Z du jour n'est pas clôturé). L'inclure fausse les totaux et les comparaisons.

**Règle (gouvernance import) :**
- La **date du jour d'apport/téléchargement de la base est EXCLUE par défaut** du chargement et de l'affichage.
- Cette date est marquée **`JOUR_INCOMPLET`** (quarantaine logique), distincte d'un rejet : la donnée existe mais **n'est ni agrégée ni publiée** tant que la journée n'est pas confirmée close.
- Le rapport « actif » s'arrête donc à **J-1 (la veille)**.
- *Exemple :* base apportée le **2026-06-03** → on charge/affiche **jusqu'au 2026-06-02** ; le **2026-06-03** reste `JOUR_INCOMPLET` jusqu'à confirmation (prochaine base contenant un 03 clôturé, ou validation Yahia).

**Implémentation :** paramètre `date_apport` (déduit du nom de dossier/fichier ou de `date_reception`) → filtre `date_jour < date_apport` à l'extraction ET borne haute des vues BI. Trace dans `import_registry` : `date_max_publiable = date_apport − 1 j`.
**Réf. exécution :** script Codex `J37_extract_obrien_z_day_summary.py` (extraction OBRIEN Z/Day excluant explicitement la date d'apport) — **à vérifier (CHAT) : nb de jours, dernière date incluse = veille, aucun jour d'apport agrégé.**

---

## 6. Séparation des deux mondes (rappel — NON négociable)

| | **Cockpit SAMMY** | **Outil technique YAHIA** |
|---|---|---|
| Voit | tableau simple : CA, ventes, rayons, affluence, événements | **+** migration, sources, anomalies, fiabilité, écarts Z, calibration |
| Métadonnées | masquées (badge implicite « officiel ») | **visibles** : source_ref, import_id, badge, écarts |
| Coûts / marges / fournisseurs | non | oui (sensible) |
| Contrôle d'import | n'existe pas pour lui | **console d'import** (registre, quarantaine, validation) |

Gouvernance Metabase : collections séparées + permissions. Sammy ne voit **jamais** la console technique ni les coûts.

---

## 7. Garde-fous (repris et confirmés)
- Aucune écriture prod sans validation Yahia · aucune publication Metabase depuis staging.
- Aucun `DROP/ALTER/UPDATE` destructif ; imports **idempotents** (rejouer ≠ doubler).
- Dollars = `Z/Day` uniquement ; Access = volumes (J30).
- Tout fichier douteux → **quarantaine** + rapport lisible (J28).
- Original `.mdb` **toujours archivé** avant publication ; jamais ré-écrit.
- Échelle ×10000 (SCALE) figée par sanity check avant tout agrégat $.
- **Jour d'apport/téléchargement EXCLU par défaut** (`JOUR_INCOMPLET`) ; les rapports s'arrêtent à la veille (cf. §5.ter).

---

## 8. Ordre de construction (chantier 2)
1. `import_registry` enrichi (J28 §1 + ce doc §3) + porte G1–G9.
2. Conversion standardisée staging + `batch_id` + contrôle fidélité (A/B).
3. `reconciliation_jour` (historique des écarts SQL vs Z).
4. Archivage Drive `05_ARCHIVES_ACCESS/` + renseignement `drive_archive_id`.
5. `v_kpi_provenance` (source · date · fiabilité par KPI).
6. Console d'import Yahia (lecture registre + quarantaine + bouton « valider/publier »).
7. Tests d'acceptation T1–T12 (J28 §4) verts → pilote.

> **Rien ne se publie tant que : porte PASS + fidélité PASS + original archivé + validation Yahia.**
