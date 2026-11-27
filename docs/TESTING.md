# Vérification des parcours financiers de ClaimPay

## Mesure de référence

Contrat mesuré : [`src/ClaimPay.sol` à la révision `f81e1af`](https://github.com/razel-dev/claimpay/blob/f81e1afd04b32cb35c274ea9cf2a4931cef4a1d6/contracts/src/ClaimPay.sol). Le 27 novembre 2026, [la CI de référence](https://github.com/razel-dev/claimpay/actions/runs/45974282099/job/140422026336) a exécuté 82 tests sans échec ni test ignoré avant instrumentation, puis avec instrumentation. Le rapport LCOV du contrat contient :

| Indicateur | Touchés / mesurés |
|---|---:|
| Lignes exécutables | 178 / 178 |
| Branches instrumentées | 52 / 52 |
| Fonctions instrumentées | 13 / 13 |

Ces dénominateurs excluent les tests, les mocks et les bibliothèques tierces. Les 13 fonctions comptabilisées incluent le constructeur et les deux fonctions privées ; Foundry ne fait pas apparaître ici les deux getters générés pour les variables publiques. Une ligne source, une sous-condition logique, une combinaison de rôles et une branche LCOV ne sont pas des notions interchangeables.

## Ce qui a réellement été exercé

| Parcours | Ce que les assertions contrôlent |
|---|---|
| Création et dépôt | Le total des jalons est transféré au contrat. Une autorisation ou un solde insuffisant entraîne un refus. Désigner ClaimPay comme prestataire ou comme tiers est refusé avant le dépôt. |
| Paiement direct | Seul le client peut approuver un jalon soumis. Le paiement va au prestataire ; une seconde approbation est rejetée. |
| Règlement par un tiers | Seul le tiers configuré peut régler un jalon contesté ; le bénéficiaire est déterminé par l’issue : paiement ou remboursement. |
| Accord amiable sans tiers | Il faut une proposition et l’acceptation de la même issue par l’autre partie. Le test contrôle les soldes, l’état terminal et la disparition de la proposition. |
| Deux accords simultanés | Le [test à montants variables](https://github.com/razel-dev/claimpay/blob/f81e1afd04b32cb35c274ea9cf2a4931cef4a1d6/contracts/test/ClaimPayIsolation.t.sol) a exécuté 256 paires de montants. Régler le premier accord ne clôt pas le second, ne supprime pas sa proposition et laisse son montant sous séquestre. |

Une couverture de 100 % sur ces trois indicateurs ne garantit ni l’absence de défaut ni l’exercice de toutes les suites d’actions possibles. En particulier, passer sur la ligne d’un transfert lors d’un paiement réussi ne vérifie pas ce qui se passe si le jeton refuse de payer. Les tests d’atomicité doivent contrôler les **soldes, statuts et propositions après le refus**, pas seulement la présence d’une erreur.

## Trois tests complémentaires : refus temporaire d’un transfert sortant

Le fichier [ClaimPayTransferFailure.t.sol](../contracts/test/ClaimPayTransferFailure.t.sol) utilise une variante locale du mock dont les transferts sortants peuvent être temporairement refusés. Le dépôt initial a réellement lieu avant le refus. Le contrat ClaimPay testé n’est pas modifié.

| Test | Effet attendu après le refus du jeton |
|---|---|
| `testDirectPaymentPreservesStateWhenTransferFails` | Le jalon reste soumis, l’accord actif et les fonds sous séquestre ; le prestataire n’est pas payé. |
| `testArbiterSettlementPreservesStateWhenTransferFails` | La décision de paiement du tiers ne clôt pas l’accord ; le jalon reste contesté et les soldes ne bougent pas. |
| `testMutualRefundPreservesProposalOnFailureAndCanBeRetried` | Le jalon reste contesté. L’offre initiale reste disponible, avec le même auteur et la même issue. Une fois le transfert rétabli, le prestataire peut accepter cette même offre : le client est remboursé, l’accord est terminé et l’offre est effacée. |

Ces trois tests s’ajoutent aux 82 de la mesure de référence. Ils concernent un jeton qui signale explicitement un échec, pas toutes les variantes possibles de jetons ERC-20.

## Reproduire la mesure

Depuis la racine d’une copie du dépôt avec Foundry et les dépendances du projet disponibles :

```bash
cd contracts
forge test -vvv
FOUNDRY_FUZZ_SEED=0x434c41494d504159 forge coverage --report lcov --report-file /tmp/claimpay-coverage.lcov
```

Le workflow filtre l’enregistrement LCOV de `src/ClaimPay.sol` : le résumé « Couverture du contrat ClaimPay » donne les totaux et le journal du job **Contracts** conserve le détail par ligne. Le test à montants variables compte comme un test dans le bilan, pas comme 256 tests distincts. Ne pas comparer les coûts de gaz d’une exécution instrumentée à ceux d’une compilation de déploiement.
