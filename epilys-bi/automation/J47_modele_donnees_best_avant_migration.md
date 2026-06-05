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
| **QteMain** (stock) | 92 % rempli **mais 84 % NÉGATIF** | stock **NON FIABLE** (réception non saisie → `QteMain ≈ −QteVendu`) |
| Actif | 99,1 % | actif/inactif |
| DateVendu | 99,5 % | dernière vente → **dormant** |
| DateRecu | 32,0 % | dernière réception |
| FournisseurAutre1-4 (+Coutant) | — | **multi-fournisseur** par article |
| NoFournisseur / CUP1 / QteEntrepot | <1 % | peu/pas utilisés |

→ **`Inventaire` est la MEILLEURE source coût/fournisseur/stock** (66 / 69 / 92 %), **bien supérieure à `Day`** (cout 30-44 %, fournisseur 17-24 %). Badge `CATALOGUE_À_VALIDER` (prix catalogue ≠ prix réellement vendu).

### B.2 `Fournisseur` (126) — contacts seulement
Nom, adresse, tél, courriel, contact, terme, transporteur. **`TotalAchat` et `DernierAchat` = VIDES (0/126)** → **pas d'historique d'achat fournisseur** ici.

### B.3 `Departement` (34) — référentiel + mapping comptable
Departement, Description, `NonAdd` (= CONSIGNE), `Taxe1..4`, **`GL`** (lien grand livre), `Profit`, `Groupe`, `Cat`. Utile pour le **fiscal/compta** (mapping GL).

### B.4 `Historique` (64 267) — par article, mensuel 202507→202606
`QuantiteVendu` / `MontantVendu` (Σ ≈ 14,3 M$) = **utilisable pour tendances/rotation**. ⚠️ **`MontantAchete` = CORROMPU** (Σ = 23 **000 milliards**, 4 583 lignes aberrantes) → **inutilisable** (borne anti-aberration, même classe que CORRECTIONS).

### B.5 ACHATS / COMMANDES / RÉCEPTIONS — **RÉSOLU (preuve)**
- **`Commande`** (PO : `NoCommande, NoFournisseur, Commande`=commandé, `Recu`=reçu, `DateLiv`) existe **mais = 1 ligne stub** → **module bons d'achat NON utilisé**.
- `Fournisseur.TotalAchat`/`DernierAchat` **vides** ; `Historique.MontantAchete` **corrompu**.
- Seule trace réception = `Articles.QteAchete` (cumul) + `DateRecu` (32 %, dernière date), **pas de log transactionnel**.
- **CONCLUSION : achats fournisseurs NON EXPLOITABLES aujourd'hui depuis BEST.** La table `Commande` **existe** (`NoCommande, NoFournisseur, Date, NoArticle, CoutantBrut, Coutant, Commande, Recu, BO, DateLiv, Traite`) mais est **quasi vide → à valider** (pas un « absent » définitif). → source officielle achats = **comptabilité / factures fournisseurs (QuickBooks)**.

> `InventaireOld.mdb` (14 Mo) = **ancien snapshot** (mêmes tables), non détaillé ici.

---

## E. MATRICE — Information → Source → Fiabilité → Usage

| Information | Source principale | Source secondaire | Fiabilité | Sammy | Yahia | Commentaire |
|---|---|---|---|:--:|:--:|---|
| CA / TTC / taxes / paiements | **Z/Day** ou rapport mensuel BEST | — | `OFFICIEL` (au cent) | ✅ | ✅ | dollars officiels |
| Prix réellement vendu | **Z/Day** (`Prix`) | — | `OFFICIEL` | ✅ | ✅ | — |
| Coût article | **Inventaire `Articles.Coutant/CoutMoyen`** (66 %) | Z/Day `Coutant` (30-44 %) | `CATALOGUE_À_VALIDER` | ❌ | ✅ | prix catalogue ≠ vendu |
| Marge | Z/Day `Prix` − Inventaire `Coutant` | — | `À_VALIDER` (coût partiel) | ❌ | ✅ | poids = artefact |
| Fournisseur (article) | **Inventaire `Articles.Fournisseur`** (69 %) + `Fournisseur` (126) | Z/Day (17-24 %) | `À_VALIDER` | ❌ | ✅ | multi-fournisseur dispo |
| Stock | Inventaire `Articles.QteMain` | — | `NON_FIABLE` (84 % négatif) | ❌ | ✅ | réception non saisie → inutilisable tel quel |
| Dormant / actif | Inventaire `Actif` + `DateVendu` | Transaction (0 vente N j) | `VOLUME_FIABLE` | ❌ | ✅ | argent immobilisé |
| Tendance ventes article | Inventaire `Historique` (Qté/Montant Vendu) | Transaction (volumes) | `VOLUME_FIABLE` | (✅) | ✅ | 202507→202606 |
| Rotation | Historique ventes ÷ `QteMain` | — | `À_VALIDER` (stock non fiable) | ❌ | ✅ | dépend d'un stock réel |
| Mapping comptable (GL) | Inventaire `Departement.GL` | — | utile fiscal | ❌ | ✅ | export compta |
| **Achats fournisseurs** | **Comptabilité / factures (QuickBooks)** | BEST `Commande` (à valider) | `À_VALIDER` | ❌ | ✅ | `Commande` présente mais quasi vide ; `MontantAchete` corrompu |
| Réception marchandise | Inventaire `DateRecu`+`QteAchete` (cumul, 32 %) | — | `INCOMPLET` | ❌ | ✅ | pas de log transactionnel |

