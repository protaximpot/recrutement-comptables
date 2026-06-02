# J28 — Tests minimums avant tout import réel (exécutables)

**À faire passer AVANT le premier import en production.** Chaque test = un fichier-fixture + une assertion sur le `Resultat` de `porte_securite.py` ou sur `epilys_ops.import_registry`. Aucun test ne touche la prod (bases témoins + schéma de staging jetable).

| # | Fixture (entrée) | Action | Assertion (attendu) |
|---|---|---|---|
| **T1** | `.mdb` dont le MD5 est déjà en statut `IMPORTE` | porte | `statut=QUARANTAINE`, motif commence par `G2 doublon` |
| **T2** | base **PIE9** déclarée `OBRIEN` | porte | `QUARANTAINE`, `G3 magasin incoherent` |
| **T3** | base dont `date_max` < `date_max(prod)` du magasin | porte | `QUARANTAINE`, `G5 base perimee` |
| **T4** | `.mdb` sans les tables `transaction/article/departement` | porte | `QUARANTAINE`, `G4 structure/client inattendu` |
| **T5** | base avec accents (é, è, ç) | conversion | export UTF-8 sans aucun `�` ; `contient_caractere_casse()==False` |
| **T6** | base témoin de référence | fidélité | `nb_lignes_SQL == nb_lignes_source` **et** `SUM(montant)_source == SUM(montant)_SQL` (au cent) |
| **T7** | disque rempli artificiellement (< 2× projeté) | porte | `QUARANTAINE`, `G8 espace insuffisant`, **aucun** demi-import |
| **T8** | importer 2× la même base valide | pipeline | 2e passage = doublon (T1) ; **0 ligne dupliquée** en base |
| **T9** | jour avec rapport Z connu (ex. PIE9 10-avr = TTC 148 597,63) | réconciliation | ligne `reconciliation_jour` JOUR : `valeur_z` renseignée ; écart vs SQL calculé et catégorisé |
| **T10** | un `batch_id` importé | rollback | `DELETE ... WHERE batch_id=…` retire tout le lot ; prod (OBRIEN) **intacte** |
| **T11** | fichier mis en quarantaine | vérif | **aucune** écriture dans `epilys.*` / `epilys_pie9.*` ; seul `import_registry` a une ligne `QUARANTAINE` |
| **T12** | après un import valide | Metabase | dashboards **#13 / #14 / #15 inchangés** (nb dashcards + requêtes identiques au snapshot) |

## Squelette pytest (à compléter côté hôte)

```python
import porte_securite as P

class FakeDB:           # remplace l'accès PostgreSQL en test
    importes = {"<md5_deja_importe>"}
    def existe_md5_importe(self, md5): return md5 in self.importes

PROD_MAX = {"PIE9": "2026-05-10", "OBRIEN": "2026-05-06"}
VOL_MOY  = {"PIE9": 50000, "OBRIEN": 80000}

def test_T1_doublon(tmp_path):
    f = fixture_md5_connu(tmp_path)          # base dont md5 ∈ FakeDB.importes
    r = P.porte_securite(str(f), "PIE9", "yahia", FakeDB(),
                         PROD_MAX.get, VOL_MOY.get)
    assert r.statut == "QUARANTAINE" and r.motif.startswith("G2")

def test_T2_mauvais_magasin(tmp_path):
    f = fixture_pie9(tmp_path)
    r = P.porte_securite(str(f), "OBRIEN", "yahia", FakeDB(),
                         PROD_MAX.get, VOL_MOY.get)
    assert r.statut == "QUARANTAINE" and "G3" in r.motif

def test_T3_base_perimee(tmp_path):
    f = fixture_pie9_vieille(tmp_path)        # date_max < PROD_MAX["PIE9"]
    r = P.porte_securite(str(f), "PIE9", "yahia", FakeDB(),
                         PROD_MAX.get, VOL_MOY.get)
    assert r.statut == "QUARANTAINE" and "G5" in r.motif
# ... T4..T12 sur le même modèle (fidélité/rollback/Metabase = SQL + snapshot)
```

## Règle de sortie
- **Tous les 12 tests verts** = la porte est sûre → on autorise le **premier import pilote** (toujours en staging, validation Yahia avant Metabase).
- **Un seul test rouge** = NO-GO, on corrige avant.

## Données de référence pour T9 (réconciliation Z — déjà vérifiées par CHAT)
PIE-IX : 10-fév TTC 41 865,22 · 20-fév 78 424,80 · 10-mars 148 922,89 · 20-mars 82 549,12 · 10-avr 148 597,63 · 20-avr 79 534,99 · 10-mai 169 100,46.
⚠️ Ne jamais sommer la section CORRECTIONS (20-mars = 1,08 M$ ; 20-fév = 59,7 G$ = valeurs corrompues du journal BEST).
