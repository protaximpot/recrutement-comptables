-- =====================================================================
-- EPILYS BI — ROLLBACK de la couche finance quotidienne
-- =====================================================================
-- A executer par CODE si on veut annuler la livraison cote PostgreSQL.
-- Le rollback Metabase (dashboard + cartes) est separe : voir
-- /tmp/j19_finance_rollback.sql cote VPS (genere par CODE a la creation).
--
-- Ce rollback est CIBLE : il ne supprime QUE les objets crees par cette
-- livraison. Il ne touche AUCUNE table source epilys.*.
-- =====================================================================

-- Ordre : la vue variation depend de la vue jour -> on la supprime d'abord.
DROP VIEW IF EXISTS epilys_bi.v_finance_variation;
DROP VIEW IF EXISTS epilys_bi.v_finance_journee_calculee;
-- Si une MV a ete creee :
DROP MATERIALIZED VIEW IF EXISTS epilys_bi.mv_finance_journee_calculee;

-- !!! IMPORTANT : le schema epilys_bi PREEXISTE (il contient deja mv_fact_tx,
--     la facade 7,36M lignes du dashboard #13). NE PAS le supprimer.
--     La ligne ci-dessous est volontairement EN RESTRICT (jamais CASCADE) :
--     elle echouerait tant que mv_fact_tx existe (comportement voulu), donc
--     on la laisse COMMENTEE pour ne pas risquer de toucher l'existant.
-- DROP SCHEMA IF EXISTS epilys_bi RESTRICT;

-- NOTE : aucun DROP/TRUNCATE sur epilys.* — interdit par les garde-fous.
