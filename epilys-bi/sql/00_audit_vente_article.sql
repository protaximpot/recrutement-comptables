-- =====================================================================
-- EPILYS BI — ETAPE 0 (BLOQUANTE) : AUDIT DE epilys.obrien_vente_article
-- =====================================================================
-- Auteur : CHAT (analyse)  /  A executer par : CODE (VPS PostgreSQL)
-- Objectif : avant de publier la moindre carte "couverture Vente article"
--            (#165), prouver QUELLE source alimente cette table et POURQUOI
--            le rapport J18 annonçait une couverture de 65,5 % (118 008,75 $).
--
-- Rappel des faits verifies sur les PDF sources (jour temoin 2026-01-01) :
--   - Z financier (officiel)        CA HT = 180 193,55 $
--   - "Ventes par VENDEUR" (PDF)    Total = 182 370,46 $   (> Z, donc PAS un sous-ensemble)
--   - J18 "Detail Vente article"            = 118 008,75 $  -> introuvable dans les PDF fournis
--
-- Il existe DEUX rapports distincts cote BEST :
--   20260101vente.pdf         (ventes par ARTICLE)
--   20260101vente-vendeur.pdf (ventes par VENDEUR)
-- => Cet audit doit dire lequel alimente reellement obrien_vente_article.
--
-- 100 % READ-ONLY. Aucune ecriture.
-- =====================================================================

-- A. Schema reel de la table (colonnes + types)
SELECT ordinal_position, column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'epilys'
  AND  table_name   = 'obrien_vente_article'
ORDER  BY ordinal_position;

-- B. Echantillon brut sur le jour temoin (adapter le nom de colonne date/ventes
--    selon le resultat de A : ci-dessous on suppose date_jour + ventes/montant)
SELECT *
FROM   epilys.obrien_vente_article
WHERE  date_jour = DATE '2026-01-01'
LIMIT  50;

-- C. Total du jour temoin -> c'est LE chiffre qui tranche la source
--    (remplacer "ventes" par la vraie colonne de montant trouvee en A)
SELECT date_jour,
       COUNT(*)                              AS nb_lignes,
       ROUND(SUM(ventes), 2)                 AS total_vente_article
FROM   epilys.obrien_vente_article
WHERE  date_jour = DATE '2026-01-01'
GROUP  BY date_jour;

-- D. Grille de lecture du resultat de C (verdict automatique a reporter a CHAT) :
--    total ≈ 182 370,46  -> la table = "ventes par VENDEUR" (mal nommee "article")
--                           => la carte couverture est FAUSSE par construction
--                              (un total > CA Z ne peut pas etre un detail a 65,5 %)
--    total ≈ 180 193,55  -> la table = ventilation departement/article = CA Z complet
--                           => "couverture" ≈ 100 %, le 65,5 % du J18 est errone
--    total ≈ 118 008,75  -> table = extrait article PARTIEL
--                           => couverture 65,5 % plausible, MAIS il faut documenter
--                              pourquoi 34,5 % du CA n'a pas de detail article
--    autre valeur        -> source inconnue : NE PAS publier la carte, escalader Yahia

-- E. Couverture recalculee proprement vs le Z officiel (ne s'execute que si la
--    table obrien_z_journalier expose bien ca_ht — sinon ignorer)
SELECT a.date_jour,
       ROUND(SUM(a.ventes), 2)                                  AS detail_article,
       z.ca_ht                                                  AS ca_z_officiel,
       ROUND(SUM(a.ventes) - z.ca_ht, 2)                        AS ecart,
       ROUND(100.0 * SUM(a.ventes) / NULLIF(z.ca_ht, 0), 1)     AS couverture_pct
FROM   epilys.obrien_vente_article a
JOIN   epilys.obrien_z_journalier  z USING (date_jour)
WHERE  a.date_jour = DATE '2026-01-01'
GROUP  BY a.date_jour, z.ca_ht;

-- VERDICT ATTENDU (a renvoyer a CHAT/Yahia via RELAY avant toute publication #165) :
--   - source reelle de obrien_vente_article = ARTICLE | VENDEUR | inconnue
--   - total jour temoin = ............ $
--   - couverture reelle vs Z = .......%
--   - decision : carte couverture FIABLE / A CORRIGER / A RETIRER
