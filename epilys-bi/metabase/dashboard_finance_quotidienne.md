# Metabase — `EPILYS — Finance quotidienne BEST POS`

**Spec de dashboard préparée par CHAT — à construire par CODE sur le VPS (`:3003`).**

## Décision (clarifiée avec Yahia 2026-06-01)

- **Faits confirmés (Codex+Yahia, 2026-06-01)** : Metabase `:3003` accessible ; `#14` existe (id=14, « EPILYS — Finance BEST POS », non archivé) ; `#13` existe ; **aucun `#15`** encore.
- `#13` = opérationnel Power-BI (façade `epilys_bi.mv_fact_tx`) — **NE PAS TOUCHER / ne pas régresser**.
- `#14` = **zone FINANCE OFFICIELLE confirmée par Z** (déjà créée). On la garde comme référence « dollars certifiés ». **Ne pas l'écraser sans validation Yahia** ; au plus un bandeau « OFFICIEL — confirmé Z ».
- `#15` = **nouveau cockpit interactif à créer**, branché sur `epilys_bi.v_finance_journee_calculee` **+** `epilys_bi.v_finance_variation` : statut de fiabilité, filtres Power-BI, **couche VARIATION/COMPARAISON** (période courante vs précédente, Z↔Z, variation CA $, profit $, marge %, panier, taxes, paiements) **+ carte-analyse dynamique sous chaque carte principale**.
- Collection : `EPILYS OBRIEN` (id 8, comme #14).
- ⚠️ `epilys_bi` **préexiste** (contient `mv_fact_tx`) → `CREATE SCHEMA IF NOT EXISTS` est inoffensif, mais **ne jamais** `DROP SCHEMA … CASCADE`.

## Garde-fous (obligatoires)

1. Exécuter **`00_audit_vente_article.sql` d'abord** — ne pas créer la carte couverture tant que la source n'est pas tranchée.
2. Créer la vue (`10_v_finance_journee_calculee.sql`) après confirmation du schéma (étape 0).
3. **Tester les 12 requêtes** ci-dessous (toutes lisent la vue) avant de créer les cartes.
4. **Snapshot Metabase** + générer `/tmp/j19_finance_rollback.sql` avant insertion.
5. **Pas de promotion prod sans validation Yahia.**
6. Mettre l'explication "pour Sammy" sous chaque carte importante.

## Filtres du dashboard (variables de champ Metabase)

| Filtre | Variable | Colonne vue | Cartes mappées |
|---|---|---|---|
| Période / date | `{{periode}}` | `date_jour` | toutes sauf explicatives |
| Magasin | `{{magasin}}` | `magasin` | toutes sauf explicatives |
| Statut fiabilité | `{{statut}}` | `statut_fiabilite` | détail, comptages, CA estimé |
| Source validation | `{{source}}` | `source_validation` | détail, comptages |
| Département | `{{departement}}` | (table `obrien_z_departement`) | carte départements uniquement |

> Pattern SQL filtre Metabase : `WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]] ...`

---

## Cartes (12) — SQL sur la vue

### 1. CA officiel Z par jour — *line*
```sql
SELECT date_jour, ca_z_officiel
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite = 'CONFIRME_BEST' [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : CA hors taxes confirmé par le rapport Z. Source officielle des ventes.*

### 2. Total TTC encaissé (Z) — *scalar*
```sql
SELECT SUM(total_ttc_z)
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite='CONFIRME_BEST' [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]];
```
*Sammy : argent total encaissé taxes comprises, jours confirmés Z.*

### 3. Taxes TPS + TVQ (Z) — *scalar*
```sql
SELECT SUM(tps_z) AS tps, SUM(tvq_z) AS tvq, SUM(tps_z+tvq_z) AS taxes_totales
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite='CONFIRME_BEST' [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]];
```
*Sammy : taxes officielles extraites du Z. Jamais estimées — uniquement jours confirmés.*

### 4. Profit & marge brute (Z) — *bar*
```sql
SELECT date_jour, profit_z, marge_z_pct
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite='CONFIRME_BEST' [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : profit par département selon BEST. Indicateur de pilotage (pas la marge comptable finale).*

### 5. Panier moyen — *line*
```sql
SELECT date_jour, panier_moyen_z, nb_factures_z
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite='CONFIRME_BEST' [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : CA HT ÷ nombre de factures. Ex. 01-01 = 53,66 $.*

### 6. CA estimé / base par jour (badge fiabilité) — *table*
```sql
SELECT date_jour, ca_calcule_access AS ca_estime, statut_fiabilite, note_limite
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite IN ('ESTIME_BASE','ECART_A_VERIFIER')
  [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]] [[ AND statut_fiabilite = {{statut}} ]]
