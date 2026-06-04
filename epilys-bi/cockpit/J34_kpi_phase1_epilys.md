# EPILYS — Brainstorming KPI structuré + PHASE 1 exploitable (J34) — v2 (QA Codex intégrée)

**Magasins :** OBRIEN + PIE-IX · **Auteur :** CHAT (architecte) · **Supervision/QA :** Codex
**Statut :** document & plan. **Aucun changement Metabase/production. Aucun DROP/ALTER/UPDATE.**
**Sources :** `Z/AAAAMMJJ.mdb` table **`Day`** = DOLLARS OFFICIELS (vérifié au cent, OBRIEN) · `Transaction.mdb` = volumes/historique · `Inventaire.mdb` = catalogue/coût.
**Badges :** `OFFICIEL_Z` · `VOLUME_FIABLE` · `ESTIME_CALIBRE` · `ECART_A_EXPLIQUER`.

> ### ⚠️ CORRECTION CLÉ — ÉCHELLE DES MONTANTS (×10000)
> BEST stocke en interne `Prix`, `Coutant`, `Qte` en **grandeurs entières ×10000** (observé sur `Transaction.mdb` : brut 7500 → 0,75 $).
> - **Vérifié :** via `mdb-export`, la table `Day` ressort **déjà en décimal** (ex. `Prix=3.4900`) et reproduit le Z **au cent SANS division** (test CHAT 01-01/02-01/05-06).
> - **Donc :** ne JAMAIS faire `qte*prix` sur du **brut** sans connaître l'échelle. Introduire un facteur `SCALE` (= 1 si extraction décimale `mdb-export` ; = 10000 si chargement brut entier). **La sanity check (3 Z connus) tranche l'échelle AVANT tout usage.** Vérifier aussi le champ **`AFor`** (multiplicateur/quantité éventuel).

---

