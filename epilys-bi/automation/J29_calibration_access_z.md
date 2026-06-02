# J29 — Calibration Access ↔ Z (PIE-IX) : du volume au dollar estimé fiable

**Auteur :** CHAT (architecte/QA) · **Exécutant :** CODE/CODEX · **Statut :** spec + seuils à valider par Yahia.
**Répond à #7844 :** on ne peut pas exiger un Z chaque jour. Le Z **étalonne** ; Access fournit le **quotidien**. Un dollar Access n'est montré que s'il est **calibré et prouvé**.

---

## 1. Principe
- **Z/GL = officiel** quand disponible (fiscal/comptable).
- **Access = quotidien** pour volumes/tendances (nb factures, nb items, achalandage).
- **Dollar Access = `ESTIME_ACCESS_CALIBRE`** seulement si la calibration sur les Z témoins est dans une bande d'erreur acceptable.
- **TPS/TVQ : jamais estimé.** Taxes = Z/GL uniquement.

## 2. Pourquoi un estimateur **par volume** (et pas par prix Access)
Le prix transactionnel Access est inutilisable (10-fév : 4959/5934 lignes VE à prix 0). On **n'estime donc pas** le CA en sommant des prix Access. On estime par **volume × panier de référence** appris sur les Z :

```
CA_estimé(jour) = nb_factures_access(jour) × panier_ref
panier_ref      = médiane sur les Z témoins de (CA_HT_Z / nb_factures_Z)
```
(Variante équivalente possible : nb_items × prix_moyen_item_ref. La médiane est choisie pour résister aux jours anormaux comme le 20-mars.)

## 3. Ce que disent TES 7 Z (calcul réel du panier de référence)
| Jour PIE-IX | CA HT Z | Factures | Panier (CA/fact) |
|---|---|---|---|
| 10-fév | 41 527,71 | 615 | 67,52 |
| 20-fév | 77 606,74 | 1 146 | 67,72 |
| 10-mars | 146 462,13 | 2 606 | 56,20 |
| 20-mars | 81 760,37 | 1 521 | 53,75 |
| 10-avr | 146 047,35 | 2 366 | 61,73 |
| 20-avr | 78 694,05 | 1 669 | 47,15 |
| 10-mai | 166 138,82 | 2 907 | 57,15 |

- **panier_ref (médiane) = 57,15 $** · moyenne ≈ 58,75 $.
- **Écart moyen ≈ 10 %**, **écart max ≈ 18,5 %** (le 20-avr à 47 $ et les jours de fév à ~68 $).

➡️ **Lecture honnête :** un panier unique donne une estimation **« moyenne »**, bonne pour la **tendance**, pas pour un dollar exact. La précision montera quand (a) on calibrera **par jour de semaine** et **par rayon**, et (b) on aura **plus de Z**.

## 4. Vue de calibration proposée (SQL)
Entrées : `epilys_ops` côté Z (tes 7 Z importés) + agrégat Access quotidien (fourni par CODE). `[VERIFIER]` = source Access réelle.

