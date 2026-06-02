#!/usr/bin/env python3
# =====================================================================
# J28 - Porte de securite d'import BEST POS (implementation de reference)
# =====================================================================
# Auteur : CHAT (architecte) / A executer & adapter par : CODE/CODEX sur l'hote
# Statut : SQUELETTE EXECUTABLE. Non destructif. Ne PROMEUT rien.
#
# Decisions Yahia (validees) : 7 motifs de refus, seuil volume +-50% (pilote),
# tout fichier douteux -> quarantaine, aucune publication sans validation Yahia.
#
# Dependances hote : mdbtools (mdb-tables, mdb-export, mdb-schema), iconv,
# psql/psycopg2. CHAT n'a PAS d'acces DB/fichiers -> a tester cote VPS/Mac.
# Les elements specifiques au schema reel sont marques  # [VERIFIER]
# =====================================================================
from __future__ import annotations
import hashlib, os, shutil, subprocess, sys, uuid
from dataclasses import dataclass, field

# ---- Parametres (pilote) --------------------------------------------
SEUIL_VOLUME_PCT      = 0.50          # +-50% valide Yahia
PLANCHER_DATE         = "2019-01-01"  # dates < plancher = aberrantes
FACTEUR_DISQUE        = 2.0           # libre >= 2x taille SQL projetee
RATIO_MDB_VERS_SQL    = 4.0           # estimation grossiere .mdb -> SQL (index+temp)
QUARANTAINE_DIR       = os.environ.get("BESTPOS_QUARANTINE", "/var/bestpos/quarantine")
FINGERPRINT_TABLES    = {"transaction", "article", "departement"}  # [VERIFIER] tables attendues
MARQUEUR_MAGASIN      = {"epilyspieix": "PIE9", "obrien": "OBRIEN"} # [VERIFIER] marqueur interne


@dataclass
class Resultat:
    statut: str = "RECU"               # RECU/QUARANTAINE/VALIDE/REFUSE
    motif:  str | None = None
    infos:  dict = field(default_factory=dict)

    def refuse(self, motif: str) -> "Resultat":
        self.statut, self.motif = "QUARANTAINE", motif
        return self