## A. MATRICE KPI COMPLÈTE
| # | KPI | Question métier | Source | Formule (montants ÷ SCALE) | Filtres | Comparaison | Cible | Badge |
|--|--|--|--|--|--|--|--|--|
|1|CA HT|Combien on vend (hors taxes) ?|Z/Day|Σ(Qte·Prix) ventes IT/IB/DP +ED net − consigne nette|magasin,période,dept|J-1,J-7,sem,mois,YoY,Hijri|Sammy+Yahia|OFFICIEL_Z|
|2|TTC encaissé|Argent réellement entré ?|Z/Day|Σ(Prix\|PM,RE,RO)|magasin,période,mode|J-1,J-7,mois|Sammy+Yahia|OFFICIEL_Z|
|3|TPS / TVQ|Taxes à remettre ?|Z/Day|Σ(Prix\|T1)/Σ(Prix\|T2)|magasin,période|mois,trim.|Yahia|OFFICIEL_Z|
|4|Profit brut|Combien on gagne ?|Z/Day|Σ((Prix−Coutant)·Qte) IT/IB/DP (si Coutant fiable)|dept,article|J-7,mois,YoY|**Yahia**|OFFICIEL_Z|
|5|Marge %|Rentabilité ?|Z/Day|profit ÷ CA HT (si Coutant fiable)|dept,article|mois,vs moy.|**Yahia**|OFFICIEL_Z|
|6|Nb factures|Achalandage ?|Z/Day|distinct NoFacture|magasin,heure,jour|J-7,sem,Hijri|Sammy|OFFICIEL_Z|
|7|Panier moyen|Valeur du ticket ?|Z/Day|CA HT ÷ nb factures|magasin,période|J-7,mois,Hijri|Sammy+Yahia|OFFICIEL_Z|
|8|Articles/panier|Taille du panier ?|Z/Day|Σ Qte ÷ nb factures|magasin,période|J-7,mois|Sammy|OFFICIEL_Z|
|9|CA par département|Quels rayons portent ?|Z/Day|group Departement|magasin,période|mois,YoY,Hijri|Sammy+Yahia|OFFICIEL_Z|
|10|CA/profit par article|Top/flop produits ?|Z/Day|group CodeUPC|dept,période|J-7,mois|Sammy(CA)/**Yahia(profit)**|OFFICIEL_Z|
|11|CA par caissier|Performance équipe ?|Z/Day|group Vendeur|période,magasin|J-7,mois|**Yahia**|OFFICIEL_Z|
|12|CA par heure|Heures de pointe ?|Z/Day+Transaction|group hour(ts)|jour,magasin|J-7,Ramadan|Sammy|OFFICIEL_Z / vol. VOLUME_FIABLE|
|13|Modes de paiement|Argent vs carte ?|Z/Day|Σ(Prix\|PM) by Description|période,magasin|mois|Yahia|OFFICIEL_Z|
|14|Retours $/taux|Trop de retours ?|Z/Day|Σ\|RE\| ; ÷ CA|caissier,période|J-7,vs moy.|Yahia|OFFICIEL_Z|
|15|Escomptes|Combien de rabais ?|Z/Day|Σ\|ED\||période,caissier|mois|Yahia|OFFICIEL_Z|
|16|Consigne (nette)|Dépôts bouteilles|Z/Day|consigne vendue − consigne crédit/retour|période|mois|Yahia|OFFICIEL_Z (à régler P1)|
|17|Top fournisseurs|Dépendance achat ?|Z/Day(Fournisseur)+Inv|Σ ventes/coût by Fournisseur|période|mois|**Yahia/Akram**|OFFICIEL_Z|
|18|Articles dormants|Argent immobilisé ?|Transaction+Inv|0 vente N j|dept,magasin|—|Yahia/Akram|VOLUME_FIABLE|
|19|Rotation|Vitesse d'écoulement ?|Transaction+Inv|ventes ÷ stock|dept|mois|Akram|VOLUME_FIABLE|
|20|Prix moyen/kg (poids)|Cohérence prix balances ?|Z/Day|Σ(Prix·Qte)÷Σ Qte (poids)|rayon poids|mois|Akram|OFFICIEL_Z|
|21|CA vs même jour Hijri N-1|Effet événement ?|Z/Day+dim_hijri|var $/%|événement|Hijri N-1|Sammy+Yahia|OFFICIEL_Z|
|22|CA rayons traditionnels|Produits maghrébins ?|Z/Day(groupe)|group rayon traditionnel|événement|Ramadan/Eid|Sammy|OFFICIEL_Z|
|23|Affluence horaire Ramadan|Quand staffer ?|Transaction+Day|factures/heure|jour Ramadan|J-7 Ramadan|Sammy|VOLUME_FIABLE|

## B. MODULE VENTES / FINANCE OFFICIEL (Z/Day)
Cartes : CA HT, TTC, TPS+TVQ, Profit & marge (Yahia), Nb factures, Panier moyen, CA par département, CA par heure, Modes de paiement, Retours & escomptes, **Corrections (VD/RE/RO — exclues du CA, montrées à part pour contrôle)**.
Formules (montants ÷ SCALE) : `TPS=Σ(Prix|T1)` · `TVQ=Σ(Prix|T2)` · `TTC=Σ(Prix|PM,RE,RO)`. **Exclure VD** (récap interne — à confirmer sur fichier).

### B.bis — PROFIT / MARGE : formule PRUDENTE (correction QA)
Ne pas mélanger ED/consigne/taxes. Formule recommandée :
```
revenu_articles = Σ(Qte·Prix | IT,IB,DP, dept<>CONSIGNE)   + Σ(Prix|ED)   # ED net (escompte, négatif)
cout_articles   = Σ(Qte·Coutant | IT,IB,DP, dept<>CONSIGNE, Coutant>0)
profit_brut     = revenu_articles − cout_articles
marge_%         = profit_brut ÷ revenu_articles
```
- **Marge affichée UNIQUEMENT si `Coutant` fiable** (renseigné, >0). Sinon afficher « coût manquant » et ne pas calculer de marge.
- Rayons au **poids** (balances) : marges aberrantes (artefact) → isoler, ne pas inclure dans la marge globale présentée.
- Taxes (T1/T2), paiements (PM), arrondissement (RO) **exclus** du profit.

### B.ter — CONSIGNE NETTE : À RÉSOUDRE EN PHASE 1 ⚠️
- `Day` contient **consigne vendue** (dépôt à l'achat) ET **consigne crédit/retour** (remboursement bouteilles rapportées). Mon calcul brut « dept=CONSIGNE en Σ(Qte·Prix) » a donné 259,88 / 353,60 — alors que la consigne **nette** officielle est 257,26 / 337,10.
- **C'est la cause probable du résidu CA de 2,62 $ / 16,51 $.**
- Phase 1 : identifier le code/signe de la **consigne crédit** (cf. « CONSIGNE CREDIT: −1,99 » vu dans le Z mensuel 20-fév) et faire `consigne_nette = consigne_vendue − consigne_credit`.
- **Ne PAS annoncer un CA exact tant que la consigne nette n'est pas réglée.** (TPS/TVQ/TTC, eux, sont déjà exacts au cent.)

## C. MODULE ACHAT / PRICING
Top 20 articles (CA/profit/quantité) · Top fournisseurs ($ vendus, coût, marge) · Marge par département · Marge négative (isoler poids) · Couverture coût/prix · Dormants (≥30/60/90 j) + valeur · Rotation · Surstock · Rupture probable · Écart prix catalogue vs appliqué. **Coûts/marges = Yahia/Akram seulement.**

## D. MODULE SAISONNALITÉ MAGHRÉBINE (différenciateur)
`dim_date_hijri` (grégorien↔Hijri + drapeaux RAMADAN / RAMADAN_10_DERNIERS / VEILLE_EID / EID_FITR / EID_ADHA / MAWLID / ACHOURA / FERIE_QC).
Cartes : CA vs même jour Hijri N-1 · profil intra-Ramadan (pic 10 derniers jours + veille Eid) · pic horaire (avant iftar / après tarawih) · rayons traditionnels par événement · Eid al-Adha=viande/agneau · Eid al-Fitr=pâtisserie/dattes · reco achat pré-événement.

### D.bis — Exemple de KPI ACHAT par événement (pour présentation Yahia)
| Produit | Vente/sem. normale | Vente/sem. Ramadan | Variation | Marge | Recommandation achat |
|--|--|--|--|--|--|
| Dattes | 1 200 $ | 4 800 $ | **+300 %** | ~25 % | Commander ×4, sécuriser 2 sem. avant |
| Feuilles de brick | 300 $ | 2 100 $ | **+600 %** | ~30 % | Stock fort dès pré-Ramadan |
| Frik / chorba | 250 $ | 1 500 $ | **+500 %** | ~28 % | Réassort hebdo Ramadan |
| Agneau / viande | 5 000 $ | 7 000 $ | +40 % (pic **Eid al-Adha**) | ~12 % | Pic à l'Eid al-Adha, pré-commande |
| Pâtisserie orientale | 800 $ | 2 500 $ (pic **Eid al-Fitr**) | +210 % | ~35 % | Montée fin Ramadan → Eid |
| Thé / café | 600 $ | 1 100 $ | +83 % | ~30 % | Réassort modéré |
*(Chiffres ILLUSTRATIFS — à remplacer par les vrais une fois la Phase 1 chargée.)*

## E. VARIATIONS (chaque axe)
J-1 · J-7 · semaine · MoM · YoY · MTD/YTD · même période Hijri N-1 · moyenne 4 dern. sem. → variation **$ ET %** (marge en points).

## F. PRÉSENTATION : SAMMY vs YAHIA (renforcé — QA)
- **SAMMY voit :** CA, TTC, panier, nb factures, **top rayons & top produits (en CA)**, affluence/heures, **événements religieux**, **recommandations d'achat**. 
- **SAMMY NE VOIT PAS :** coût d'achat, marge par article/département, fournisseurs, fiscal — **aucun coût/marge article visible à Sammy sans décision explicite de Yahia.**
- **YAHIA/ADMIN voit :** tout Sammy **+** coût, profit/marge (article/caissier/fournisseur), TPS/TVQ, réconciliation Z, écarts caisse, calibration.
- Mise en œuvre : **collections Metabase séparées + permissions** ; les cartes coût/marge dans la collection Yahia uniquement.

## G. BACKLOG PHASÉ
| Phase | Contenu | Effort | Risque | Dépendances |
|--|--|--|--|--|
|**1 — Finance officielle Z (OBRIEN)**|Import staging Z/Day read-only (échelle validée), vues finance jour/dept/caissier/heure/paiement, **validation 3 jours**, consigne nette|Moyen|Faible (read-only)|accès `.mdb` Z OBRIEN + mdbtools|
|**2 — Achat/pricing + saisonnalité**|Marge article/fournisseur, dormants/rotation, `dim_date_hijri`, Ramadan/Eid|Moyen-élevé|Moyen (coût/stock partiels, Hijri à valider)|Phase 1 + Inventaire + dates Hijri + mapping rayons|
|**3 — PIE-IX parité + alertes + auto-refresh**|Mettre PIE-IX au niveau OBRIEN (cf. §K), alertes, refresh quotidien, calibration|Élevé|Moyen|source Z PIE-IX confirmée + porte sécurité J28|

## H. PHASE 1 — PSEUDO-SQL (à adapter après extraction mdb-export/access_parser — NON FINAL)
> **Statut : pseudo-SQL.** À finaliser une fois l'extraction (mdb-export OU access_parser) et l'**échelle (SCALE)** confirmées par la sanity check. Schéma dédié `epilys_z_stage`, read-only. **Aucun DROP/ALTER sur l'existant.**

```sql
CREATE SCHEMA IF NOT EXISTS epilys_z_stage;

-- 1) Table brute + colonnes d'AUDIT / import idempotent
CREATE TABLE IF NOT EXISTS epilys_z_stage.z_day_raw (
    -- audit / idempotence
    source_file   text NOT NULL,      -- nom fichier .mdb (ex '20260201.mdb')
    file_md5      text NOT NULL,       -- empreinte du fichier source
    imported_at   timestamptz DEFAULT now(),
    store         text NOT NULL,       -- 'OBRIEN' | 'PIE9'
    date_jour     date NOT NULL,       -- AAAAMMJJ du fichier
    row_hash      text,                -- hash de la ligne (dédoublonnage)
    -- données Day (brut, échelle À CONFIRMER)
    id bigint, nocaisse text, nofacture text, dt text, code text,
    qte numeric, afor numeric, codeupc text, description text, departement text,
    coutant numeric, prix numeric, vendeur text, refmev text, fournisseur text, groupe text, mixmatch text,
    UNIQUE (file_md5, id)             -- ré-import du même fichier = pas de doublon
);
-- chargement (hors SQL) : pour chaque fichier, mdb-export Day -> ajouter source_file/file_md5/store/date_jour/row_hash -> \copy

-- 2) Vue typée : applique SCALE (1 si mdb-export decimal ; 10000 si brut) + borne anti-aberration
--    >>> SCALE EST DETERMINE PAR LA SANITY CHECK (section H.5) AVANT USAGE <<<
CREATE OR REPLACE VIEW epilys_z_stage.v_z_day AS
WITH p AS (SELECT 1::numeric AS scale)   -- [VERIFIER] 1 (mdb-export) ou 10000 (brut)
SELECT store, date_jour,
       to_timestamp(dt,'MM/DD/YY HH24:MI:SS') AS ts,     -- [VERIFIER format réel]
       code, departement, nofacture, vendeur, codeupc, description, fournisseur, groupe,
       qte/scale  AS qte, prix/scale AS prix, coutant/scale AS coutant,
       (qte/scale)*(prix/scale) AS montant_ligne
FROM epilys_z_stage.z_day_raw, p
WHERE abs(coalesce(prix,0)/scale) < 1e6 AND abs(coalesce(qte,0)/scale) < 1e5;  -- anti-aberration

-- 3) Finance jour (consigne NETTE à finaliser — cf. B.ter)
CREATE OR REPLACE VIEW epilys_z_stage.v_finance_jour AS
SELECT store, date_jour,
  round(SUM(montant_ligne) FILTER (WHERE code IN ('IT','IB','DP') AND departement<>'CONSIGNE')
      + SUM(prix)          FILTER (WHERE code='ED'),2)                       AS ca_ht,      -- ED net inclus
  round(SUM(prix) FILTER (WHERE code='T1'),2)                               AS tps,
  round(SUM(prix) FILTER (WHERE code='T2'),2)                               AS tvq,
  round(SUM(prix) FILTER (WHERE code IN ('PM','RE','RO')),2)                AS ttc,
  round(SUM(montant_ligne) FILTER (WHERE departement='CONSIGNE'),2)         AS consigne_brute,  -- [À NETTER]
  count(DISTINCT nofacture) FILTER (WHERE code IN ('IT','IB','DP','ED'))    AS nb_factures
FROM epilys_z_stage.v_z_day GROUP BY store, date_jour;
-- marge/profit : vue séparée (B.bis), affichée seulement si Coutant fiable.

-- 4) Déclinaisons : v_finance_dept / v_finance_caissier / v_finance_heure / v_paiement (idem v1, sur v_z_day)

-- ROLLBACK : DROP SCHEMA IF EXISTS epilys_z_stage CASCADE;  (schéma dédié, sans source)
```

### H.5 — MINI-PLAN DE VALIDATION (obligatoire avant d'élargir)
1. Importer **3 jours OBRIEN déjà contrôlés** : `20260101`, `20260201`, `20260506`.
2. Comparer **CA / TPS / TVQ / TTC / consigne / paiements** aux valeurs officielles :
   - 01-01 : CA 180 193,55 · TPS 694,59 · TVQ 1 389,29 · TTC 182 534,71
   - 02-01 : CA 182 816,25 · TPS 707,90 · TVQ 1 415,61 · TTC 185 276,86
   - 05-06 : CA 16 057,00 · TPS 45,69 · TVQ 91,50 · TTC 16 213,69
3. **Confirmer SCALE** (les scommes doivent tomber juste, pas ×10000). Régler la **consigne nette** jusqu'à CA exact.
4. **Seulement après** : élargir aux 333 jours OBRIEN, puis traiter PIE-IX (§K).

## I. ALERTES INTELLIGENTES
Rupture probable · Surstock/dormant · Baisse de marge · Hausse retours · Produit vedette · Pré-événement (Ramadan/Eid dans X j → liste achats) · Écart caisse · Prix/marge aberrant · Donnée aberrante (borne).

## J. LIMITES & GARDE-FOUS
- **Dollars = Z/Day uniquement** ; `Transaction.mdb` = volumes (prix=0).
- **Échelle ×10000** : confirmer SCALE par sanity check avant tout calcul.
- **Exclure `VD`** du CA (à confirmer) · **consigne nette** à régler (résidu 2,62/16,51 $) · **borne anti-aberration** (Z mensuel 20-fév 59,7 G$).
- **Marge** seulement si `Coutant` fiable ; rayons au poids = artefact.
- **Calendrier Hijri** à valider (±1 j).
- **Aucune mise en production / Metabase sans validation Yahia.**

## K. DISPONIBILITÉ DE LA SOURCE PAR MAGASIN (correction QA — ne rien supposer)
| Élément | **OBRIEN** | **PIE-IX** |
|--|--|--|
| `Z/AAAAMMJJ.mdb` (table `Day`, $ officiels journaliers) | ✅ **333 fichiers** (2025-05-08→2026-06-03), **vérifiés au cent** | ❓ **NON confirmé** — à vérifier sur le poste/Drive PIE-IX |
| Rapports Z **mensuels** (TXT) | ✅ (déc, fév, mars, avr) | ✅ (jan, fév, mars, avr) |
| Rapports Z **journaliers** (CSV/PDF) | partiels | ✅ 7 CSV vérifiés (10/20 fév, 10/20 mars, 10/20 avr, 10 mai) |
| `Transaction.mdb` (volumes/historique) | ✅ | ✅ |
| `Inventaire.mdb` (catalogue/coût) | ✅ | ✅ |
| Dashboards Metabase existants | #8/#10 | #11/#12/#13 (volumes) |

**Conséquence :** la **Phase 1 dollars-journaliers démarre sur OBRIEN** (source `Z/*.mdb` complète et vérifiée). Pour **PIE-IX au même niveau**, il faut **confirmer/récupérer les `Z/*.mdb` journaliers de PIE-IX** (sinon, dollars PIE-IX limités au mensuel + 7 jours CSV, et volumes via Transaction). **Ne pas supposer que PIE-IX a les `Z/*.mdb`** tant que non vérifié.