```sql
-- a) Statistiques de calibration par magasin (et par rayon en phase 2)
CREATE OR REPLACE VIEW epilys_ops.v_calibration AS
WITH temoins AS (   -- jours où Z ET Access existent
  SELECT z.magasin, z.date_jour,
         z.ca_ht_z,
         a.nb_factures_access,
         z.ca_ht_z / NULLIF(a.nb_factures_access,0) AS panier_jour
  FROM   epilys_ops.z_officiel       z          -- [VERIFIER] table des Z importés
  JOIN   epilys_ops.access_jour      a          -- [VERIFIER] agrégat Access quotidien
         USING (magasin, date_jour)
)
SELECT magasin,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY panier_jour) AS panier_ref,
       count(*)                                                 AS nb_z_calibration,
       round(avg(abs(ca_ht_z - panier_ref_calc)/NULLIF(ca_ht_z,0))*100,1) AS ecart_moyen_pct,
       round(max(abs(ca_ht_z - panier_ref_calc)/NULLIF(ca_ht_z,0))*100,1) AS ecart_max_pct
FROM ( SELECT *, (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY panier_jour)
                  FROM temoins t2 WHERE t2.magasin=t1.magasin) AS panier_ref_calc
       FROM temoins t1 ) s
GROUP BY magasin;

-- b) Estimation quotidienne + statut + confiance
CREATE OR REPLACE VIEW epilys_ops.v_estimation_jour AS
SELECT a.magasin, a.date_jour,
       z.ca_ht_z                                           AS ca_officiel_z,
       round(a.nb_factures_access * c.panier_ref, 2)       AS ca_estime_calibre,
       a.nb_factures_access, a.nb_items_access,
       c.nb_z_calibration, c.ecart_moyen_pct, c.ecart_max_pct,
       CASE
         WHEN z.ca_ht_z IS NOT NULL                                   THEN 'OFFICIEL_Z'
         WHEN z.ca_ht_z IS NOT NULL AND
              abs(a.nb_factures_access*c.panier_ref - z.ca_ht_z)
              /NULLIF(z.ca_ht_z,0) > 0.20                             THEN 'ECART_A_VERIFIER'
         WHEN c.nb_z_calibration >= 5 AND c.ecart_moyen_pct <= 10
              AND c.ecart_max_pct <= 20                               THEN 'ESTIME_ACCESS_CALIBRE'
         ELSE 'VOLUME_SEULEMENT'
       END                                                            AS statut,
       CASE
         WHEN c.nb_z_calibration >= 5 AND c.ecart_moyen_pct <= 7  AND c.ecart_max_pct <= 15 THEN 'ELEVEE'
         WHEN c.nb_z_calibration >= 3 AND c.ecart_moyen_pct <= 12                            THEN 'MOYENNE'
         ELSE 'FAIBLE'
       END                                                            AS confiance
FROM   epilys_ops.access_jour a                          -- [VERIFIER]
LEFT JOIN epilys_ops.z_officiel z USING (magasin, date_jour)
LEFT JOIN epilys_ops.v_calibration c USING (magasin);
```

## 5. Statuts (les 4 demandés)
- `OFFICIEL_Z` — un Z existe → on montre le Z (officiel).
- `ESTIME_ACCESS_CALIBRE` — pas de Z, mais calibration prouvée (seuils OK) → $ estimé **avec badge + confiance + nb_z**.
- `VOLUME_SEULEMENT` — pas de Z et calibration insuffisante → **volumes seulement**, badge « $ à confirmer ».
- `ECART_A_VERIFIER` — un Z témoin où l'estimateur diverge fortement (> 20 %) → drapeau, baisse la confiance.

## 6. Seuils PROPOSÉS (à valider par Yahia)
| Paramètre | Valeur proposée | Effet |
|---|---|---|
| nb_z minimum pour estimer un $ | **5** | en-dessous → VOLUME_SEULEMENT |
| écart moyen max pour estimer | **≤ 10 %** | au-delà → VOLUME_SEULEMENT |
| écart max toléré | **≤ 20 %** | au-delà → ECART_A_VERIFIER |
| confiance ÉLEVÉE | nb_z ≥ 5, moyen ≤ 7 %, max ≤ 15 % | badge vert |
| TPS/TVQ estimé | **JAMAIS** | Z/GL uniquement |

➡️ **Avec tes 7 Z actuels (panier médian 57,15 ; écart moyen ~10 %, max ~18,5 %)** : PIE-IX serait juste à la limite → statut **`ESTIME_ACCESS_CALIBRE` confiance MOYENNE**. Honnête : utilisable en tendance, badge visible, **pas** pour le fiscal.

## 7. Limites à afficher (transparence Sammy)
- Calibration basée sur **7 Z** seulement (échantillon faible) → confiance MOYENNE.
- Estimateur **jour-niveau** d'abord ; **par rayon** en phase 2 (nécessite de corriger la jointure article→rayon, cf. trous $0 du 10-fév sur VIANDE/PÂTISSERIE).
- Chaque nouveauZ **améliore** la calibration et peut faire monter la confiance.