## C. `Transaction.mdb` — MOUVEMENTS / STOCK DYNAMIQUE ✅ ANALYSÉ (686 Mo)

**UNE seule table `Transaction`** (modèle plat, comme `Day`). Colonnes : `Date`, `Article`, `GrandeurCouleur`, **`Type`** (type de mouvement), `Quantite`, `Prix`, **`QteMain`, `QteEntrepot`, `QteReserve`, `QteCommande`** (stock dynamique après mouvement), `Employe`, `Note`, `DateExp`, `Change`.
- **Usage = MOUVEMENTS / VOLUMES / TENDANCES / STOCK DYNAMIQUE / HISTORIQUE LONG uniquement.** ⚠️ **`Prix` souvent 0 → JAMAIS pour les dollars officiels** (prouvé J30 : des centaines de milliers de lignes VE à prix 0).
- **Clé relation** : `Transaction.Article` ↔ `Inventaire.Articles.NoArticle`.
- **`Type`** = à décoder (vente / retour / réception / ajustement) — c'est la clé pour isoler les mouvements ; à cartographier avant usage.
- **Volumes déjà mesurés (J30)** : OBRIEN fév 763 830 / mars 706 879 / avril 147 123 (avril Access tronqué) → badge `VOLUME_FIABLE`, à comparer aux quantités Z.

> **Extraction (résout la « priorité Articles ») :** `access_parser` **plante** (overflow) sur `Articles`. **`mdbtools` (`mdb-export`) lit `Articles` proprement** — déjà fait ici : **13 093 lignes, tous les taux mesurés (B.1)**. ⇒ **Pipeline d'extraction = `mdbtools`**, pas access_parser. (Si un `.mdb` est réellement corrompu : Compact & Repair Access, ou export CSV depuis BEST.)
> *Note versions :* le snapshot Mac de Codex montre 64 tables / Fournisseur 126 lignes ; le fichier uploadé = 58 tables / Fournisseur 126 (mon « 300 » initial = sur-comptage wc multiligne, corrigé). Staging Codex = Fournisseur 117 → écart 9 à réconcilier (même classe que Articles).

---

## D. ÉTAT DE L'ÉTAPE « COMPRENDRE » (quasi terminée)
- ✅ **Z/Day** (A) · ✅ **Inventaire** (B) · ✅ **Transaction** schéma (C) · ✅ **Achats** = hors BEST (B.5).
- **Carte des relations (ERD)** : `Articles.NoFournisseur`↔`Fournisseur` · `Articles.Departement`↔`Departement` · `Historique.ArticleID`↔`Articles` · `Transaction.Article`↔`Articles.NoArticle` · `Day.Departement`↔`Departement`.
- **Outil d'extraction retenu** : **mdbtools** (`mdb-export`) — fiable sur `Articles` (access_parser overflow).
- **Reste** : décoder les valeurs `Transaction.Type` (sur données réelles) + extraire `Articles` en prod via mdbtools.

## F. CONTRÔLE QUALITÉ CATALOGUE `Articles` ✅ (mesuré sur 13 093 lignes via mdbtools)
Extraction : `mdb-export Inventaire.mdb Articles` → `EPILYS_OBRIEN_Articles.csv` (mdbtools fiable ; access_parser plante).

| Contrôle | Nb | % | Lecture |
|---|--:|--:|---|
| Coût manquant (`Coutant`&`CoutMoyen`=0) | 4 508 | 34,4 % | marge incalculable sur 1/3 du catalogue |
| Fournisseur manquant | 4 105 | 31,4 % | fournisseur à compléter sur 1/3 |
| Département manquant | 3 | 0,0 % | ✅ quasi parfait |
| Prix vente = 0 | 654 | 5,0 % | à vérifier (articles non tarifés) |
| **Coût > Prix (marge négative)** | 194 | 1,5 % | erreurs de prix ou produits d'appel → revue |
| **Stock négatif (`QteMain`<0)** | **11 046** | **84,4 %** | 🔴 **stock NON fiable** (`QteMain ≈ −QteVendu`, réception non saisie) |
| Articles inactifs | 114 | 0,9 % | à exclure des vues actives |
| Articles balance/poids | 171 | 1,3 % | marge « aberrante » normale (balances) → isoler |

