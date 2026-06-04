# EPILYS — Conception du cockpit (J33)

**Auteur :** CHAT (architecte/QA) · **Statut :** conception, aucun changement production.
**Sources de vérité :**
- **`Z/AAAAMMJJ.mdb` → table `Day`** = **DOLLARS OFFICIELS** (prix réel, coût, taxes, paiements, caissier, facture, RefMEV). Vérifié au cent vs rapport Z.
- **`Transaction.mdb`** = volumes / mouvements / **historique long** (2020→). Prix souvent 0 → jamais pour les $.
- **`Inventaire.mdb`** = catalogue, prix/coût courant, départements, fournisseurs.

**Règle d'or :** un chiffre = une source + un badge. `OFFICIEL_Z` (dollars Day/Z), `VOLUME_FIABLE` (volumes Transaction), `ESTIME_CALIBRE` (estimé prouvé), `ECART_A_EXPLIQUER`. **Jamais mélanger officiel et estimé sans badge.**

> **Ce que la table `Day` débloque enfin** : `Prix` (réel) + `Coutant` (coût) ⇒ **marge réelle** ; `Vendeur` ⇒ caissier en **dollars** ; `Date` (horodatée) ⇒ **heure** ; `Departement`, `CodeUPC`/`Description`, `Fournisseur`, `Groupe`, `MixMatch` (promo), modes de paiement (`PM`).

---

## 0. Architecture : 2 cockpits
| | **Cockpit SAMMY (simple)** | **Cockpit YAHIA/ADMIN (détaillé)** |
|---|---|---|
| But | piloter le magasin au quotidien | finance, marge, fiabilité, anomalies, fiscal |
| Contenu | CA, panier, top rayons, affluence, événements | marge par article/caissier/fournisseur, taxes, écarts Z, calibration, alertes |
| Dollars | officiels Z, lecture simple | officiels Z + détail + contrôles |
| Ton | « combien on a vendu, quoi marche » | « où est la marge, où est le risque » |

---

## 1. KPI FINANCIERS (source `Z/Day`) — OFFICIEL_Z
| KPI | Formule (table Day) |
|---|---|
| CA HT | Σ(Qte·Prix) ventes (IT/IB/DP/ED) − consigne |
| TTC encaissé | Σ(Prix) où Code ∈ PM,RE,RO |
| TPS / TVQ | Σ(Prix\|T1) / Σ(Prix\|T2) |
| **Profit brut** | Σ((Prix−Coutant)·Qte) sur ventes |
| **Marge %** | profit ÷ CA HT |
| Panier moyen | CA HT ÷ nb factures |
| Nb factures / nb articles | distinct NoFacture / Σ Qte |
| Articles par panier | nb articles ÷ nb factures |
| CA / profit **par département** | group by Departement |
| CA **par caissier** | group by Vendeur |
| CA **par heure** | group by hour(Date) |
| **Modes de paiement** | Σ(Prix\|PM) group by Description (argent/débit/Visa/MC/Amex) |
| Retours $ / **taux de retour** | Σ\|RE\| ; Σ\|RE\| ÷ CA |
| Escomptes accordés | Σ\|ED\| |
| Consigne | dept CONSIGNE (net des crédits) |

## 2. KPI OPÉRATIONNELS (`Transaction.mdb` historique + `Day`)
- Affluence : nb factures **par heure / jour de semaine**, **pic horaire**, jours forts/faibles.
- Volumes : ventes VE, retours RT, articles vendus distincts, quantités (kg pour rayons au poids).
- **Productivité caissier** (maintenant en $) : CA/heure, factures/heure, panier moyen par caissier, taux de retour par caissier.
- Vitesse : articles/minute, tiroirs ouverts, duplicatas (contrôle).
- Tendance long terme (Transaction 2020→) : CA/volume mensuel, saisonnalité, croissance.
- Qualité : lignes prix=0 (Transaction), articles sans coût, anomalies de caisse.

