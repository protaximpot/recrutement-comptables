# EPILYS — Confiance migration SQL vs rapport BEST

**Objet :** prouver, magasin par magasin, ce qu'on peut utiliser des données migrées (PostgreSQL) et ce qui doit rester sur le rapport Z officiel.
**Auteur cadre :** CHAT (QA) · **Chiffres Zone 1/2 à remplir par :** CODE/CODEX (accès `.mdb` + SQL).
**Principe :** la migration Access→SQL est fiable pour le **brut et les volumes**. Les écarts avec le Z viennent de la **différence entre la table Access disponible et le rapport financier BEST**, pas d'une déformation SQL — **à confirmer par la Zone 1**.

## Légende des badges (vocabulaire UNIQUE — remplace les variantes)
| Badge | Sens | Condition |
|---|---|---|
| `MIGRATION_VERIFIEE` | Access brut = SQL | Zone 1 passée (lignes + sommes identiques) |
| `OFFICIEL_Z` | Dollar confirmé par rapport BEST Z | un Z existe |
| `ESTIME_CALIBRE` | Calculé depuis Access avec calibration prouvée | seuils J29 respectés |
| `VOLUME_FIABLE` | Volume utilisable, **pas** un dollar | migration vérifiée, pas de calibration $ |
| `ECART_A_EXPLIQUER` | Écart trop fort → ne pas utiliser pour décision financière | écart hors seuil |

---

## ZONE 1 — Contrôle de migration (Access direct vs SQL) — *FIABLE une fois mesurée*
> But : prouver que la conversion **n'a rien changé**. Test A = comparer le **même** brut des deux côtés. **Tant que ces cases ne sont pas remplies, le verdict est « présumé », pas « mesuré ».**

| Magasin | Mois | Lignes `.mdb` brut | Lignes SQL | SUM(montant) `.mdb` | SUM(montant) SQL | Identique ? | Badge |
|---|---|---:|---:|---:|---:|:--:|---|
| PIE9 | 2026-03 | _____ | _____ | _____ | _____ | ⬜ | `MIGRATION_VERIFIEE` si = |
| OBRIEN | 2026-04 | _____ | _____ | _____ | _____ | ⬜ | **cas prioritaire (−80 %)** |
| … | … | | | | | | |

**Verdict Zone 1 :** ⬜ migration fidèle (lignes & sommes égales) — _ou_ ⬜ écart de conversion localisé (préciser colonne/lignes).

---

## ZONE 2 — Comparaison métier (SQL Access vs rapport Z) — *À ANALYSER*
> Ici l'écart est **normal** : le Z n'est pas une simple somme de la table (poids, consignes NON-ADD, corrections exclues, prix=0 sur Access).

### PIE9 (volumes proches → bon candidat calibration)
| Mois | Volume SQL | Volume Z | Écart | Badge |
|---|---:|---:|---:|---|
| Février | 588 046 | 637 777 | −7,8 % | `VOLUME_FIABLE` |
| Mars | 1 259 306 | 1 299 071 | −3,1 % | `VOLUME_FIABLE` |
| Avril | 1 132 981 | 1 107 383 | +2,3 % | `VOLUME_FIABLE` |

### OBRIEN (écarts forts → diagnostic)
| Mois | Volume SQL | Volume Z | Écart | Badge |
|---|---:|---:|---:|---|
| Décembre | 1 114 293 | 805 084 | +38,4 % | `ECART_A_EXPLIQUER` (Access > Z = artefact, pas une perte) |
| Février | 763 830 | 902 847 | −15,4 % | `ECART_A_EXPLIQUER` |
| Mars | 706 879 | 858 909 | −17,7 % | `ECART_A_EXPLIQUER` |
| Avril | 147 123 | 754 511 | −80,5 % | `ECART_A_EXPLIQUER` (caisse/.mdb manquant probable) |

> ⚠️ Comparaison sur la **quantité** (métrique bruitée : unités+poids+consignes). À refaire sur **factures et $** pour isoler le vrai écart.

---

## ZONE 3 — Décision (utilisable / estimé / bloqué)
| Question | Réponse |
|---|---|
| SQL a-t-il changé les chiffres Access ? | **Non** *(à confirmer Zone 1 — surtout OBRIEN avril)* |
| Volumes SQL fiables ? | **Oui** (PIE9 ; OBRIEN sauf avril) |
| Dollars SQL Access fiables ? | **Pas encore** (prix=0 sur Access) |
| Le Z est-il la source officielle des dollars ? | **Oui** |
| SQL utilisable pour tendances/ventes/retours/articles/caissiers ? | **Oui** |
| SQL seul pour CA / TPS-TVQ / paiements ? | **Non**, sauf calibration prouvée (PIE9 en cours) |

**Conclusion :** SQL est une **copie fiable de la base Access**. Mais **la base Access ne contient pas tout ce que le Z utilise pour les dollars** (prix=0, source de calcul interne BEST). → Dollars = Z ; Access = volumes/tendances ; PIE9 = calibration possible ; OBRIEN avril = bloqué tant que la source manquante n'est pas trouvée (cf. courriel BEST POS).
