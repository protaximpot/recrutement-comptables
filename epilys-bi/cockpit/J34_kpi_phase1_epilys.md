# EPILYS — Brainstorming KPI structuré + PHASE 1 exploitable (J34)

**Magasins :** OBRIEN + PIE-IX · **Auteur :** CHAT (architecte) · **Supervision :** Codex
**Statut :** document & plan. **Aucun changement Metabase/production. Aucun DROP/ALTER/UPDATE.**
**Sources :** `Z/AAAAMMJJ.mdb` table **`Day`** = DOLLARS OFFICIELS (vérifié au cent) · `Transaction.mdb` = volumes/historique · `Inventaire.mdb` = catalogue/coût.
**Badges :** `OFFICIEL_Z` · `VOLUME_FIABLE` · `ESTIME_CALIBRE` · `ECART_A_EXPLIQUER`.

---

## A. MATRICE KPI COMPLÈTE
| # | KPI | Question métier | Source | Formule | Filtres | Comparaison | Cible | Badge |
|--|--|--|--|--|--|--|--|--|
|1|CA HT|Combien on vend (hors taxes) ?|Z/Day|Σ(Qte·Prix) ventes − consigne|magasin, période, dept|J-1, J-7, sem, mois, YoY, Hijri|Sammy+Yahia|OFFICIEL_Z|
|2|TTC encaissé|Argent réellement entré ?|Z/Day|Σ(Prix\|PM,RE,RO)|magasin, période, mode|J-1, J-7, mois|Sammy+Yahia|OFFICIEL_Z|
|3|TPS / TVQ|Taxes à remettre ?|Z/Day|Σ(Prix\|T1) / Σ(Prix\|T2)|magasin, période|mois, trimestre|Yahia|OFFICIEL_Z|
|4|Profit brut|Combien on gagne ?|Z/Day|Σ((Prix−Coutant)·Qte) ventes|magasin, dept, article|J-7, mois, YoY|Yahia|OFFICIEL_Z|
|5|Marge %|Rentabilité ?|Z/Day|profit ÷ CA HT|dept, article, caissier|mois, vs moyenne|Yahia|OFFICIEL_Z|
|6|Nb factures|Achalandage ?|Z/Day|distinct NoFacture|magasin, heure, jour|J-7, sem, Hijri|Sammy|OFFICIEL_Z|
|7|Panier moyen|Valeur du ticket ?|Z/Day|CA HT ÷ nb factures|magasin, période|J-7, mois, Hijri|Sammy+Yahia|OFFICIEL_Z|
|8|Articles/panier|Taille du panier ?|Z/Day|Σ Qte ÷ nb factures|magasin, période|J-7, mois|Sammy|OFFICIEL_Z|
|9|CA par département|Quels rayons portent ?|Z/Day|group Departement|magasin, période|mois, YoY, Hijri|Sammy+Yahia|OFFICIEL_Z|
|10|CA/profit par article|Top/flop produits ?|Z/Day|group CodeUPC|dept, période|J-7, mois|Sammy(CA)/Yahia(profit)|OFFICIEL_Z|
|11|CA par caissier|Performance équipe ?|Z/Day|group Vendeur|période, magasin|J-7, mois|Yahia|OFFICIEL_Z|
|12|CA par heure|Heures de pointe ?|Z/Day + Transaction|group hour(Date)|jour, magasin|J-7, Ramadan|Sammy|OFFICIEL_Z (vol. VOLUME_FIABLE)|
|13|Modes de paiement|Argent vs carte ?|Z/Day|Σ(Prix\|PM) by Description|période, magasin|mois|Yahia|OFFICIEL_Z|
|14|Retours $ / taux|Trop de retours ?|Z/Day|Σ\|RE\| ; ÷ CA|caissier, période|J-7, vs moyenne|Yahia|OFFICIEL_Z|
|15|Escomptes|Combien de rabais ?|Z/Day|Σ\|ED\||période, caissier|mois|Yahia|OFFICIEL_Z|
|16|Consigne (net)|Dépôts bouteilles|Z/Day|dept CONSIGNE net crédits|période|mois|Yahia|OFFICIEL_Z|
|17|Top fournisseurs|Dépendance achat ?|Z/Day(Fournisseur)+Inv|Σ ventes/coût by Fournisseur|période|mois|Yahia/Akram|OFFICIEL_Z|
|18|Articles dormants|Argent immobilisé ?|Transaction+Inv|0 vente N j|dept, magasin|—|Yahia/Akram|VOLUME_FIABLE|
|19|Rotation|Vitesse d'écoulement ?|Transaction+Inv|ventes ÷ stock|dept|mois|Akram|VOLUME_FIABLE|
|20|Prix moyen/kg (poids)|Cohérence prix balances ?|Z/Day|Σ(Prix·Qte)÷Σ Qte (poids)|rayon poids|mois|Akram|OFFICIEL_Z|
|21|CA vs même jour Hijri N-1|Effet événement religieux ?|Z/Day+dim_hijri|var $/%|événement|Hijri N-1|Sammy+Yahia|OFFICIEL_Z|
|22|CA rayons traditionnels|Produits maghrébins ?|Z/Day(groupe)|group rayon traditionnel|événement, période|Ramadan/Eid|Sammy|OFFICIEL_Z|
|23|Affluence horaire Ramadan|Quand staffer ?|Transaction+Day|factures/heure (Ramadan)|jour Ramadan|J-7 Ramadan|Sammy|VOLUME_FIABLE|

