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

## B. `Inventaire Ob.mdb` — ⏳ EN ATTENTE DU SCHÉMA
*(catalogue, coûts, fournisseurs, stock, départements — c'est ICI que vivent les vraies relations)*
À documenter dès réception : tables, colonnes, types, `MSysRelationships`, clés produit↔fournisseur↔département↔stock, taux de remplissage.
**Commande :** `mdb-schema "Inventaire Ob.mdb"` + `mdb-tables -1 "Inventaire Ob.mdb"` + export `MSysRelationships`.

## C. `Transaction Ob.mdb` — ⏳ EN ATTENTE DU SCHÉMA
*(mouvements/historique long → VOLUMES/TENDANCES uniquement ; prix souvent 0 → jamais pour les $)*
À documenter : tables, relations, clé article, types de mouvement (vente/retour/réception ?), période couverte.
**Commande :** `mdb-schema "Transaction Ob.mdb"` + `mdb-tables -1 "Transaction Ob.mdb"` + export `MSysRelationships`.

---

## D. CE QU'IL RESTE À OBTENIR POUR FINIR L'ÉTAPE « COMPRENDRE »
1. Schémas (texte) d'`Inventaire Ob.mdb` et `Transaction Ob.mdb` → compléter B et C.
2. Carte des relations (ERD) une fois B/C remplis.
3. Tables ACHATS / COMMANDES / RÉCEPTIONS / FOURNISSEUR : à localiser (absentes du Z journalier).

> **Règle d'or maintenue :** chaque chiffre = une source + un badge ; on ne mélange pas officiel, estimé et incomplet ; on ne migre une table qu'après l'avoir comprise.