## 3. KPI ACHAT / PRICING (`Inventaire` + `Day.Coutant/Fournisseur`)
- **Marge par article / département / fournisseur** (Prix−Coutant).
- Articles à **marge négative** (souvent artefact balances/poids → à isoler, pas à paniquer).
- Couverture : % articles avec prix / avec coût renseigné.
- **Articles dormants** (0 vente depuis N jours) + valeur immobilisée.
- **Rotation** (ventes ÷ stock) si stock dispo ; produits à rotation rapide vs lente.
- **Top fournisseurs** en $ vendus / coût d'achat ; dépendance fournisseur.
- Écart **prix catalogue vs prix réellement appliqué** (Day vs Inventaire).
- Produits en **promo** (MixMatch/Groupe) : volume et effet sur marge.
- Prix moyen/kg des rayons au poids (viande, fruits/légumes).

## 4. KPI RAMADAN / EID / CALENDRIER HIJRI ⭐ (le différenciateur)
> Construire une dimension **`dim_date_hijri`** : date grégorienne ↔ date Hijri + drapeaux d'événement (Ramadan, 10 derniers jours, veille Eid, Eid al-Fitr, Eid al-Adha, Mawlid, Achoura, jours fériés QC).

- **CA quotidien Ramadan vs même jour Hijri an dernier** (1 Ramadan an N vs an N-1).
- **CA total Ramadan** et **profil intra-Ramadan** (montée, pic des **10 derniers jours**, **veille de l'Eid** = sommet).
- **Pic horaire spécial Ramadan** (achats **avant l'iftar**, 2e vague **après tarawih**).
- **Rayons traditionnels** (dattes, **feuilles de brick**, chorba/**frik**, pâtisserie orientale, **viande/agneau**, thé/café, boissons, semoule) : CA et part pendant Ramadan/Eid vs hors période.
- **Eid al-Adha** : pic **viande/agneau** ; **Eid al-Fitr** : pic pâtisserie/dattes/cadeaux.
- Panier moyen et affluence par phase (pré-Ramadan, Ramadan, Eid).
- **Compte à rebours événement** + recommandation d'achat (cf. alertes).

## 5. COMPARAISONS (chaque KPi doit pouvoir se comparer)
Jour précédent · **même jour J-7** (semaine préc.) · semaine vs semaine · **MoM** (mois) · **YoY** (même mois an dernier) · cumulatif **MTD / YTD** · **même période Hijri an dernier** · moyenne 4 dernières semaines. → toujours afficher **variation $ ET %** (+ marge en **points**).

## 6. ALERTES INTELLIGENTES
| Alerte | Déclencheur | Pour qui |
|---|---|---|
| 🔴 Rupture probable | rotation élevée + stock bas (ou ventes en hausse + stock ↓) | Sammy/Akram |
| 🟠 Surstock / dormant | 0 vente N jours + stock/valeur élevés | Akram |
| 🟠 Baisse de marge | marge dept < seuil ou < moyenne mobile | Yahia |
| 🟠 Hausse des retours | taux retour jour/caissier > seuil | Sammy/Yahia |
| ⭐ Produit vedette | croissance ventes > X % vs J-7/4 sem. | Sammy/Akram |
| 🟣 Pré-événement | Ramadan/Eid dans X jours → liste d'achats traditionnels recommandée | Akram/Sammy |
| ⚠️ Écart de caisse | paiements ≠ TTC au-delà de l'arrondi | Yahia |
| ⚠️ Prix/marge aberrant | marge négative hors rayon au poids | Yahia |
| ⚠️ Donnée aberrante | valeur Day hors bande (cf. Z corrompu 59,7 G$) | Yahia (garde-fou) |

## 7. CARTES METABASE RECOMMANDÉES (extrait — nom · objectif · source · formule · filtre · cible)
**Cockpit SAMMY**
1. **CA du jour** · voir les ventes officielles · Day · Σ ventes − consigne · {période/dept} · Sammy
2. **CA vs hier / J-7 / an dernier** · tendance · Day+dim_date · variation $/% · {période} · Sammy
3. **Top 10 rayons (CA & profit)** · ce qui fait vivre le magasin · Day · group Departement · {période} · Sammy
4. **Affluence par heure** · staffing · Transaction/Day · count factures/heure · {jour} · Sammy
5. **Panier moyen** · qualité du ticket · Day · CA÷factures · {période} · Sammy
6. **Modes de paiement** · argent vs carte · Day(PM) · Σ par mode · {période} · Sammy
7. **Spécial Ramadan/Eid** · suivi événement · Day+dim_date_hijri · CA vs an dernier Hijri · {événement} · Sammy
8. **Top produits traditionnels** · dattes/brick/viande… · Day · CA par groupe traditionnel · {période} · Sammy

**Cockpit YAHIA/ADMIN**
9. **Marge par département / article** · où est le profit · Day(Prix−Coutant) · {période/dept} · Yahia
10. **Taxes TPS/TVQ officielles** · fiscal · Day(T1,T2) · Σ · {période} · Yahia
11. **Productivité caissier ($)** · RH · Day(Vendeur) · CA/heure, taux retour · {période} · Yahia
12. **Top fournisseurs** · achats/dépendance · Day(Fournisseur) · Σ ventes/coût · {période} · Yahia
13. **Dormants & rotation** · argent immobilisé · Inventaire+Transaction · 0 vente N j · {dept} · Yahia/Akram
14. **Réconciliation Z (officiel vs calculé)** · fiabilité · Day vs rapport Z · écart · {jour} · Yahia
15. **Alertes consolidées** · pilotage risque · vues alertes · — · Yahia

## 8. ANALYSE AUTO SOUS CHAQUE CARTE (langage simple, dynamique)
Phrase générée selon le filtre : **valeur · variation vs période précédente ($/%/points) · lecture (hausse/baisse/stable) · cause probable si dispo · fiabilité (badge) · action recommandée**.
Ex. : « CA du 1er Ramadan : 24 500 $, +18 % vs même jour l'an dernier. ↑ Forte hausse, cohérente avec le début du Ramadan. Officiel (Z). Action : prévoir réassort dattes/brick pour les 10 derniers jours. »
Règle : si la valeur est estimée (Access), commencer par « ⚠️ Estimé — non officiel ».

## 9. QUI VOIT QUOI
**Sammy seulement** : CA, panier, top rayons/produits, affluence, événements religieux, alertes ruptures/vedettes. *(Pas la marge fine ni les coûts/fournisseurs ni le fiscal.)*
**Yahia/admin** : tout Sammy **+** marge par article/caissier/fournisseur, **coûts**, TPS/TVQ, réconciliation/fiabilité, écarts de caisse, calibration, données brutes. Gouvernance : permissions Metabase par collection ; Sammy ne voit pas les coûts d'achat (sensible).

## 10. LIMITES & RISQUES
- **Dollars = Z/Day uniquement** ; Transaction = volumes (prix=0). Ne jamais convertir un volume en $ sans calibration badgée.
- **Marge** fiable seulement si `Coutant` renseigné — rayons au **poids** (balances) donnent des marges aberrantes (artefact) → isoler.
- **Données aberrantes** possibles (Z mensuel 20-fév = 59,7 G$) → borne anti-aberration obligatoire avant tout agrégat.
- **Calendrier Hijri** : à charger/valider (dates d'observation lunaire varient ±1 j) — faire valider les dates d'événement par Yahia/Sammy.
- **OBRIEN avril** : source Access tronquée → exclure des comparaisons tant que non corrigé.
- **Historique** : Transaction remonte à 2020 (volumes) mais les **dollars Z** ne couvrent que la période des fichiers `Z/*.mdb` (mai 2025→) → comparaisons $ YoY limitées au début.
- **Consigne** : netter les crédits (résidu ~16 $/jour vu en vérif).
- **Aucune mise en production / Metabase sans validation Yahia.**
