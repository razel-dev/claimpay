# ClaimPay

ClaimPay est une application Web3 de paiement conditionnel par jalons. Elle permet à un client et à un prestataire de définir plusieurs étapes de réalisation, puis de déclencher progressivement les paiements après validation du travail effectué.

**Les fonds sont déposés dans ClaimPay dès la création de l’accord.** Le client autorise d’abord ClaimPay à dépenser le jeton de paiement (`approve` sur le contrat du jeton). Puis `createAgreement` prélève le total des jalons. Autoriser ne déplace pas de fonds ; créer l’accord les place sous séquestre.

Le prestataire soumet un jalon. Le client peut alors l’approuver pour payer le prestataire, ou le contester. En cas de contestation :

* **Avec tiers désigné** : seul ce tiers peut choisir entre paiement intégral du jalon au prestataire et remboursement intégral au client.
* **Sans tiers** : une partie propose l’une de ces issues, l’autre doit l’accepter. Sans accord, il n’y a ni transfert ni déblocage automatique.

L’accord devient `Completed` lorsque tous les jalons sont payés ou remboursés. Pour les paramètres, les erreurs, les événements et des exemples concrets, voir le [guide français du contrat](docs/SMART_CONTRACT.md).

## Technologies

### Smart contracts

* Solidity
* Foundry
* OpenZeppelin
* MockUSDC

### Frontend

Le dossier `frontend/` contient actuellement un squelette React/Vite. La cible du MVP est une interface **Angular et TypeScript** connectée au wallet et au contrat ; cette migration n’est pas encore livrée.

## Structure du projet

* `contracts/` : smart contracts, tests et scripts de déploiement
* `frontend/` : code de l’interface utilisateur
* `docs/` : documentation fonctionnelle et technique
* `deployments/` : informations relatives aux déploiements

## État du projet

ClaimPay est actuellement en cours de développement.

Le MVP sera d’abord testé localement, puis déployé sur le réseau de test Sepolia avec un frontend accessible publiquement.

## Avertissement

ClaimPay est un projet expérimental. Il n’est pas destiné à gérer des fonds réels dans sa version actuelle.