## B. MODULE VENTES / FINANCE OFFICIEL (Z/Day)
Cartes : **CA HT du jour**, **TTC**, **TPS+TVQ**, **Profit & marge**, **Nb factures**, **Panier moyen**, **CA par département** (barres), **CA par heure** (courbe), **Modes de paiement** (camembert), **Retours & escomptes**, **Corrections** (VD/RE/RO — *exclues du CA*, montrées à part pour contrôle).
Formules clés (validées) : `CA_HT = Σ(Qte·Prix) ventes − consigne_net` · `TPS=Σ(Prix|T1)` · `TVQ=Σ(Prix|T2)` · `TTC=Σ(Prix|PM,RE,RO)` · `Profit=Σ((Prix−Coutant)·Qte)`. **Exclure VD. Netter consigne. Borne anti-aberration.**

## C. MODULE ACHAT / PRICING
Cartes : **Top 20 articles** (CA / profit / quantité) · **Top fournisseurs** ($ vendus, coût, marge) · **Marge par département** · **Articles à marge négative** (isoler rayons au poids) · **Couverture coût/prix** (% renseigné) · **Dormants** (0 vente ≥ 30/60/90 j) + valeur · **Rotation** · **Surstock** (dormant + stock élevé) · **Rupture probable** (rotation haute + stock bas) · **Écart prix catalogue vs appliqué**. Cible : Akram (achats) + Yahia (marge). Coûts = **réservés Yahia/admin**.

## D. MODULE SAISONNALITÉ MAGHRÉBINE (le différenciateur)
- **`dim_date_hijri`** : date grégorienne ↔ Hijri + drapeaux : `RAMADAN`, `RAMADAN_10_DERNIERS`, `VEILLE_EID`, `EID_FITR`, `EID_ADHA`, `MAWLID`, `ACHOURA`, `FERIE_QC`.
- Cartes : **CA Ramadan vs an dernier (même jour Hijri)** · **Profil intra-Ramadan** (montée → pic 10 derniers jours → veille Eid) · **Affluence horaire Ramadan** (pic avant iftar / après tarawih) · **Rayons traditionnels par événement** (dattes, feuilles de brick, frik/chorba, pâtisserie, agneau/viande, thé/café, semoule, boissons) · **Eid al-Adha = viande/agneau** · **Eid al-Fitr = pâtisserie/dattes** · **Recommandation d'achat pré-événement** (J-X).
- Comparaison spéciale : **même jour Hijri N-1** (pas seulement date grégorienne).

## E. VARIATIONS (à appliquer à CHAQUE axe)
Jour vs **hier (J-1)** · **même jour semaine préc. (J-7)** · **semaine vs semaine** · **mois (MoM)** · **année (YoY)** · **cumulatif MTD / YTD** · **même période Hijri N-1** · moyenne 4 dernières semaines. Toujours afficher **variation $ ET %** (marge en **points**).

