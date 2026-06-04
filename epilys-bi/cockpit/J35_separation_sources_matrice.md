# EPILYS — Séparation des sources + Matrice « Information → Source » (J35)

**Auteur :** CHAT · **Supervision/QA :** Codex · **Statut :** spec, aucun changement prod.
**Fiabilité ancrée sur mesures réelles** (3 fichiers OBRIEN ouverts : 2026-01-01 / 02-01 / 05-06).
**Badges :** `OFFICIEL_Z` · `CALCULE_DAY_A_VALIDER` · `VOLUME_FIABLE` · `ESTIME_CALIBRE` · `ECART_A_EXPLIQUER` · `A_CHERCHER`.

---

## 1. `Z/Day` — ce qui s'est RÉELLEMENT vendu à la caisse (DOLLARS OFFICIELS)
Ventes réelles en $ · **prix réellement vendu** (`Prix`) · taxes **TPS/TVQ** (`T1`/`T2`) · **modes de paiement** (`PM`) · **caissier** (`Vendeur`) · **facture** (`NoFacture`) · **heure** (`Date`) · **quantité vendue** (`Qte`) · **département** (`Departement`).
**Coûtant** (`Coutant`) et **Fournisseur** présents **mais partiels → à valider** (mesuré : Coutant ≈ **40 %**, Fournisseur ≈ **23 %** des lignes de vente).
> Échelle ×10000 (SCALE) · taxes/paiement = `Prix` sans ×Qte · CA à régler consigne nette.

## 2. `Inventaire.mdb` — ce que le magasin sait sur ses articles (CATALOGUE)
Catalogue articles · **prix catalogue** · **coût catalogue** · **stock actuel** · **fournisseur principal** · statut actif/dormant.
→ Sert au **fallback coût/fournisseur**, aux **achats** et aux **marges théoriques**. (Prix catalogue ≠ prix réellement vendu.)

## 3. `Transaction.mdb` — l'historique des mouvements (VOLUMES)
Mouvements d'articles : ventes, retours, ajustements, **réceptions si présentes** · **historique long (2020→)** · volumes et tendances.
> **Ne JAMAIS l'utiliser seul pour les dollars** (prix souvent 0). Volumes uniquement → `VOLUME_FIABLE`.

## 4. Tables ACHATS / RÉCEPTIONS — À CHERCHER (base complète BEST)
Non présentes dans le `.mdb` Z journalier (seulement `Day, Paiement, Interets, ServiceNo, Customer`). À chercher via `mdb-tables -1` sur chaque `.mdb` du dossier `Epilys Obrien/` :
`Achat · Commande · Reception · ReceptionMarchandise · BonCommande · LigneCommande · Fournisseur · Purchase · Supplier · PaidOut` — **toute table contenant** : fournisseur, date, **facture fournisseur**, **coût**, **quantité reçue**.
Candidats `.mdb` à inspecter : `Inventaire.mdb`, `Transaction.mdb`, `Tables.mdb`, `Compte.mdb`, `Compteurs.mdb`, `Location.mdb`, `Client.mdb`, `Caisse.mdb`.

---

## 5. MATRICE MAÎTRESSE — Information → Meilleure source → Fiabilité → Usage
| Information | Meilleure source | Source secondaire / fallback | Fiabilité (mesurée) | Badge | Usage dashboard |
|--|--|--|--|--|--|
| **CA réel (HT)** | `Z/Day` (Σ ventes − consigne nette) | — | TTC/taxes exacts au cent ; CA exact après consigne nette | `OFFICIEL_Z` | Sammy + Yahia — carte CA |
| **Total TTC** | `Z/Day` (Σ Prix \| PM,RE,RO) | — | **vérifié exact au cent** (3/3) | `OFFICIEL_Z` | Sammy + Yahia |
| **TPS / TVQ** | `Z/Day` (T1 / T2) | — | **vérifié exact au cent** (3/3) | `OFFICIEL_Z` | Yahia (fiscal) |
| **Paiement par mode** | `Z/Day` (PM by Description) | table `Paiement` | net (PM+RE+RO) = TTC au cent | `OFFICIEL_Z` | Yahia |
| **Quantité vendue** | `Z/Day` (`Qte`) | `Transaction.mdb` | fiable ; à comparer aux volumes | `OFFICIEL_Z` / `VOLUME_FIABLE` | Sammy |
| **Article vendu** | `Z/Day` (`CodeUPC`/`Description`) | `Inventaire.mdb` (libellé) | fiable | `OFFICIEL_Z` | Sammy + Yahia |
| **Prix vendu** | `Z/Day` (`Prix`) | — | **très fiable** (prix réel appliqué) | `OFFICIEL_Z` | Sammy + Yahia |
| **Coûtant vendu** | `Z/Day` (`Coutant`) | `Inventaire.mdb` (coût catalogue) | **partiel : ~40 % rempli** dans Day | `CALCULE_DAY_A_VALIDER` | Yahia |
| **Marge réelle** | `Z/Day` (Prix−Coutant) | + fallback `Inventaire` | **~40 % des lignes** ; poids = artefact à isoler | `CALCULE_DAY_A_VALIDER` | Yahia |
| **Fournisseur (article)** | `Inventaire.mdb` (fourn. principal) | `Z/Day` (~23 %, fourn. réel à la vente) | maître = catalogue ; Day partiel | `A_VALIDER` | Yahia / Akram |
| **Stock** | `Inventaire.mdb` | — | bon si bien rempli | `VOLUME_FIABLE` | Akram |
| **Rotation** | `Transaction.mdb` (ventes) + `Inventaire` (stock) | — | bon (volumes) | `VOLUME_FIABLE` | Akram |
| **Dormant** | `Transaction.mdb` (0 vente N j) + `Inventaire` (stock/actif) | — | très utile | `VOLUME_FIABLE` | Akram / Yahia |
| **Achat fournisseur** | table `Achat`/`Commande` **(à trouver)** | `Inventaire` (coût) en attendant | **inconnue tant que table non trouvée** | `A_CHERCHER` | Akram / Yahia |
| **Réception marchandise** | table `Reception` **(à trouver)** | `Transaction` type réception si présent | **inconnue** | `A_CHERCHER` | Akram |
| **Commande fournisseur** | table `Commande`/`BonCommande` **(à trouver)** | — | **inconnue** | `A_CHERCHER` | Akram |

## 6. Lecture simple (pour Sammy)
- **Ventes / prix / taxes / paiements** = `Z/Day`, **fiable et officiel**.
- **Coût / marge / fournisseur** = `Z/Day` quand présent (~40 % / ~23 %), **sinon catalogue `Inventaire.mdb`**.
- **Achats / réceptions / commandes** = **à localiser** dans la base complète BEST — **prochaine recherche prioritaire**.

## 7. Garde-fous
Dollars = `Z/Day` only · échelle ×10000 (SCALE figé par sanity check) · marge `CALCULE_DAY_A_VALIDER` tant que coût partiel · achats `A_CHERCHER` (ne rien promettre) · PIE-IX `Day` à confirmer · aucune prod/Metabase sans Yahia.
