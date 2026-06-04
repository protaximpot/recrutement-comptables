# J47 — Modèle de données BEST POS : comprendre AVANT de migrer

**Auteur :** CHAT (QA/archi) · **Statut :** spec, aucun changement prod.
**Principe (validé par Yahia) :** lire les `.mdb` comme Access, comprendre **schéma + types + relations + taux de remplissage + systèmes de codes** AVANT toute migration SQL. On ne migre plus rien à l'aveugle.
**Méthode :** `mdb-schema` (DDL), `mdb-tables`, `MSysRelationships` (relations déclarées), profilage des colonnes (taux de remplissage) sur fichiers réels OBRIEN.

---

## PLAN EN 5 ÉTAPES
1. **Schéma + relations** de chaque base (`Inventaire Ob.mdb`, `Transaction Ob.mdb`, `Z/AAAAMMJJ.mdb`).
2. **Dictionnaire de données** : table/colonne → sens métier + type + **taux de remplissage**.
3. **Carte des relations (ERD)** : quelles tables se joignent, par quelle clé.
4. **Décodage des systèmes de codes** (codes `Day`, départements, modes de paiement).
5. **ENSUITE seulement** : table de mapping migration colonne par colonne + badge de fiabilité.

---

## A. COUCHE Z JOURNALIÈRE — `Z/AAAAMMJJ.mdb` ✅ ENTIÈREMENT ANALYSÉE

### A.1 Nature
**Export PLAT (journal de caisse), PAS un modèle relationnel.**
- `MSysRelationships` = **vide** → **aucune relation déclarée**.
- Tables : `Day` (toutes les données), + `Paiement`, `Interets`, `ServiceNo`, `Customer` = **VIDES (0 ligne)** dans l'export journalier.
- La table `Day` est **entièrement dénormalisée** : produit, fournisseur, département, caissier sont recopiés sur chaque ligne.

### A.2 Types (tranche le doute SCALE)
`Prix`, `Coutant`, `Qte`, `EscDirect` = **`Currency`** → **déjà décimaux**. **Aucun ×10000 à appliquer sur ces fichiers.** `Taxe1..4` = **Booléens** (taxable oui/non), pas des montants.

### A.3 Dictionnaire de la table `Day` (taux mesurés, jour complet 01-fév, 50 143 lignes, 9 caisses)
| Colonne | Type | % rempli | Rôle |
|---|---|--:|---|
| ID | Long | 100 % | clé ligne |
| NoCaisse | Text(5) | 100 % | **caisse** (00201→00209) |
| NoFacture | Long | 100 % | n° facture (⚠ non unique sur grosses journées) |
| Date | DateTime | 100 % | **horodatage** transaction |
| Code | Text(2) | 100 % | **type de ligne** (cf. A.4) |
| Qte | Currency | 100 % | quantité (poids possible) |
| Prix | Currency | 99,6 % | **prix réel appliqué** (= $) |
| Description | Text(60) | 100 % | libellé article |
| Vendeur | Text(10) | 100 % | **caissier** |
| CodeUPC | Text(30) | 82,7 % | code-barres |
| Departement | Text(16) | 89,0 % | **rayon** |
| RefMEV | Text | 82,7 % | signature module Revenu Québec (MEV) |
| **Coutant** | Currency | **30-44 %** | **coût — PARTIEL** → marge partielle |
| **Fournisseur** | Text(30) | **17-24 %** | **fournisseur — PARTIEL** |
| NoFournisseur | Text(16) | 2,8 % | code fournisseur (rare) |
| Taxe1 / Taxe2 | Bool | 6,2 % | drapeau taxable TPS / TVQ |
| MixMatch | Text(16) | 7,2 % | **promo** (« 8 pour 1.99$ ») |
| EscDirect | Currency | 3,9 % | escompte direct |
| Note | Text(40) | 23,2 % | note (autorisations carte…) |
| AFor | Integer | 100 % | facteur « X pour » |
| **Inutilisés (0 %)** | — | 0 % | Siege, Client, Localisation(+Ang), Sequence(+Ang), Note(Ang), CUP1-5, Groupe, RapportCaissier/Poste |

### A.4 Système de codes `Day` (sémantique confirmée)
| Code | Sens | Signe | Usage agrégat |
|---|---|---|---|
| `IT` / `IB` | vente article | + | ventes |
| `DP` | vente département | + | ventes |
| `ED` | escompte | − | net ventes |
| `RE` | **retour** | − | **net cash + TTC** |
| `RO` | arrondissement | ± | TTC |
| `PM` | **paiement par mode** | + | encaissé |
| `T1` / `T2` | **TPS / TVQ** | + | taxes |
| `CA` | annulation | | corrections |
| `PV` | après-vente | | corrections |
| `D1` | tiroir ouvert | compteur | — |
| `RD` | duplicata reçu | compteur | — |
| `VD` | **récap interne** | | **EXCLURE** (double) |

