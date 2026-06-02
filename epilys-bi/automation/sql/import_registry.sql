-- =====================================================================
-- J28 — Table de controle des imports BEST POS + reconciliation
-- =====================================================================
-- Auteur : CHAT (architecte)  /  A executer par : CODE (PostgreSQL 5433)
-- Additif & reversible. Schema dedie 'epilys_ops' (ne touche aucune source).
-- Valide Yahia : 7 motifs de refus + seuil volume +-50% (pilote).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS epilys_ops;

-- 1) Registre des imports : LA verite de ce qui est entre / refuse -----
CREATE TABLE IF NOT EXISTS epilys_ops.import_registry (
    id                bigserial PRIMARY KEY,
    fichier_nom       text        NOT NULL,
    fichier_md5       text        NOT NULL,
    magasin_detecte   text,                         -- OBRIEN / PIE9 (par CONTENU)
    magasin_declare   text,                         -- ce que l'operateur/nom annonce
    type_base         text,                         -- inventaire / transaction
    date_min          date,
    date_max          date,
    nb_lignes_source  bigint,
    nb_tables         int,
    operateur         text,
    statut            text        NOT NULL DEFAULT 'RECU'
                      CHECK (statut IN ('RECU','QUARANTAINE','VALIDE','IMPORTE','REJETE')),
    motif             text,                         -- raison si quarantaine/refus
    batch_id          uuid,                         -- lot d'import -> rollback donnees
    drive_archive_id  text,                         -- id Google Drive de l'original
    checksum_post     text,                         -- controle apres import (fidelite)
    date_reception    timestamptz NOT NULL DEFAULT now(),
    date_decision     timestamptz
);

-- Anti-doublon : un meme contenu (md5) ne peut etre IMPORTE qu'une fois.
CREATE UNIQUE INDEX IF NOT EXISTS ux_import_registry_md5_importe
    ON epilys_ops.import_registry (fichier_md5)
    WHERE statut = 'IMPORTE';

CREATE INDEX IF NOT EXISTS ix_import_registry_magasin_date
    ON epilys_ops.import_registry (magasin_detecte, date_max);

-- 2) Reconciliation jour/rayon/paiement : Z officiel vs Access SQL ------
CREATE TABLE IF NOT EXISTS epilys_ops.reconciliation_jour (
    id              bigserial PRIMARY KEY,
    magasin         text NOT NULL,
    date_jour       date NOT NULL,
    dimension       text NOT NULL,                  -- 'JOUR' | 'DEPARTEMENT' | 'PAIEMENT'
    cle             text,                            -- nom rayon / mode paiement (NULL si JOUR)
    valeur_z        numeric(14,2),                   -- officiel (rapport Z)
    valeur_sql      numeric(14,2),                   -- agrege depuis Access SQL
    ecart_dollars   numeric(14,2) GENERATED ALWAYS AS (valeur_sql - valeur_z) STORED,
    ecart_pct       numeric(7,2),                    -- calcule a l'insert (NULLIF z=0)
    statut          text NOT NULL
                    CHECK (statut IN ('OFFICIEL_Z','ACCESS_VOLUME','NON_CALCULABLE','A_CORRIGER')),
    cause           text,
    batch_id        uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (magasin, date_jour, dimension, cle)
);

-- 3) Vue lisible pour Yahia : etat des imports recents -----------------
CREATE OR REPLACE VIEW epilys_ops.v_import_dernier AS
SELECT date_reception, fichier_nom, magasin_detecte, type_base,
       date_min, date_max, nb_lignes_source, statut, motif
FROM   epilys_ops.import_registry
ORDER  BY date_reception DESC;

-- ROLLBACK : DROP SCHEMA IF EXISTS epilys_ops CASCADE;  (schema dedie, sans source)