# ---- Helpers hote (mdbtools / md5 / disque) -------------------------
def md5_fichier(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def mdb_tables(path: str) -> list[str]:
    out = subprocess.run(["mdb-tables", "-1", path], capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        raise RuntimeError(f"mdb-tables a echoue: {out.stderr.strip()}")
    return [t.strip().lower() for t in out.stdout.split("\n") if t.strip()]

def mdb_export_iter(path: str, table: str):
    """Exporte une table en CSV UTF-8 (force CP1252->UTF-8). Generator de lignes."""
    p = subprocess.Popen(["mdb-export", "-d", ";", path, table],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    conv = subprocess.Popen(["iconv", "-f", "WINDOWS-1252", "-t", "UTF-8//TRANSLIT"],
                           stdin=p.stdout, stdout=subprocess.PIPE, text=True)
    p.stdout.close()
    for line in conv.stdout:
        yield line


# ---- Les 9 controles G1..G9 (chaque echec -> quarantaine/refus) -----
def porte_securite(path: str, magasin_declare: str, operateur: str,
                   db, prod_date_max, volume_moyen) -> Resultat:
    """db, prod_date_max(magasin), volume_moyen(magasin) : injectes par l'appelant
    (acces PostgreSQL cote hote). Retourne Resultat ; n'IMPORTE rien."""
    r = Resultat(infos={"fichier": os.path.basename(path)})

    # G1 - Lisibilite + tables presentes
    try:
        tables = set(mdb_tables(path))
    except Exception as e:
        return r.refuse(f"G1 fichier illisible/corrompu: {e}")
    r.infos["tables"] = sorted(tables)

    # G4 - Bon client / structure (fingerprint) - tot pour eviter de lire un .mdb etranger
    if not FINGERPRINT_TABLES.issubset(tables):
        manquantes = FINGERPRINT_TABLES - tables
        return r.refuse(f"G4 structure/client inattendu (tables manquantes: {manquantes})")

    # G2 - Doublon MD5 deja IMPORTE
    md5 = md5_fichier(path); r.infos["md5"] = md5
    if db.existe_md5_importe(md5):                       # SELECT 1 ... statut='IMPORTE'
        r.statut, r.motif = "QUARANTAINE", "G2 doublon: ce fichier est deja importe"
        return r

    # G3 - Magasin par CONTENU (marqueur interne) vs declare
    magasin = detecter_magasin(path)                    # lit l'en-tete/un ID interne
    r.infos["magasin_detecte"] = magasin
    if magasin is None:
        return r.refuse("G3 magasin indetectable dans le contenu")
    if magasin_declare and magasin_declare.upper() != magasin:
        return r.refuse(f"G3 magasin incoherent: declare {magasin_declare} vs contenu {magasin}")

    # Bornes de dates + volume (un seul balayage des transactions)
    dmin, dmax, nb_lignes = bornes_dates_et_volume(path)  # [VERIFIER] colonne date
    r.infos.update(date_min=dmin, date_max=dmax, nb_lignes=nb_lignes)

    # G6 - Plage de dates coherente
    if not (dmin and dmax) or dmin > dmax:
        return r.refuse("G6 dates aberrantes (min/max invalides)")
    if str(dmin) < PLANCHER_DATE:
        return r.refuse(f"G6 date trop ancienne (< {PLANCHER_DATE})")

    # G5 - Anti-base perimee : date_max(fichier) >= date_max(prod)
    pmax = prod_date_max(magasin)
    if pmax and dmax < pmax:
        return r.refuse(f"G5 base perimee: date_max fichier {dmax} < prod {pmax}")

    # G7 - Volume plausible (+-50%)
    moy = volume_moyen(magasin)
    if moy and abs(nb_lignes - moy) > SEUIL_VOLUME_PCT * moy:
        return r.refuse(f"G7 volume anormal: {nb_lignes} vs moyenne {moy:.0f} (+-{int(SEUIL_VOLUME_PCT*100)}%)")

    # G8 - Espace disque suffisant
    libre = shutil.disk_usage(os.path.dirname(path) or ".").free
    projete = os.path.getsize(path) * RATIO_MDB_VERS_SQL
    if libre < FACTEUR_DISQUE * projete:
        return r.refuse(f"G8 espace insuffisant: libre {libre} < {FACTEUR_DISQUE}x projete {projete:.0f}")

    # G9 - Encodage : zero caractere de remplacement apres conversion UTF-8
    if contient_caractere_casse(path, tables):
        return r.refuse("G9 encodage a corriger (caractere casse dans les libelles)")

    r.statut = "VALIDE"
    return r


# ---- Briques specifiques au schema (a finaliser cote hote) ----------
def detecter_magasin(path: str) -> str | None:
    """Lit un marqueur interne (en-tete 'Pour Epilyspieix' ou ID magasin). [VERIFIER]"""
    try:
        for table in ("entete", "config", "transaction"):   # [VERIFIER] ou est le marqueur
            if table not in mdb_tables(path):
                continue
            for i, line in enumerate(mdb_export_iter(path, table)):
                low = line.lower()
                for marqueur, code in MARQUEUR_MAGASIN.items():
                    if marqueur in low:
                        return code
                if i > 50:
                    break
    except Exception:
        return None
    return None

def bornes_dates_et_volume(path: str):
    """Min/max de la colonne date + nb lignes de la table transaction. [VERIFIER colonne]"""
    dmin = dmax = None; nb = 0
    DATE_COL_IDX = 0   # [VERIFIER] index/nom colonne date dans le CSV exporte
    for i, line in enumerate(mdb_export_iter(path, "transaction")):  # [VERIFIER] nom table
        if i == 0:
            continue  # entete CSV
        nb += 1
        try:
            d = line.split(";")[DATE_COL_IDX].strip().strip('"')[:10]
            if d:
                dmin = d if dmin is None or d < dmin else dmin
                dmax = d if dmax is None or d > dmax else dmax
        except Exception:
            pass
    return dmin, dmax, nb

def contient_caractere_casse(path: str, tables: set[str]) -> bool:
    """Detecte un caractere de remplacement U+FFFD apres conversion UTF-8."""
    for table in (t for t in ("article", "departement") if t in tables):  # [VERIFIER]
        for i, line in enumerate(mdb_export_iter(path, table)):
            if "�" in line:
                return True
            if i > 500:
                break
    return False


# ---- CLI : un fichier -> decision (sans import) ----------------------
if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: porte_securite.py <fichier.mdb> <magasin_declare> [operateur]")
        sys.exit(2)
    print("NB: stub - brancher db/prod_date_max/volume_moyen (acces PostgreSQL hote) "
          "puis ecrire le resultat dans epilys_ops.import_registry, "
          "et deplacer le fichier vers QUARANTAINE_DIR si statut=QUARANTAINE.")
    print(f"  batch_id propose: {uuid.uuid4()}")