### A.5 Règles d'agrégation PROUVÉES (au cent, 3 jours témoins)
- **TPS** = Σ(`Prix` \| `T1`) · **TVQ** = Σ(`Prix` \| `T2`)
- **TTC encaissé** = Σ(`Prix` \| `Code`∈`PM`,`RE`,`RO`)
- **ARGENT net** = Σ(`Prix` \| `PM` & Desc=`ARGENT`) **+** Σ(`Prix` \| `RE`)  *(les retours sont en argent)*
- **Cartes** (DEBIT/VISA/MC/AMEX) = Σ(`Prix` \| `PM` & Desc=mode), directes
- **Consigne** = Σ(`Qte`·`Prix` \| `Departement`=CONSIGNE)
- **Nb factures** = **compteur officiel du Z** (≠ distinct `NoFacture`, qui sous-compte)
- **VENTES AVANT TAXES** = Σ ventes − escomptes (`ED`)
- **À EXCLURE** : `VD` (récap) et toute valeur aberrante (borne anti-aberration : section CORRECTIONS des rapports = corrompue, jusqu'à 464 G$).

### A.6 Conséquence migration (couche Z)
- **Dollars fiables** : CA, taxes, paiements, prix → `OFFICIEL_Z`.
- **Coût / marge / fournisseur** : **partiels (17-44 %)** → `À VALIDER`, compléter via `Inventaire`.
- **Complétude** : un fichier complet = **toutes les caisses** ; un fichier partiel (1-2 caisses) sous-compte → réconcilier vs Z officiel (cf. J46).

---

## B. `Inventaire.mdb` — CATALOGUE ✅ ANALYSÉ (OBRIEN 20260603, 30 Mo)

**58 tables.** Clés : `Articles`, `Fournisseur`, `Commande`, `Departement`, `Historique`, `PrixSpeciaux`, `PaidOut`, `MixMatch`, `Employe`, `Retour`, `Service/Ingredients/Combo` (resto), `Tare` (poids).

### B.1 `Articles` — catalogue (13 093 lignes, 12 979 actifs) — taux mesurés
| Colonne | % rempli | Rôle |
|---|--:|---|
| NoArticle / Article | 100 / 99,8 % | clé + libellé |
| Departement | 100 % | rayon |
| PrixVente | 95,0 % | **prix catalogue** (≠ prix vendu) |
| **Coutant** | **65,5 %** | **coût catalogue** |
| CoutMoyen | 31,0 % | coût moyen pondéré |
| **Fournisseur** (nom) | **68,6 %** | fournisseur principal |
| **QteMain** (stock) | **91,7 %** | stock en main |
| Actif | 99,1 % | actif/inactif |
| DateVendu | 99,5 % | dernière vente → **dormant** |
| DateRecu | 32,0 % | dernière réception |
| FournisseurAutre1-4 (+Coutant) | — | **multi-fournisseur** par article |
| NoFournisseur / CUP1 / QteEntrepot | <1 % | peu/pas utilisés |

→ **`Inventaire` est la MEILLEURE source coût/fournisseur/stock** (66 / 69 / 92 %), **bien supérieure à `Day`** (cout 30-44 %, fournisseur 17-24 %). Badge `CATALOGUE_À_VALIDER` (prix catalogue ≠ prix réellement vendu).

### B.2 `Fournisseur` (300) — contacts seulement
Nom, adresse, tél, courriel, contact, terme, transporteur. **`TotalAchat` et `DernierAchat` = VIDES (0/300)** → **pas d'historique d'achat fournisseur** ici.

### B.3 `Departement` (34) — référentiel + mapping comptable
Departement, Description, `NonAdd` (= CONSIGNE), `Taxe1..4`, **`GL`** (lien grand livre), `Profit`, `Groupe`, `Cat`. Utile pour le **fiscal/compta** (mapping GL).

### B.4 `Historique` (64 267) — par article, mensuel 202507→202606
`QuantiteVendu` / `MontantVendu` (Σ ≈ 14,3 M$) = **utilisable pour tendances/rotation**. ⚠️ **`MontantAchete` = CORROMPU** (Σ = 23 **000 milliards**, 4 583 lignes aberrantes) → **inutilisable** (borne anti-aberration, même classe que CORRECTIONS).

### B.5 ACHATS / COMMANDES / RÉCEPTIONS — **RÉSOLU (preuve)**
- **`Commande`** (PO : `NoCommande, NoFournisseur, Commande`=commandé, `Recu`=reçu, `DateLiv`) existe **mais = 1 ligne stub** → **module bons d'achat NON utilisé**.
- `Fournisseur.TotalAchat`/`DernierAchat` **vides** ; `Historique.MontantAchete` **corrompu**.
- Seule trace réception = `Articles.QteAchete` (cumul) + `DateRecu` (32 %, dernière date), **pas de log transactionnel**.
- **CONCLUSION : les achats fournisseurs ne sont PAS dans BEST.** → la source achats = **comptabilité (QuickBooks / factures fournisseurs)**, hors BEST. **Fin de la chasse « à chercher ».**

> `InventaireOld.mdb` (14 Mo) = **ancien snapshot** (mêmes tables), non détaillé ici.

---

## E. MATRICE — Information → Source → Fiabilité → Usage

| Information | Source principale | Source secondaire | Fiabilité | Sammy | Yahia | Commentaire |
|---|---|---|---|:--:|:--:|---|
| CA / TTC / taxes / paiements | **Z/Day** ou rapport mensuel BEST | — | `OFFICIEL` (au cent) | ✅ | ✅ | dollars officiels |
| Prix réellement vendu | **Z/Day** (`Prix`) | — | `OFFICIEL` | ✅ | ✅ | — |
| Coût article | **Inventaire `Articles.Coutant/CoutMoyen`** (66 %) | Z/Day `Coutant` (30-44 %) | `CATALOGUE_À_VALIDER` | ❌ | ✅ | prix catalogue ≠ vendu |
| Marge | Z/Day `Prix` − Inventaire `Coutant` | — | `À_VALIDER` (coût partiel) | ❌ | ✅ | poids = artefact |
| Fournisseur (article) | **Inventaire `Articles.Fournisseur`** (69 %) + `Fournisseur` (300) | Z/Day (17-24 %) | `À_VALIDER` | ❌ | ✅ | multi-fournisseur dispo |
| Stock | **Inventaire `Articles.QteMain`** (92 %) | — | `VOLUME_FIABLE` | ❌ | ✅ | Akram |
| Dormant / actif | Inventaire `Actif` + `DateVendu` | Transaction (0 vente N j) | `VOLUME_FIABLE` | ❌ | ✅ | argent immobilisé |
| Tendance ventes article | Inventaire `Historique` (Qté/Montant Vendu) | Transaction (volumes) | `VOLUME_FIABLE` | (✅) | ✅ | 202507→202606 |
| Rotation | Historique ventes ÷ `QteMain` | — | `VOLUME_FIABLE` | ❌ | ✅ | Akram |
| Mapping comptable (GL) | Inventaire `Departement.GL` | — | utile fiscal | ❌ | ✅ | export compta |
| **Achats fournisseurs** | **HORS BEST** (compta/QuickBooks/factures) | — | `A_CHERCHER_HORS_BEST` | ❌ | ✅ | `Commande` vide, `MontantAchete` corrompu |
| Réception marchandise | Inventaire `DateRecu`+`QteAchete` (cumul, 32 %) | — | `INCOMPLET` | ❌ | ✅ | pas de log transactionnel |

## C. `Transaction.mdb` — MOUVEMENTS ✅ SCHÉMA OBTENU (686 Mo)
*(schéma via Codex/access_parser ; données via mdbtools)*

**UNE seule table `Transaction`** (modèle plat, comme `Day`). Colonnes utiles : `Date`, `Article`, **`Type`** (type de mouvement), `Quantite`, `Prix`, `QteMain` (stock après mouvement), `Employe`, …
- **Usage = VOLUMES / TENDANCES / HISTORIQUE LONG uniquement.** ⚠️ **`Prix` souvent 0 → JAMAIS pour les dollars** (prouvé J30 : des centaines de milliers de lignes VE à prix 0).
- **Clé relation** : `Transaction.Article` ↔ `Inventaire.Articles.NoArticle`.
- **`Type`** = à décoder (vente / retour / réception / ajustement) — c'est la clé pour isoler les mouvements ; à cartographier avant usage.
- **Volumes déjà mesurés (J30)** : OBRIEN fév 763 830 / mars 706 879 / avril 147 123 (avril Access tronqué) → badge `VOLUME_FIABLE`, à comparer aux quantités Z.

> **Extraction (résout la « priorité Articles ») :** `access_parser` **plante** (overflow) sur `Articles`. **`mdbtools` (`mdb-export`) lit `Articles` proprement** — déjà fait ici : **13 093 lignes, tous les taux mesurés (B.1)**. ⇒ **Pipeline d'extraction = `mdbtools`**, pas access_parser. (Si un `.mdb` est réellement corrompu : Compact & Repair Access, ou export CSV depuis BEST.)
> *Note versions :* le snapshot Mac de Codex montre 64 tables / Fournisseur 126 lignes ; le fichier analysé ici (uploadé) = 58 tables / Fournisseur 300 — **snapshots à dates différentes**, mêmes structures.

---

## D. ÉTAT DE L'ÉTAPE « COMPRENDRE » (quasi terminée)
- ✅ **Z/Day** (A) · ✅ **Inventaire** (B) · ✅ **Transaction** schéma (C) · ✅ **Achats** = hors BEST (B.5).
- **Carte des relations (ERD)** : `Articles.NoFournisseur`↔`Fournisseur` · `Articles.Departement`↔`Departement` · `Historique.ArticleID`↔`Articles` · `Transaction.Article`↔`Articles.NoArticle` · `Day.Departement`↔`Departement`.
- **Outil d'extraction retenu** : **mdbtools** (`mdb-export`) — fiable sur `Articles` (access_parser overflow).
- **Reste** : décoder les valeurs `Transaction.Type` (sur données réelles) + extraire `Articles` en prod via mdbtools.

> **Règle d'or maintenue :** chaque chiffre = une source + un badge ; on ne mélange pas officiel, estimé et incomplet ; on ne migre une table qu'après l'avoir comprise.