**Constat structurant :** pas de réception saisie (`Commande` vide) ⇒ **`QteMain ≈ −QteVendu`** ⇒ **stock inexploitable** (84 % négatif + aberrations jusqu'à 878 G). Le stock ne pourra servir qu'après une **vraie gestion des réceptions** (hors BEST actuel).

## G. PLAN DE MIGRATION — table par table, avec badges
> Règle : migrer **en staging**, badger chaque champ, **rien en prod/Metabase sans Yahia**. Borne anti-aberration partout (QteMain/MontantAchete corrompus).

| Table | Migrer | Champs FIABLES | Champs PARTIELS / À VALIDER | À EXCLURE | Voit |
|---|:--:|---|---|---|---|
| **Z/Day** (ou Z officiel parsé) | ✅ couche $ | CA, TTC, TPS, TVQ, paiements, prix, caissier, facture, dept | Coûtant (30-44 %), Fournisseur (17-24 %) | `VD`, CORRECTIONS, aberrants | Sammy+Yahia ($) |
| **Inventaire.Articles** | ✅ référentiel | NoArticle, Article, Departement (100 %), PrixVente (95 %), Actif | Coutant (66 %), Fournisseur (69 %), DateRecu (32 %) | **QteMain (non fiable)**, CUP1, QteEntrepot | Yahia |
| **Inventaire.Fournisseur** | ✅ référentiel | Nom, coordonnées, terme | — | TotalAchat/DernierAchat (vides) | Yahia/Akram |
| **Inventaire.Departement** | ✅ référentiel | Departement, Description, **GL**, NonAdd, taxes | — | — | Yahia (fiscal) |
| **Inventaire.Historique** | ✅ tendances | QuantiteVendu, MontantVendu, Date | QuantiteAchete | **MontantAchete (corrompu)** | Yahia/Akram |
| **Inventaire.Commande** | ⏸ non | — | tout (quasi vide) | — | — |
| **Transaction.Transaction** | ✅ volumes | Date, Article, Type, Quantite, Employe | QteMain dynamique | **Prix (jamais $)**, aberrants | Yahia/Akram |
| **Achats fournisseurs** | ⛔ hors BEST | — | — | — | (compta/QuickBooks) |

**Gouvernance Sammy/Yahia :** Sammy = ventes/CA/rayons/affluence/saisons ($ officiels) ; **jamais** coûts, marges, fournisseurs, stock. Yahia = tout + fiabilité + contrôle.

**Décision Codex/Yahia (validée) :** stock = NON FIABLE → **KPI rupture / surstock / valeur inventaire / rotation stock = BACKLOG** (jusqu'à mise en place/validation des réceptions) ; `QteMain` jamais utilisé comme stock réel. Coût/fournisseur/marge = **Yahia seulement, badge « catalogue à valider »**. Anomalies catalogue exportées : `EPILYS_OBRIEN_Articles_ANOMALIES.csv` (5 191 articles).

> **Règle d'or maintenue :** chaque chiffre = une source + un badge ; on ne mélange pas officiel, estimé et incomplet ; on ne migre une table qu'après l'avoir comprise.

---

## H. ÉTAT STAGING FINAL — validé QA (2026-06-05)
**Verdict : GO QA Yahia · NO-GO publication automatique.** Réserves CHAT **fermées par Codex** (vérif PG + ré-import mdbtools, pas juste documentées).

| Table | Staging | Statut |
|---|--:|---|
| Articles | **13 093** (clé NoArticle unique, 0 vide, 0 doublon) | GO |
| Fournisseur | **126** (était 117 → ré-importé mdbtools ; les 9 manquants étaient référencés par des articles = vraie perte corrigée) | GO |
| Departement | 34 | GO |
| Historique ventes utiles | **62 911** (était 59 988 → l'ancienne source PG avait **perdu des ventes mai/juin 2026** ; ré-importé mdbtools) | GO |
| Transaction | 5 011 859 (volumes/tendances only) | GO |
| Z Day détail | 449 080 | GO |

**Garde-fous confirmés :** `QteMain` NON FIABLE (jamais stock), `Transaction.Prix` exclu des $, **aucune prod / Metabase / portail Sammy touché**.
**Réserve ouverte (NON bloquante staging) :** la vue badges est **par objet/table**, pas encore **par champ** → à enrichir **avant** de construire les cockpits Yahia/Sammy.
**Réf. :** `RAPPORT_QA_YAHIA_J47_STAGING_EPILYS_2026-06-05.md` (Codex, local).
