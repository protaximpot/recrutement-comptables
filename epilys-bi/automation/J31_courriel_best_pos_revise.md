# Courriel à envoyer à BEST POS (version révisée)

**Objet :** Source officielle du rapport financier Z — alimenter un tableau de bord externe

Bonjour,

Nous sommes **ProtaxImpôt, mandataire CPA d'Épilys**. Nous mettons en place des tableaux de bord externes à partir des données BEST POS, **sans modifier BEST POS**.

Nous avons accès aux bases Access `Inventaire.mdb` et `Transaction.mdb`. **Nous avons vérifié que la copie vers notre base (PostgreSQL) reproduit fidèlement les volumes de `Transaction.mdb`** (chiffres identiques). En revanche, **les montants du rapport financier Z ne peuvent pas être reconstruits depuis `Transaction.mdb`** : de très nombreuses lignes de vente y ont `Prix = 0` (les volumes sont présents, mais pas les montants). Les montants CA, taxes et paiements du Z proviennent donc d'une autre source ou d'un calcul interne.

Nous cherchons simplement la **source officielle** qui alimente le rapport Z.

**Questions prioritaires :**
1. Existe-t-il un **export officiel du rapport financier Z en CSV/Excel** — idéalement **planifiable automatiquement** (quotidien/mensuel) ? Un **fichier exemple** nous serait très utile.
2. Quelle **table / base / fichier** BEST POS utilise pour générer le Z (CA, taxes, paiements, profit, ventes par département et par caissier) ?
3. **Où est stocké le prix réellement appliqué** à chaque vente, lorsque `Transaction.mdb` indique `Prix = 0` ?
4. Y a-t-il **plusieurs caisses/terminaux dont les données sont dans des fichiers séparés** à consolider pour obtenir le total Z ?
5. Le rapport Z correspond-il aux données du **module d'enregistrement des ventes de Revenu Québec (MEV / WEB-SRM)**, et cette source est-elle exportable ?

**Questions complémentaires :**
6. Où sont stockés les **modes de paiement** par facture (argent, débit, Visa, Mastercard, Amex) ?
7. Où sont stockées les **taxes TPS/TVQ** (par facture ou par jour) ?
8. À quelle **heure se clôture la journée** Z (coupure de la journée comptable) ?
9. Comment **distinguer les ventes au poids** (viande, fruits/légumes, pâtisserie) dans l'export ?
10. Disposez-vous de la **documentation du schéma** des bases Access BEST POS ?

Notre objectif est de **reproduire exactement les chiffres du rapport Z** dans un tableau de bord externe, sans modifier BEST POS. Pourriez-vous nous indiquer la **meilleure source officielle** à utiliser, et nous mettre en relation avec une **personne technique** si nécessaire ? Nous sommes disponibles pour un **court appel** au besoin.

Merci d'avance,

Yahia Sghaier, CPA
ProtaxImpôt — Mandataire CPA d'Épilys
