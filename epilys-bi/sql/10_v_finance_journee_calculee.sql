-- =====================================================================
-- EPILYS BI — COUCHE FINANCE QUOTIDIENNE
-- Vue : epilys_bi.v_finance_journee_calculee
-- =====================================================================
-- Auteur : CHAT (analyse)  /  A executer par : CODE (VPS PostgreSQL)
--
-- PRINCIPE (non negociable) :
--   * Les DOLLARS OFFICIELS viennent UNIQUEMENT du Z financier.
--   * Le GL sert au rapprochement (l'ecart = arrondissement caisse).
--   * La base Access ne donne JAMAIS un CA officiel : au mieux une ESTIMATION,
--     marquee comme telle. (Sur les 3 jours temoins Access != Z d'environ 10 %.)
--   * Jamais d'estime pour TPS/TVQ : taxes = Z uniquement.
--
-- ADDITIF & REVERSIBLE : cree un schema dedie epilys_bi + une vue.
--   Ne touche AUCUNE table source. Aucun DROP/TRUNCATE/UPDATE.
--
-- !!! ETAPE 0 OBLIGATOIRE AVANT EXECUTION !!!
--   Les noms de COLONNES ci-dessous sont des HYPOTHESES deduites des PDF Z.
--   CODE doit d'abord confirmer le schema reel :
--     SELECT table_name, column_name, data_type
--     FROM information_schema.columns
--     WHERE table_schema='epilys'
--       AND table_name IN ('obrien_z_journalier','obrien_z_departement',
--                          'obrien_z_paiement','obrien_gl_journalier',
--                          'obrien_vente_article')
--     ORDER BY table_name, ordinal_position;
--   ... puis ajuster les alias de colonnes marques  -- [VERIFIER]
--
--   La table Access migree (mouvements transactionnels) n'est PAS connue de CHAT.
--   Remplacer  epilys.obrien_transaction  par la vraie table.  -- [VERIFIER NOM]
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS epilys_bi;

CREATE OR REPLACE VIEW epilys_bi.v_finance_journee_calculee AS
WITH
-- 1) Z FINANCIER = source dollar officielle ---------------------------
z AS (
    SELECT
        date_jour                                   AS date_jour,
        COALESCE(magasin, 'OBRIEN')                 AS magasin,        -- [VERIFIER]
        ca_ht                                       AS ca_z_officiel,  -- [VERIFIER] "VENTES AVANT TAXES"
        tps                                         AS tps_z,          -- [VERIFIER]
        tvq                                         AS tvq_z,          -- [VERIFIER]
        total_ttc                                   AS total_ttc_z,    -- [VERIFIER] ligne "TOTAL"
        profit                                      AS profit_z,       -- [VERIFIER] profit dept total
        nb_factures                                 AS nb_factures_z,  -- [VERIFIER]
        ROUND(ca_ht / NULLIF(nb_factures, 0), 2)    AS panier_moyen_z  -- verifie : 180193.55/3358 = 53.66
    FROM epilys.obrien_z_journalier
),
-- 2) GRAND LIVRE = rapprochement (total credits = total TTC GL) --------
--    Hypothese : table ligne-a-ligne (gl_numero, debit, credit).
--    Total TTC GL = SUM(credit). L'ecart Z vs GL = arrondissement caisse.
gl AS (
    SELECT
        date_jour                  AS date_jour,
        COALESCE(magasin,'OBRIEN') AS magasin,                 -- [VERIFIER]
        ROUND(SUM(credit), 2)      AS total_ttc_gl             -- [VERIFIER] sinon colonne total deja agregee
    FROM epilys.obrien_gl_journalier
    GROUP BY date_jour, COALESCE(magasin,'OBRIEN')
),
-- 3) ACCESS = volumes operationnels + ESTIMATION (jamais officielle) ---
--    [VERIFIER NOM TABLE + COLONNES]. Filtres type_mouvement = VE/RT a adapter.
access_jour AS (
    SELECT
        date_vente                                              AS date_jour,     -- [VERIFIER]
        COALESCE(magasin,'OBRIEN')                              AS magasin,       -- [VERIFIER]
        COUNT(*)                                                AS nb_mouvements,
        COUNT(*) FILTER (WHERE type_mouvement = 'VE')           AS nb_ventes_ve,  -- [VERIFIER codes]
        COUNT(*) FILTER (WHERE type_mouvement = 'RT')           AS nb_retours_rt, -- [VERIFIER codes]
        SUM(quantite)                                           AS nb_articles,
        COUNT(DISTINCT caissier)                                AS nb_caissiers,
        -- estimation CA depuis Access : ventes - retours (NON officiel)
        ROUND(
          SUM(montant) FILTER (WHERE type_mouvement = 'VE')
          - COALESCE(SUM(montant) FILTER (WHERE type_mouvement = 'RT'), 0), 2)    AS ca_calcule_access
    FROM epilys.obrien_transaction                              -- [VERIFIER NOM]
    GROUP BY date_vente, COALESCE(magasin,'OBRIEN')
),
-- 4) Colonne vertebrale des dates : union Z + Access ------------------
dates AS (
    SELECT date_jour, magasin FROM z
    UNION
    SELECT date_jour, magasin FROM access_jour
)
SELECT
    d.date_jour,
    d.magasin,

    -- ---- DOLLARS OFFICIELS (Z uniquement) --------------------------
    z.ca_z_officiel,
    z.total_ttc_z,
    z.tps_z,
    z.tvq_z,
    z.profit_z,
    ROUND(100.0 * z.profit_z / NULLIF(z.ca_z_officiel,0), 1)        AS marge_z_pct,
    z.panier_moyen_z,
    z.nb_factures_z,

    -- ---- ESTIMATION ACCESS (jamais officielle) ---------------------
    a.ca_calcule_access,
    ROUND(a.ca_calcule_access - z.ca_z_officiel, 2)                AS ecart_ca,
    ROUND(100.0 * (a.ca_calcule_access - z.ca_z_officiel)
                  / NULLIF(z.ca_z_officiel,0), 2)                  AS ecart_ca_pct,
    a.nb_mouvements,
    a.nb_ventes_ve,
    a.nb_retours_rt,
    a.nb_articles,
    a.nb_caissiers,

    -- ---- RAPPROCHEMENT GL ------------------------------------------
    gl.total_ttc_gl,
    ROUND(gl.total_ttc_gl - z.total_ttc_z, 2)                      AS ecart_gl_z, -- = arrondissement caisse

    -- ---- TRACABILITE DES SOURCES -----------------------------------
    CASE
        WHEN z.date_jour IS NOT NULL AND gl.total_ttc_gl IS NOT NULL THEN 'Z+GL'
        WHEN z.date_jour IS NOT NULL                                  THEN 'Z'
        WHEN a.ca_calcule_access IS NOT NULL                          THEN 'BASE'
        ELSE 'AUCUNE'
    END                                                             AS source_validation,

    -- ---- STATUT DE FIABILITE (4 valeurs demandees) -----------------
    -- CONFIRME_BEST   : un Z existe -> dollars officiels.
    -- ESTIME_BASE     : pas de Z, estimation Access plausible (NON officiel).
    -- ECART_A_VERIFIER: pas de Z et estimation Access douteuse/aberrante.
    -- NON_MESURABLE   : ni Z ni Access exploitable.
    CASE
        WHEN z.date_jour IS NOT NULL                                   THEN 'CONFIRME_BEST'
        WHEN a.ca_calcule_access IS NOT NULL AND a.ca_calcule_access > 0
             AND a.nb_ventes_ve > 0                                    THEN 'ESTIME_BASE'
        WHEN a.ca_calcule_access IS NOT NULL                           THEN 'ECART_A_VERIFIER'
        ELSE 'NON_MESURABLE'
    END                                                             AS statut_fiabilite,

    -- ---- FLAG CALIBRATION (jours temoins : Z ET Access presents) ---
    -- Diagnostic : sur un jour ou les 2 existent, mesure si le calcul base
    -- diverge fortement du Z (seuil 5 % a ajuster avec Yahia).
    CASE
        WHEN z.date_jour IS NOT NULL AND a.ca_calcule_access IS NOT NULL
             AND ABS(a.ca_calcule_access - z.ca_z_officiel)
                 / NULLIF(z.ca_z_officiel,0) > 0.05                    THEN 'ECART_ELEVE'
        WHEN z.date_jour IS NOT NULL AND a.ca_calcule_access IS NOT NULL THEN 'OK'
        ELSE NULL
    END                                                             AS flag_calibration,

    -- ---- NOTE LECTURE (pour Sammy) ---------------------------------
    CASE
        WHEN z.date_jour IS NOT NULL
            THEN 'Dollars officiels (Z financier BEST). Taxes et CA fiables.'
        WHEN a.ca_calcule_access IS NOT NULL AND a.nb_ventes_ve > 0
            THEN 'ESTIMATION depuis base Access — NON officiel, ne pas utiliser pour fiscal.'
        ELSE 'Donnee insuffisante pour mesurer le CA de cette journee.'
    END                                                             AS note_limite

FROM        dates       d
LEFT JOIN   z           ON z.date_jour  = d.date_jour AND z.magasin  = d.magasin
LEFT JOIN   gl          ON gl.date_jour = d.date_jour AND gl.magasin = d.magasin
LEFT JOIN   access_jour a ON a.date_jour = d.date_jour AND a.magasin = d.magasin
ORDER BY    d.date_jour, d.magasin;

-- =====================================================================
-- PERFORMANCE : si l'agregat Access est lourd (millions de lignes),
-- convertir en MATERIALIZED VIEW + index, et REFRESH quotidien :
--   CREATE MATERIALIZED VIEW epilys_bi.mv_finance_journee_calculee AS
--   SELECT * FROM epilys_bi.v_finance_journee_calculee;
--   CREATE INDEX ON epilys_bi.mv_finance_journee_calculee (date_jour, magasin);
--   REFRESH MATERIALIZED VIEW epilys_bi.mv_finance_journee_calculee;  -- cron quotidien
-- =====================================================================
