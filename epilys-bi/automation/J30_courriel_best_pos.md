# Courriel à envoyer au fournisseur BEST POS

**Stratégie :** ne pas demander les bases Access (déjà en main). Demander **la source du rapport Z** et **l'export officiel**. Court et ciblé = meilleure réponse. Les 4 dernières questions sont l'« annexe » si tu veux pousser.

---

**Objet :** Source officielle du rapport financier Z — alimentation d'un tableau de bord externe

Bonjour,

Nous (ProtaxImpôt, mandataire CPA d'Épilys) mettons en place des tableaux de bord à partir des données BEST POS, **sans modifier BEST POS**.

Nous avons accès aux bases Access `Inventaire.mdb` et `Transaction.mdb`, mais nous constatons que **les montants du rapport financier Z ne peuvent pas être reconstruits à partir de `Transaction.mdb`** : plusieurs lignes de vente ont **Prix = 0** (les volumes sont là, mais pas les montants). Les montants CA, taxes et paiements du Z semblent donc venir d'une autre source ou d'un calcul interne.

Nos questions prioritaires :

1. **Existe-t-il un export officiel (quotidien ou mensuel) du rapport financier Z en CSV/Excel**, ou une procédure recommandée pour alimenter un système BI externe ?
2. **Quelle table/fichier BEST utilise pour générer le rapport Z** (CA, taxes, paiements, profit) — est-ce `Transaction.mdb`, une autre base, ou un calcul au moment du rapport ?
3. **Où est stocké le prix réellement appliqué** à chaque vente (puisque `Transaction.mdb` a Prix = 0 sur de nombreuses lignes) ?
4. **Y a-t-il plusieurs caisses/terminaux dont les données sont dans des fichiers `.mdb` séparés** (et faut-il tous les consolider pour obtenir le total Z) ?
5. **Le rapport Z correspond-il aux données du module d'enregistrement des ventes Revenu Québec (MEV / WEB-SRM)**, et cette source est-elle exportable ?

Si utile, questions complémentaires : à quelle **heure se clôture la journée** comptable du Z ? Comment **distinguer les ventes au poids** (viande, fruits-légumes) dans l'export ? Où sont stockés les **modes de paiement** et les **taxes TPS/TVQ** par facture ? Disposez-vous de la **documentation du schéma** des bases ?

Notre objectif est simplement de **reproduire les mêmes chiffres que le rapport Z** dans un tableau de bord externe. Merci de nous indiquer la **meilleure source officielle** à utiliser.

Cordialement,
Yahia Sghaier, CPA — ProtaxImpôt
Mandataire CPA d'Épilys