ORDER BY date_jour;
```
*Sammy : ⚠️ estimations depuis la base Access — **non officielles, jamais pour le fiscal**.*

### 7. Écart Access vs Z (jours contrôlés) — *bar*
```sql
SELECT date_jour, ca_z_officiel, ca_calcule_access, ecart_ca, ecart_ca_pct, flag_calibration
FROM epilys_bi.v_finance_journee_calculee
WHERE ca_calcule_access IS NOT NULL AND ca_z_officiel IS NOT NULL
  [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : mesure l'écart entre le calcul Access et le Z officiel. Sert à juger si l'estimation est fiable.*

### 8. Modes de paiement — *bar*  *(lit la table source paiement)*
```sql
SELECT mode_paiement, SUM(montant) AS montant
FROM epilys.obrien_z_paiement
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
GROUP BY mode_paiement ORDER BY montant DESC;
```
*Sammy : répartition argent / débit / crédit selon le Z.*

### 9. Top départements CA / profit — *table*  *(table source département + filtre {{departement}})*
```sql
SELECT departement, SUM(ca) AS ca, SUM(profit) AS profit
FROM epilys.obrien_z_departement
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]] [[ AND departement = {{departement}} ]]
GROUP BY departement ORDER BY ca DESC;
```
*Sammy : départements qui font le CA et le profit (Z).*

### 10. Jours confirmés vs estimés vs non mesurables — *bar/pie*
```sql
SELECT statut_fiabilite, COUNT(*) AS nb_jours, SUM(COALESCE(ca_z_officiel, ca_calcule_access)) AS ca
FROM epilys_bi.v_finance_journee_calculee
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]] [[ AND source_validation = {{source}} ]]
GROUP BY statut_fiabilite;
```
*Sammy : combien de journées sont fiables (Z) vs estimées vs sans donnée.*

### 11. Détail quotidien complet — *table*
```sql
SELECT date_jour, magasin, ca_z_officiel, total_ttc_z, tps_z, tvq_z, profit_z, marge_z_pct,
       panier_moyen_z, ca_calcule_access, ecart_ca_pct, total_ttc_gl, ecart_gl_z,
       source_validation, statut_fiabilite, flag_calibration, note_limite
FROM epilys_bi.v_finance_journee_calculee
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
     [[ AND statut_fiabilite = {{statut}} ]] [[ AND source_validation = {{source}} ]]
ORDER BY date_jour DESC;
```

### 12. Statuts + limites connues — *text/table (NON filtrée)*
> **Légende fiabilité**
> - `CONFIRME_BEST` — dollars officiels (rapport Z). Fiable, fiscal OK.
> - `ESTIME_BASE` — estimation Access. **Non officiel, pas pour le fiscal.**
> - `ECART_A_VERIFIER` — estimation douteuse, à investiguer.
> - `NON_MESURABLE` — pas assez de données.
>
> **Limites connues**
> - Z disponibles : 2026-01-01, 2026-02-01, 2026-05-06 ; GL : 01-01, 02-01.
> - Access ≠ Z (~10 % d'écart quantité sur jours témoins) → estimations à calibrer.
> - `obrien_vente_article` : **source à auditer** (cf. couverture 65,5 % non confirmée).
> - Rapprochement Z↔GL : écart de 1–2 $ = arrondissement caisse (normal).

---

## Couche VARIATION / COMPARAISON (cartes 13-18) — le « pas une photo figée »

> Source : `epilys_bi.v_finance_variation` (lit uniquement les journées Z → **100 % officiel, aucun estimé**).
> Filtres `{{periode}}` / `{{magasin}}` applicables.

### 13. Variation vs journée Z précédente — *table (KPI deltas)*
```sql
SELECT date_jour, ca_z_officiel,
       var_ca_dollars, var_ca_pct,
       var_profit_dollars, var_profit_pct,
       var_marge_points,
       var_panier_dollars, var_panier_pct,
       var_taxes_dollars, var_taxes_pct,
       tendance_ca
FROM epilys_bi.v_finance_variation
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour DESC;
```
*Sammy : écart en **dollars ET en %** d'une journée Z à la précédente. Vert = hausse, rouge = baisse. Tout est confirmé Z.*

### 14. Comparer 2 rapports Z (période A vs période B) — *scalaires côte à côte*
```sql
-- Carte A : SUM(...) WHERE {{periode_a}}   |   Carte B : SUM(...) WHERE {{periode_b}}
SELECT SUM(ca_z_officiel) AS ca, SUM(profit_z) AS profit,
       SUM(tps_z+tvq_z) AS taxes, SUM(total_ttc_z) AS ttc
FROM epilys_bi.v_finance_journee_calculee
WHERE statut_fiabilite='CONFIRME_BEST' [[ AND {{periode_a}} ]] [[ AND magasin = {{magasin}} ]];
```
*Sammy : choisis 2 périodes (ex. 01-01 vs 02-01). L'écart $ et % se lit entre les 2 cartes. Comparaison entre journées Z disponibles.*

### 15. Variation CA $ dans le temps — *waterfall / bar signé*
```sql
SELECT date_jour, var_ca_dollars
FROM epilys_bi.v_finance_variation
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : combien de dollars de CA gagnés/perdus par rapport à la journée Z d'avant.*

### 16. Variation profit $ & marge (points) — *bar*
```sql
SELECT date_jour, var_profit_dollars, var_marge_points
FROM epilys_bi.v_finance_variation
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : variation du profit en $ et de la marge en **points de %** (ex. 47,1 % → 48,9 % = +1,8 pt).*

### 17. Variation panier moyen & taxes — *line double axe*
```sql
SELECT date_jour, var_panier_dollars, var_panier_pct, var_taxes_dollars, var_taxes_pct
FROM epilys_bi.v_finance_variation
WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
ORDER BY date_jour;
```
*Sammy : le panier moyen monte-t-il ? les taxes collectées suivent-elles le CA ?*

### 18. Variation des modes de paiement (période A vs B) — *bar groupé* *(table source paiement)*
```sql
-- 2 requêtes (A et B) groupées par mode, puis comparaison visuelle.
SELECT mode_paiement, SUM(montant) AS montant
FROM epilys.obrien_z_paiement
WHERE 1=1 [[ AND {{periode_a}} ]] [[ AND magasin = {{magasin}} ]]
GROUP BY mode_paiement ORDER BY montant DESC;
```
*Sammy : l'argent comptant baisse-t-il au profit du débit/crédit d'une période à l'autre ? Données Z officielles.*

> **Note variation** : toutes ces cartes ne comparent que des **journées Z confirmées**. Tant qu'il n'y a que 3 Z (01-01, 02-01, 05-06), la profondeur de comparaison est limitée — la couche s'enrichit automatiquement à chaque nouveau Z importé.

---

## Cartes d'ANALYSE DYNAMIQUE (exigence Yahia) — une sous CHAQUE carte principale

**But :** Sammy ne voit pas que des chiffres — sous chaque carte clé, une carte-analyse explique **en français simple** : variation vs période précédente ($/% ou points de marge), lecture métier (hausse/baisse/stable), cause probable si dispo, **limite de fiabilité**, **action recommandée**.

> ⚠️ Un bloc *texte* Metabase est **statique**. Pour que l'analyse change avec le filtre de période, chaque carte-analyse est une **question SQL** qui retourne **une seule colonne phrase**, branchée sur les **mêmes filtres** `{{periode}}`/`{{magasin}}` que la carte du dessus. Placement : juste sous la carte mère.

### Patron générique (à dupliquer par métrique)
```sql
WITH cur AS (
  SELECT *
  FROM epilys_bi.v_finance_variation
  WHERE 1=1 [[ AND {{periode}} ]] [[ AND magasin = {{magasin}} ]]
  ORDER BY date_jour DESC
  LIMIT 1
)
SELECT
  '📅 Journée ' || to_char(date_jour,'YYYY-MM-DD') || E'\n'
  || '💵 CA officiel : ' || to_char(ca_z_officiel,'FM999G999G990D00') || ' $ (confirmé Z).' || E'\n'
  || CASE
       WHEN var_ca_dollars IS NULL
         THEN '↔ Première journée Z de la sélection — pas de comparaison possible.'
       ELSE '📊 Variation vs Z précédent (' || to_char(date_z_precedent,'YYYY-MM-DD') || ') : '
            || CASE WHEN var_ca_dollars >= 0 THEN '+' ELSE '' END || to_char(var_ca_dollars,'FM999G990D00') || ' $ ('
            || CASE WHEN var_ca_pct      >= 0 THEN '+' ELSE '' END || to_char(var_ca_pct,'FM990D0') || ' %). '
            || CASE tendance_ca WHEN 'HAUSSE' THEN '↑ Hausse.' WHEN 'BAISSE' THEN '↓ Baisse.' ELSE '→ Stable.' END
     END || E'\n'
  || '✅ Fiabilité : dollars officiels (rapport Z), fiscal OK.' || E'\n'
  || '🎯 Action : ' || CASE
       WHEN var_ca_pct IS NULL      THEN 'attendre un 2e Z pour juger la tendance.'
       WHEN var_ca_pct < -10        THEN 'baisse marquée — vérifier achalandage / jour de semaine / fermeture partielle.'
       WHEN var_ca_pct >  10        THEN 'hausse marquée — confirmer la cause (promo, affluence) et la pérenniser.'
       ELSE 'évolution normale — surveiller la tendance sur les prochains Z.'
     END AS analyse
FROM cur;
```

### Adaptation par métrique (mêmes 5 blocs : valeur · variation · lecture · fiabilité · action)
| Métrique (carte mère) | Colonne valeur | Colonnes variation (`v_finance_variation`) | Spécificité d'action |
|---|---|---|---|
| **CA** | `ca_z_officiel` | `var_ca_dollars`, `var_ca_pct` | cf. patron |
| **Total TTC** | `total_ttc_z` | (recalcul vs TTC précédent) | doit bouger comme le CA + taxes |
| **TPS/TVQ** | `tps_z`,`tvq_z`,`taxes_z` | `var_taxes_dollars`, `var_taxes_pct` | taxes doivent suivre le CA ; écart anormal = vérifier exonérés |
| **Profit** | `profit_z` | `var_profit_dollars`, `var_profit_pct` | profit qui baisse + CA stable = coûts/démarque |
| **Marge** | `marge_z_pct` | `var_marge_points` | exprimer en **points** (ex. +1,8 pt) ; chute = revoir prix/pertes |
| **Panier moyen** | `panier_moyen_z` | `var_panier_dollars`, `var_panier_pct` | panier ↓ + factures ↑ = plus de petits paniers |
| **Factures (nb)** | `nb_factures_z` | (vs nb précédent) | proxy achalandage |
| **Paiements** | (table `obrien_z_paiement`) | comparer modes A vs B | comptant ↓ vs débit/crédit ↑ = tendance dématérialisation |
| **Départements** | (table `obrien_z_departement`) | top hausses/baisses CA par dept | pointer le dept qui tire/plombe |
| **Écart Z vs GL** | `ecart_gl_z` | — | 1–2 $ = arrondissement (normal) ; au-delà = à investiguer |
| **Couverture vente article** | (après audit étape 0) | — | n'afficher que si source tranchée ; sinon « en validation » |
| **Statut fiabilité** | `statut_fiabilite` | — | rappelle CONFIRME_BEST vs ESTIME_BASE et l'usage permis |

> **Règle fiabilité dans l'analyse** : si la métrique vient d'un jour `ESTIME_BASE`, la phrase **doit** commencer par « ⚠️ Estimation Access — non officiel, pas pour le fiscal » et l'action devient « confirmer avec un rapport Z ». Jamais d'analyse « officielle » sur de l'estimé.

---

## Rapprochement attendu (sanity check après création)

| Date | CA HT Z | TPS | TVQ | TTC Z | TTC GL | Écart |
|---|---|---|---|---|---|---|
| 2026-01-01 | 180 193,55 | 694,59 | 1 389,29 | 182 534,71 | 182 536,54 | +1,83 |
| 2026-02-01 | 182 816,25 | 707,90 | 1 415,61 | 185 276,86 | 185 278,38 | +1,52 |
| 2026-05-06 | 16 057,00 | 45,69 | 91,50 | 16 213,69 | (pas de GL) | — |

Si une carte ne sort pas ces chiffres → la vue est mal mappée (revoir l'étape 0).
