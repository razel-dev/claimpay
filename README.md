# ClaimPay

ClaimPay est une application Web3 de paiement conditionnel par jalons. Elle permet à un client et à un prestataire de définir plusieurs étapes de réalisation, puis de déclencher progressivement les paiements après validation du travail effectué.

ClaimPay n’est pas un système d’escrow : les fonds restent dans le wallet du client. Le client autorise le smart contract à transférer un montant défini grâce au mécanisme ERC-20 `approve` et `transferFrom`.

## Technologies

### Smart contracts

* Solidity
* Foundry
* OpenZeppelin
* MockUSDC

### Frontend

* React
* TypeScript
* Vite
* Wagmi
* Viem

## Structure du projet

* `contracts/` : smart contracts, tests et scripts de déploiement
* `frontend/` : interface utilisateur React
* `docs/` : documentation fonctionnelle et technique
* `deployments/` : informations relatives aux déploiements

## État du projet

ClaimPay est actuellement en cours de développement.

Le MVP sera d’abord testé localement, puis déployé sur le réseau de test Sepolia avec un frontend accessible publiquement.

## Avertissement

ClaimPay est un projet expérimental. Il n’est pas destiné à gérer des fonds réels dans sa version actuelle.