## F. PRÉSENTATION : SAMMY (simple) vs YAHIA (développé)
- **Sammy** : CA, TTC, panier, nb factures, top rayons/produits, affluence, **événements religieux**, alertes ruptures/vedettes. *Langage simple, pas de coûts/marges fines/fiscal.*
- **Yahia/admin** : tout Sammy **+** profit/marge par article/caissier/fournisseur, **coûts**, TPS/TVQ, réconciliation Z, écarts caisse, calibration, alertes risque. *Permissions Metabase par collection ; coûts masqués pour Sammy.*

## G. BACKLOG PHASÉ
| Phase | Contenu | Effort | Risque | Dépendances |
|--|--|--|--|--|
|**1 — Finance officielle Z**|Import staging Z/Day (read-only), vues finance jour/dept/caissier/heure/paiement, sanity vs 3 Z connus, dashboard Yahia finance + Sammy simple|Moyen|Faible (read-only)|accès aux `.mdb` Z (sync Drive) + mdbtools côté exécutant|
|**2 — Achat/pricing + saisonnalité**|Marge article/fournisseur, dormants/rotation, `dim_date_hijri`, cartes Ramadan/Eid, comparaisons Hijri|Moyen-élevé|Moyen (coût/stock partiels, calendrier Hijri à valider)|Phase 1 + Inventaire + dates Hijri validées|
|**3 — Alertes + auto-refresh + calibration PIE9**|Alertes intelligentes, rafraîchissement quotidien, calibration Access→Z pour jours sans Z|Élevé|Moyen|Phases 1-2 + pipeline import auto (porte de sécurité J28)|

## H. PHASE 1 — SQL / PSEUDO-SQL (staging, read-only, sans prod)
> Schéma dédié `epilys_z_stage`. Chargement : `mdb-export AAAAMMJJ.mdb Day` → CSV → `COPY` dans `z_day_raw` (un magasin/jour par fichier). **Aucun DROP/ALTER sur les schémas existants.**

