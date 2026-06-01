-- =====================================================================
-- EPILYS BI — COUCHE VARIATION / COMPARAISON (cockpit #15)
-- Vue : epilys_bi.v_finance_variation
-- =====================================================================
-- Auteur : CHAT (analyse)  /  A executer par : CODE (VPS PostgreSQL)
-- Depend de : epilys_bi.v_finance_journee_calculee (script 10_).
--
-- OBJECTIF (demande Yahia) : ne pas lire une "photo figee". Ajouter la
-- VARIATION entre journees, en DOLLARS et en %, pour : CA, profit, marge,
-- panier moyen, taxes. La comparaison se fait entre 2 journees Z OFFICIELLES
-- consecutives (meme magasin) => 100 % confirme BEST, JAMAIS d'estime Access.
--
-- Les "paiements" varient par MODE (argent/debit/credit) : ils ne sont pas
-- dans la vue jour ; la variation paiements se fait cote Metabase avec 2
-- filtres de periode sur epilys.obrien_z_paiement (voir spec dashboard,
-- carte 18). Idem comparaison entre 2 rapports Z choisis (carte 14).
--
-- ADDITIF & REVERSIBLE. Aucune table source touchee.
-- =====================================================================

CREATE OR REPLACE VIEW epilys_bi.v_finance_variation AS
WITH base AS (
    -- variations OFFICIELLES uniquement : on ne compare que des journees Z.
    SELECT
        date_jour, magasin,
        ca_z_officiel, profit_z, marge_z_pct, panier_moyen_z,
        tps_z, tvq_z, (tps_z + tvq_z) AS taxes_z,
        total_ttc_z, nb_factures_z
    FROM epilys_bi.v_finance_journee_calculee
    WHERE statut_fiabilite = 'CONFIRME_BEST'
)
SELECT
    date_jour,
    magasin,

    -- valeurs du jour (officielles Z) ---------------------------------
    ca_z_officiel,
    profit_z,
    marge_z_pct,
    panier_moyen_z,
    taxes_z,
    total_ttc_z,
    nb_factures_z,

    -- reference : journee Z PRECEDENTE du meme magasin ----------------
    LAG(date_jour)      OVER w AS date_z_precedent,
    LAG(ca_z_officiel)  OVER w AS ca_z_precedent,
    LAG(profit_z)       OVER w AS profit_z_precedent,
    LAG(marge_z_pct)    OVER w AS marge_z_pct_precedent,
    LAG(panier_moyen_z) OVER w AS panier_precedent,
    LAG(taxes_z)        OVER w AS taxes_z_precedent,

    -- VARIATIONS EN DOLLARS -------------------------------------------
    ROUND(ca_z_officiel  - LAG(ca_z_officiel)  OVER w, 2) AS var_ca_dollars,
    ROUND(profit_z       - LAG(profit_z)       OVER w, 2) AS var_profit_dollars,
    ROUND(panier_moyen_z - LAG(panier_moyen_z) OVER w, 2) AS var_panier_dollars,
    ROUND(taxes_z        - LAG(taxes_z)        OVER w, 2) AS var_taxes_dollars,

    -- VARIATIONS EN % (et marge en POINTS de %) -----------------------
    ROUND(100.0*(ca_z_officiel  - LAG(ca_z_officiel)  OVER w)
                / NULLIF(LAG(ca_z_officiel)  OVER w,0), 1)  AS var_ca_pct,
    ROUND(100.0*(profit_z       - LAG(profit_z)       OVER w)
                / NULLIF(LAG(profit_z)       OVER w,0), 1)  AS var_profit_pct,
    ROUND(marge_z_pct           - LAG(marge_z_pct)    OVER w, 1)
                                                            AS var_marge_points, -- ecart en points de %
    ROUND(100.0*(panier_moyen_z - LAG(panier_moyen_z) OVER w)
                / NULLIF(LAG(panier_moyen_z) OVER w,0), 1)  AS var_panier_pct,
    ROUND(100.0*(taxes_z        - LAG(taxes_z)        OVER w)
                / NULLIF(LAG(taxes_z)        OVER w,0), 1)  AS var_taxes_pct,

    -- tendance lisible -------------------------------------------------
    CASE
        WHEN LAG(ca_z_officiel) OVER w IS NULL        THEN 'PREMIER_Z'
        WHEN ca_z_officiel > LAG(ca_z_officiel) OVER w THEN 'HAUSSE'
        WHEN ca_z_officiel < LAG(ca_z_officiel) OVER w THEN 'BAISSE'
        ELSE 'STABLE'
    END                                                     AS tendance_ca,

    'Variation entre 2 journees Z officielles consecutives (dollars confirmes BEST). Aucun estime Access.'
                                                            AS note_variation
FROM   base
WINDOW w AS (PARTITION BY magasin ORDER BY date_jour)
ORDER  BY magasin, date_jour;

-- =====================================================================
-- NOTE COMPARAISON LIBRE (periode A vs periode B) :
--   Ne PAS materialiser ici. Se fait cote Metabase avec deux filtres de
--   date {{periode_a}} / {{periode_b}} sur la vue jour, par difference des
--   agregats. Voir spec dashboard #15, cartes 13-14-18.
-- =====================================================================
