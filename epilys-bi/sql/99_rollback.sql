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

DROP VIEW IF EXISTS epilys_bi.v_finance_journee_calculee;
-- Si une MV a ete creee :
DROP MATERIALIZED VIEW IF EXISTS epilys_bi.mv_finance_journee_calculee;

-- Supprimer le schema UNIQUEMENT s'il est vide (securite : pas de CASCADE).
DROP SCHEMA IF EXISTS epilys_bi RESTRICT;

-- NOTE : aucun DROP/TRUNCATE sur epilys.* — interdit par les garde-fous.