```sql
CREATE SCHEMA IF NOT EXISTS epilys_z_stage;

-- 1) Table brute (1 ligne = 1 ligne Day d'un fichier Z)
CREATE TABLE IF NOT EXISTS epilys_z_stage.z_day_raw (
    magasin       text,            -- 'OBRIEN' | 'PIE9' (dossier source)
    fichier_date  date,            -- AAAAMMJJ du nom de fichier
    id            bigint, nocaisse text, nofacture text, dt text,  -- 'Date' renommé (mot réservé)
    code text, qte numeric, codeupc text, description text, departement text,
    coutant numeric, prix numeric, vendeur text, refmev text, fournisseur text,
    groupe text, mixmatch text
    -- + autres colonnes Day au besoin (Taxe1-4, Client, NoFournisseur...)
);
-- chargement (hors SQL) : pour chaque fichier
--   mdb-export AAAAMMJJ.mdb Day | <ajouter magasin+date> | psql \copy epilys_z_stage.z_day_raw(...) FROM STDIN CSV HEADER

-- 2) Vue typée + garde-fou anti-aberration
CREATE OR REPLACE VIEW epilys_z_stage.v_z_day AS
SELECT magasin, fichier_date,
       to_timestamp(dt,'MM/DD/YY HH24:MI:SS') AS ts,        -- [VERIFIER format réel]
       code, qte, prix, coutant, departement, nofacture, vendeur, description, codeupc,
       fournisseur, groupe, (qte*prix) AS montant_ligne
FROM   epilys_z_stage.z_day_raw
WHERE  abs(coalesce(prix,0)) < 1e6 AND abs(coalesce(qte,0)) < 1e5;  -- borne anti-aberration

-- 3) Finance par jour (formules validées au cent)
CREATE OR REPLACE VIEW epilys_z_stage.v_finance_jour AS
WITH d AS (SELECT * FROM epilys_z_stage.v_z_day)
SELECT magasin, fichier_date AS date_jour,
   round(SUM(montant_ligne) FILTER (WHERE code IN ('IT','IB','DP','ED') AND departement<>'CONSIGNE'),2) AS ca_ht_brut,
   round(SUM(montant_ligne) FILTER (WHERE departement='CONSIGNE'),2)                                   AS consigne,
   round(SUM(prix)         FILTER (WHERE code='T1'),2)                                                 AS tps,
   round(SUM(prix)         FILTER (WHERE code='T2'),2)                                                 AS tvq,
   round(SUM(prix)         FILTER (WHERE code IN ('PM','RE','RO')),2)                                  AS ttc,
   round(SUM((prix-coutant)*qte) FILTER (WHERE code IN ('IT','IB','DP','ED') AND departement<>'CONSIGNE'),2) AS profit_brut,
   round(SUM(prix) FILTER (WHERE code='RE'),2)                                                         AS retours,
   round(SUM(prix) FILTER (WHERE code='ED'),2)                                                         AS escomptes,
   count(DISTINCT nofacture) FILTER (WHERE code IN ('IT','IB','DP','ED'))                              AS nb_factures
FROM d GROUP BY magasin, fichier_date;
-- CA_HT officiel = ca_ht_brut (consigne déjà exclue) ; marge% = profit_brut/ca_ht_brut ; panier = ca_ht_brut/nb_factures

-- 4) Déclinaisons
CREATE OR REPLACE VIEW epilys_z_stage.v_finance_dept     AS SELECT magasin,fichier_date,departement,
   round(SUM(montant_ligne),2) ca, round(SUM((prix-coutant)*qte),2) profit
   FROM epilys_z_stage.v_z_day WHERE code IN ('IT','IB','DP','ED') GROUP BY 1,2,3;
CREATE OR REPLACE VIEW epilys_z_stage.v_finance_caissier AS SELECT magasin,fichier_date,vendeur,
   round(SUM(montant_ligne),2) ca, count(DISTINCT nofacture) nb_fact
   FROM epilys_z_stage.v_z_day WHERE code IN ('IT','IB','DP','ED') GROUP BY 1,2,3;
CREATE OR REPLACE VIEW epilys_z_stage.v_finance_heure    AS SELECT magasin,fichier_date,extract(hour FROM ts) h,
   round(SUM(montant_ligne),2) ca, count(DISTINCT nofacture) nb_fact
   FROM epilys_z_stage.v_z_day WHERE code IN ('IT','IB','DP','ED') GROUP BY 1,2,3;
CREATE OR REPLACE VIEW epilys_z_stage.v_paiement         AS SELECT magasin,fichier_date,description mode,
   round(SUM(prix),2) montant FROM epilys_z_stage.v_z_day WHERE code='PM' GROUP BY 1,2,3;

-- 5) SANITY CHECK (doit reproduire le rapport Z officiel)
-- attendu : 2026-02-01 tps 707.90 / tvq 1415.61 / ttc 185276.86 / ca_ht ~182816 (résidu consigne à netter)
SELECT * FROM epilys_z_stage.v_finance_jour WHERE date_jour IN ('2026-01-01','2026-02-01','2026-05-06');

-- ROLLBACK : DROP SCHEMA IF EXISTS epilys_z_stage CASCADE;  (schéma dédié, sans source)
```

## I. ALERTES INTELLIGENTES
🔴 **Rupture probable** (rotation haute + stock bas) · 🟠 **Surstock/dormant** (0 vente N j + stock élevé) · 🟠 **Baisse de marge** (dept < seuil/moyenne) · 🟠 **Hausse retours** (taux > seuil) · ⭐ **Produit vedette** (croissance > X % vs J-7/4 sem) · 🟣 **Pré-événement** (Ramadan/Eid dans X j → liste d'achats traditionnels) · ⚠️ **Écart caisse** (paiements ≠ TTC) · ⚠️ **Prix/marge aberrant** (marge négative hors poids) · ⚠️ **Donnée aberrante** (hors borne).

## J. LIMITES & GARDE-FOUS
- **Dollars = Z/Day uniquement** ; `Transaction.mdb` = volumes (prix=0) → jamais de $ sans calibration badgée.
- **Exclure `VD`** du CA (récap interne, sinon +~98 k$). **Netter la consigne** (crédits/retours, résidu ~16 $/j). **Borne anti-aberration** (Z mensuel 20-fév = 59,7 G$).
- **Marge** fiable seulement si `Coutant` renseigné ; **rayons au poids** = marges aberrantes (artefact) → isoler.
- **Calendrier Hijri** à valider (observation lunaire ±1 j).
- **OBRIEN avril** : source Access tronquée → exclure des comparaisons.
- **Historique $** limité aux fichiers `Z/*.mdb` (~mai 2025→) → YoY en $ limité au démarrage ; volumes Transaction remontent à 2020.
- **Aucune mise en production / Metabase sans validation Yahia.**
