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

### ABI de ClaimPay pour le front

L’[ABI versionnée](frontend/src/contracts/abi/ClaimPay.json) décrit les appels, événements et erreurs que le front peut encoder ou décoder. Elle provient de la clé `abi` de l’artefact compilé `contracts/out/ClaimPay.sol/ClaimPay.json`. Elle ne contient ni bytecode, ni adresse de déploiement, ni identifiant de réseau. L’adresse du contrat et le réseau devront être configurés séparément.

Depuis la racine du dépôt, avec Foundry, les sous-modules Solidity initialisés, Bash et `jq` :

```bash
bash scripts/claimpay-abi.sh --check  # recompile et compare sans modifier le fichier du front
bash scripts/claimpay-abi.sh --write  # régénère le JSON après une modification volontaire
```

Ne pas éditer ce JSON à la main. Si l’interface change, relire le diff du JSON, adapter les appels concernés et soumettre le tout dans la même PR. La CI exécute `--check` et refuse un fichier absent ou différent. Elle ne garantit pas que le comportement métier ou l’ordre des valeurs d’un enum n’a pas changé : ces points relèvent des tests Solidity.

Pour le futur front Angular, importer ce JSON comme donnée statique. Deux points propres à ClaimPay :

* `approve` pour autoriser le dépôt appartient au **contrat du jeton ERC-20** ; `approveMilestone` pour payer un jalon appartient à **ClaimPay**. Le front appellera deux adresses distinctes.
* Pour une proposition amiable, lire `exists` dans `getSettlementProposal` : `PayProvider` vaut `0` et reste une issue valide. Transmettre l’issue affichée à `acceptSettlement`, sans la remplacer par une valeur par défaut.

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
