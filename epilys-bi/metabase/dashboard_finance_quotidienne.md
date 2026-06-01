# Metabase — `EPILYS — Finance quotidienne BEST POS`

**Spec de dashboard préparée par CHAT — à construire par CODE sur le VPS (`:3003`).**

## Décision : créer un **#15**, ne pas surcharger #14

- `#13` = opérationnel (Access) — **ne pas toucher**.
- `#14` = finance « 3 Z » actuel — **on le garde tel quel** comme contrôle.
- `#15` = **nouveau**, branché sur la vue `epilys_bi.v_finance_journee_calculee`, avec **statut de fiabilité** + filtres. C'est plus propre que de réécrire #14 (rollback indépendant, pas de régression sur l'existant).
- Collection : `EPILYS OBRIEN` (id 8, comme #14).

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

## Rapprochement attendu (sanity check après création)

| Date | CA HT Z | TPS | TVQ | TTC Z | TTC GL | Écart |
|---|---|---|---|---|---|---|
| 2026-01-01 | 180 193,55 | 694,59 | 1 389,29 | 182 534,71 | 182 536,54 | +1,83 |
| 2026-02-01 | 182 816,25 | 707,90 | 1 415,61 | 185 276,86 | 185 278,38 | +1,52 |
| 2026-05-06 | 16 057,00 | 45,69 | 91,50 | 16 213,69 | (pas de GL) | — |

Si une carte ne sort pas ces chiffres → la vue est mal mappée (revoir l'étape 0).
