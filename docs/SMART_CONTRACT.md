# ClaimPay — comprendre le contrat, méthode par méthode

**Version de travail du 27 novembre 2026.** Référence : `razel-dev/claimpay`, commit `538bf829c038c6bfdabde77db4e542abb3d4715f`. Cette documentation décrit le code de cette révision, pas une version de production. Elle ne constitue ni un audit de sécurité ni une attestation de déploiement. La [CI du correctif intégré](https://github.com/razel-dev/claimpay/actions/runs/45973141882) a exécuté 82 tests avec succès. Ce résultat ne mesure pas à lui seul la couverture et ne prouve pas l'absence de défaut. Les exemples sont des appels explicatifs, pas des transactions à envoyer sur un réseau réel.

Sources immuables : [ClaimPay.sol](https://github.com/razel-dev/claimpay/blob/538bf829c038c6bfdabde77db4e542abb3d4715f/contracts/src/ClaimPay.sol) · [MockUSDC.sol](https://github.com/razel-dev/claimpay/blob/538bf829c038c6bfdabde77db4e542abb3d4715f/contracts/src/mocks/MockUSDC.sol) · [Tests ClaimPay](https://github.com/razel-dev/claimpay/blob/538bf829c038c6bfdabde77db4e542abb3d4715f/contracts/test/ClaimPay.t.sol) · [Tests MockUSDC](https://github.com/razel-dev/claimpay/blob/538bf829c038c6bfdabde77db4e542abb3d4715f/contracts/test/MockUSDC.t.sol) · [Test d’isolation entre accords](https://github.com/razel-dev/claimpay/blob/538bf829c038c6bfdabde77db4e542abb3d4715f/contracts/test/ClaimPayIsolation.t.sol).

## Lire le modèle

Léa commande deux livraisons à Marc : une maquette de 400 mUSDC et une intégration de 600 mUSDC. Léa commence par autoriser le contrat à prélever 1 000 mUSDC sur le contrat du **jeton**. Elle crée ensuite l'accord sur **ClaimPay** : cette seconde transaction dépose les 1 000 mUSDC en une fois. Une soumission, une contestation ou une proposition ne fait sortir aucun jeton. Un jalon ne débloque son propre montant que lorsqu'une méthode autorisée exécute le paiement ou le remboursement.

| Notion | Représentation dans le contrat | Conséquence pratique |
|---|---|---|
| Accord | `Agreement` : client, prestataire, tiers éventuel (`arbiter`), statut, tableau de jalons | Identifiants à partir de 1 ; le client est l'adresse qui crée l'accord. |
| Jalon | `Milestone` : description, montant brut, statut | Indices à partir de 0 ; le jalon 1 est le deuxième. |
| Accord actif ou terminé | `Active = 0`, `Completed = 1` | « Terminé » signifie financièrement réglé ; tous les jalons ne sont pas nécessairement payés au prestataire. |
| État du jalon | `Pending = 0`, `Submitted = 1`, `Disputed = 2`, `Paid = 3`, `Refunded = 4` | `Paid` et `Refunded` sont terminaux. Les jalons n'ont pas à être traités dans l'ordre. |
| Issue | `PayProvider = 0`, `RefundClient = 1` | Le montant entier du jalon va à un seul bénéficiaire. Pas de partage partiel. |
| Proposition amiable | `SettlementProposal` : auteur et issue, stockés par couple (accord, jalon) | Un auteur nul signifie « aucune proposition ». |

Les descriptions sont publiques. Les coordonnées personnelles et les pièces confidentielles n'ont pas leur place dans ces chaînes. Un seul jeton est configuré pour toute l'instance. Le mock utilise six décimales : 400 mUSDC s'écrit `400_000_000`. ClaimPay manipule des entiers ; il ne lit ni le symbole ni le nombre de décimales du jeton. Son solde de jetons est commun aux accords : ce sont les entrées de stockage de chaque jalon qui déterminent ce que le contrat doit encore régler.

## Initialisation et dépôt

### 1. `constructor(address paymentTokenAddress)` — sélectionner le jeton

**Appel :** seulement lors de la création de l'instance, par son déployeur. Le constructeur refuse `address(0)` avec `InvalidPaymentToken()`, puis conserve l'adresse en tant que `IERC20 public immutable paymentToken`. Il ne crée pas d'accord, n'effectue pas de transfert, ne renvoie rien et n'émet pas d'événement ClaimPay.

**Limite :** il ne vérifie ni le code de l'adresse, ni les décimales, ni le comportement ERC-20. Il n'existe pas de fonction pour changer ce jeton ensuite. Exemple local : `new ClaimPay(address(mockUSDC))`. Tests : `testPaymentTokenIsConfigured`, `testRevertWhenPaymentTokenIsZero`.

### 2. `createAgreement(provider, arbiter, descriptions, amounts) → agreementId` — créer et financer

**Appel :** toute adresse peut devenir cliente en envoyant la transaction. `provider` est l'adresse du prestataire ; `arbiter` est un tiers technique, ou `address(0)` sans tiers. Les deux tableaux associent par indice une description et un montant en unités brutes. Le client doit avoir le solde et l'autorisation ERC-20 nécessaires. Le contrat n'attend ni transaction du prestataire ni acceptation du tiers pour créer l'accord.

**Dans cet ordre :**

1. Prestataire non nul et distinct du client **et de l’adresse de cette instance de ClaimPay** (`address(this)`), sinon `InvalidProvider()`.
2. Si un tiers est renseigné, il doit être distinct du client, du prestataire **et de cette instance de ClaimPay**, sinon `InvalidArbiter()`. `address(0)` reste le choix explicite « sans tiers ».
3. Au moins une description, sinon `EmptyMilestones()` ; tableaux de même longueur, sinon `MilestoneDataMismatch()`.
4. Pour chaque indice, description non vide en octets (`EmptyMilestoneDescription(i)`), puis montant non nul (`InvalidMilestoneAmount(i)`). Les montants sont additionnés ; un dépassement d'entier annule la transaction. Aucun contrôle des espaces, du contenu rédactionnel ni de la valeur économique.
5. `safeTransferFrom(client, ClaimPay, total)` prélève les fonds **avant** la création des entrées. Un échec de l'appel au jeton fait échouer la transaction ; pas d'accord créé à moitié. L'implémentation ne compare pas le solde reçu au montant annoncé : utiliser pour la démonstration le jeton exact prévu, pas un jeton à frais.
6. Incrémente `agreementCount`, attribue cet identifiant, écrit les trois rôles et le statut `Active`, puis ajoute chaque jalon `Pending` avec son propre montant.
7. Émet `AgreementCreated(id, client, provider, arbiter, nombre)` et renvoie `id`. Le journal ERC-20 du transfert appartient au jeton, pas à ClaimPay.

**Pourquoi ces deux exclusions ?** Le prestataire doit pouvoir soumettre personnellement un jalon ; le tiers désigné doit pouvoir appeler `resolveDispute`. Cette instance de ClaimPay ne dispose d’aucune méthode pour agir en son propre nom dans ces rôles. Confondre son adresse avec celle d’un participant pourrait immobiliser les fonds. Ces contrôles interviennent avant le prélèvement : en cas de refus, les soldes, l’autorisation ERC-20 et le compteur d’accords restent inchangés. Cela n’interdit pas tous les portefeuilles de type contrat. Tests : `testRevertWhenProviderIsClaimPay`, `testRevertWhenArbiterIsClaimPay`.

**Exemple :** `createAgreement(marc, address(0), ["Maquette", "Integration"], [400_000_000, 600_000_000])`. Depuis Angular, après confirmation de la transaction, lire l'identifiant dans `AgreementCreated` ; le hash de transaction n'est pas l'identifiant d'accord. Aucun plafond explicite de jalons ; les deux boucles et les écritures consomment du gaz. Tests : `testCreateAgreementTransfersTotalMilestoneAmount`, `testRevertWhenAllowanceIsInsufficient`, `testRevertWhenBalanceIsInsufficient`.

## Exécution normale

### 3. `submitMilestone(agreementId, milestoneIndex)` — déclarer la livraison

**Appel :** uniquement le prestataire de cet accord. Le contrat vérifie : existence de l'accord (`AgreementNotFound`), identité (`NotAgreementProvider`), indice (`MilestoneNotFound`), puis statut `Pending` (`InvalidMilestoneStatus` avec le statut réel). Il remplace `Pending` par `Submitted` et émet `MilestoneSubmitted(id, index, msg.sender)`. Aucun retour, aucun transfert, aucun changement du statut de l'accord.

**Exemple :** Marc envoie `submitMilestone(id, 0)`. Ce signal ne stocke ni pièce jointe ni preuve de qualité ; il permet maintenant à Léa d'approuver ou contester. Un second appel sur ce jalon ne recommence pas le cycle. Tests : `testProviderCanSubmitMilestone`, `testRevertWhenSubmittingMilestoneTwice`.

### 4. `approveMilestone(agreementId, milestoneIndex)` — payer une livraison non contestée

**Appel :** uniquement le client. Vérifications : accord existant (`AgreementNotFound`), appelant client (`NotAgreementClient`), indice valide (`MilestoneNotFound`), jalon `Submitted` (`InvalidMilestoneStatus`). Passe le jalon à `Paid`, parcourt les jalons de l'accord et, si tous sont réglés, écrit `Completed`. Ensuite seulement, transfère la totalité du montant au prestataire avec `safeTransfer`.

**Résultat :** sans valeur de retour ; `MilestonePaid(id, index, provider, montant)`, puis `AgreementCompleted(id)` si c'était le dernier jalon non réglé. Si le transfert échoue, les changements d'état de cet appel ne persistent pas. Exemple : Léa appelle `approveMilestone(id, 0)` ; Marc reçoit 400 mUSDC et l'accord reste actif si le deuxième jalon est encore ouvert. Ce chemin ne règle pas un jalon déjà contesté. Tests : `testClientCanApproveSubmittedMilestone`, `testAgreementCompletesOnlyAfterAllMilestonesArePaid`, `testEmitMilestonePaidAndAgreementCompleted`.

## Contestation : ouvrir, puis choisir la voie de règlement

### 5. `disputeMilestone(agreementId, milestoneIndex)` — ouvrir la contestation

**Appel :** client uniquement. Vérifie dans l'ordre : accord (`AgreementNotFound`), client (`NotAgreementClient`), indice (`MilestoneNotFound`), statut `Submitted` (`InvalidMilestoneStatus`). Écrit uniquement `Disputed` sur ce jalon et émet `MilestoneDisputed(id, index, client)`. Aucun retour ni mouvement de fonds ; les autres jalons restent utilisables.

**Exemple :** après soumission du jalon 1, Léa envoie `disputeMilestone(id, 1)`. L'appel fonctionne avec ou sans tiers. Il ne demande ni motif ni preuve et ne décide pas du bénéficiaire. Test : `testClientCanDisputeSubmittedMilestoneWithoutArbiter`.

### 6. `resolveDispute(agreementId, milestoneIndex, resolution)` — exécuter la décision du tiers désigné

**Appel :** uniquement l'adresse `arbiter` fixée à la création. Vérifie : existence de l'accord (`AgreementNotFound`), présence d'un tiers (`NoDisputeResolverConfigured`), identité du tiers (`NotAgreementResolver`), indice (`MilestoneNotFound`), puis statut `Disputed` (`InvalidMilestoneStatus`). Le tiers choisit entre `PayProvider` et `RefundClient` ; il ne fournit pas une adresse de paiement libre.

**Résultat :** délègue à `_settleMilestone` le statut, le transfert entier et son événement. Émet ensuite `DisputeResolved(id, index, tiers, issue)` et, si tous les jalons sont réglés, `AgreementCompleted(id)`. Pas de retour ni de deuxième signature. Sans tiers, cette méthode ne fonctionne pas, même si le client l'appelle. Exemple sur un accord ayant Sophie pour tiers : `resolveDispute(id, 1, RefundClient)` rembourse les 600 mUSDC à Léa. Tests : `testResolverCanRefundClientAfterDispute`, `testResolverCanPayProviderAfterDispute`, `testEmitRefundAndDisputeResolutionEvents`.

### 7. `proposeSettlement(agreementId, milestoneIndex, resolution)` — proposer sans transférer

**Appel :** client **ou** prestataire, seulement pour un accord sans tiers. Vérifie : accord (`AgreementNotFound`), appartenance à l'accord (`NotAgreementParty`), absence de tiers (`DisputeResolverAlreadyConfigured`), indice (`MilestoneNotFound`), statut `Disputed` (`InvalidMilestoneStatus`).

**Écriture :** enregistre `(msg.sender, resolution)` à la clé `(id, index)`. Toute nouvelle offre autorisée écrase la précédente, y compris si l'auteur change. Émet `SettlementProposed(id, index, auteur, issue)`. Aucun retour, paiement, remboursement ni changement de statut. Exemple : Léa propose `RefundClient` ; Marc peut proposer `PayProvider` à son tour. Cette contre-proposition ne paie pas Marc. Tests : `testSettlementProposalCanBeReplaced`, `testEmitSettlementProposed`.

### 8. `acceptSettlement(agreementId, milestoneIndex, expectedResolution)` — accepter l'issue et déplacer les fonds

**Appel :** l'autre partie à l'accord ; le tiers, une adresse extérieure et l'auteur de l'offre n'ont pas ce rôle. Les cinq premiers contrôles sont, dans l'ordre, les mêmes que pour `proposeSettlement` : accord, partie, absence de tiers, indice et état `Disputed`. Trois contrôles supplémentaires suivent :

1. Une offre existe, sinon `SettlementProposalNotFound(id, index)`.
2. Son auteur diffère de l'appelant, sinon `SettlementProposerCannotAccept(id, index)`.
3. L'issue envoyée est celle stockée, sinon `SettlementProposalMismatch(id, index, attendue, proposée)`. Ce contrôle compare l'issue, pas un numéro de version ou un hash d'offre.

**Effets :** copie l'issue, supprime la proposition, puis appelle `_settleMilestone`. Les journaux ClaimPay sont, dans l'ordre : `MilestonePaid` ou `MilestoneRefunded`, `SettlementAccepted(id, index, accepteur, issue)`, puis éventuellement `AgreementCompleted`. Ce chemin **n'émet pas** `DisputeResolved`, propre au tiers. Pas de retour. En cas d'échec, y compris du transfert, aucune de ces modifications n'est validée ; la proposition n'est pas perdue.

**Exemple :** après l'offre de remboursement de Léa, Marc envoie `acceptSettlement(id, 1, RefundClient)`. Léa reçoit 600 mUSDC et le jalon devient `Refunded`. Si le jalon 0 est déjà `Paid`, l'accord devient `Completed`. Pour Angular, montrer avant la signature *qui* reçoit *combien* et transmettre l'issue affichée. Tests : `testClientCanProposeRefundAndProviderCanAccept`, `testRevertWhenAcceptedResolutionDoesNotMatchProposal`, `testRevertWhenAcceptingSettlementTwice`.

## Lecture : afficher ce qui est effectivement inscrit

Ces lectures sont publiques. Un appel RPC de lecture ne soumet pas de transaction, ne modifie pas le stockage, ne transfère pas de jetons et n'émet pas d'événements.

### 9. `getAgreement(agreementId)`

Vérifie `agreementId != 0` et `agreementId <= agreementCount` ; sinon `AgreementNotFound(id)`. Renvoie dans l'ordre `(client, provider, arbiter, status, milestoneCount)`. Utiliser ce nombre pour consulter les indices de 0 à `milestoneCount - 1`. Le résultat n'inclut ni tableau complet ni total financier. **Exemple :** `getAgreement(1)` permet de savoir si l'accord existe, si le tiers est absent et s'il reste actif. Tests : `testCreateAgreement`, `testRevertWhenAgreementDoesNotExist`.

### 10. `getMilestone(agreementId, milestoneIndex)`

Valide d'abord la plage de l'identifiant d'accord (`AgreementNotFound`), puis l'indice strictement inférieur au nombre de jalons (`MilestoneNotFound`). Renvoie `(description, amount, status)` sans conversion monétaire. **Exemple :** pour afficher « Maquette, 400 mUSDC, payée », lire ce tuple, convertir `400_000_000` sur six décimales et afficher le libellé de `Paid`. Test : `testRevertWhenGettingMilestoneFromUnknownAgreement`.

### 11. `getSettlementProposal(agreementId, milestoneIndex)`

Vérifie accord puis indice comme `getMilestone`, avec les mêmes erreurs. Il n'exige ni état `Disputed` ni absence de tiers. Renvoie `(exists, proposer, resolution)` en déduisant `exists` de l'auteur non nul. **Exemple :** après acceptation, la lecture renvoie `(false, address(0), PayProvider)` : l'issue par défaut vaut zéro mais **ne constitue pas une offre de paiement**. L'interface ne doit afficher une offre que si `exists == true`. Tests : `testRevertWhenGettingSettlementProposalFromUnknownMilestone`, `testClientCanProposeRefundAndProviderCanAccept`.

### 12. `paymentToken()` — getter généré par Solidity

Sans paramètre, renvoie publiquement l'adresse ERC-20 immuable choisie au déploiement (type Solidity `IERC20`, encodée comme une adresse). Aucune erreur métier. **Exemple :** le front s'appuie sur cette adresse pour lire le solde et l'autorisation du client sur le bon jeton. Test : `testPaymentTokenIsConfigured`.

### 13. `agreementCount()` — getter généré par Solidity

Sans paramètre, renvoie le compteur des accords créés : zéro initialement, puis un de plus par création réussie. Aucune erreur métier. **Exemple :** une valeur de 2 signifie que les identifiants 1 et 2 existent dans cette révision, pas que ces accords appartiennent au compte connecté ou qu'ils sont tous deux actifs. Test : `testInitialAgreementCountIsZero`.

## Fonctions privées : pourquoi le contrat en a besoin

### 14. `_settleMilestone(agreementId, milestoneIndex, agreement, milestone, resolution) → bool`

Méthode privée d'exécution **après contestation**, partagée par `resolveDispute` et `acceptSettlement`. Les deux identifiants alimentent les événements et les deux références `storage` désignent l'accord et le jalon effectivement modifiés. Elle ne vérifie pas elle-même l'identité, l'existence ni le statut initial : ses appelants doivent l'avoir fait. Elle ne fait pas partie de l'ABI publique.

Dans l'ordre : choisit le destinataire et écrit `Paid` (prestataire) ou `Refunded` (client) ; calcule si l'accord est réglé via `_allMilestonesSettled` ; écrit `Completed` si nécessaire ; exécute `safeTransfer(destinataire, montantDuJalon)` ; émet l'événement financier correspondant ; renvoie le booléen de clôture. Un échec du jeton interrompt l'ensemble. L'appelant émet l'événement de décision puis éventuellement `AgreementCompleted`. **Exemple :** même remboursement de 600 mUSDC par tiers ou par consentement mutuel, mais événement de décision distinct. `approveMilestone` réalise son propre paiement direct ; il n'appelle pas ce helper. Tests indirects : `testResolverCanPayProviderAfterDispute`, `testClientCanProposeRefundAndProviderCanAccept`.

### 15. `_allMilestonesSettled(agreement) → bool`

Lecture privée d'une référence d'accord : inspecte les statuts des jalons et renvoie `false` au premier qui n'est ni `Paid` ni `Refunded`. Sinon renvoie `true`. Aucun transfert, événement, changement d'état ni erreur métier propre. Une liste vide aboutirait à `true`, mais `createAgreement` interdit de créer une telle liste. Dans le pire cas, une lecture de statut par jalon : le coût de règlement dépend du nombre de jalons. **Exemple :** `[Paid, Disputed]` vaut faux ; `[Paid, Refunded]` vaut vrai. Tests indirects : `testAgreementCompletesAfterPaidAndRefundedMilestones`, `testAgreementCompletesAfterDirectPaymentAndMutualRefund`.

## Jeton de démonstration : MockUSDC

Ce contrat de test hérite d'`ERC20` d'OpenZeppelin. Il ne représente pas l'USDC réel. Les trois déclarations propres au projet sont les suivantes :

| Méthode | Objectif, accès et effet | Exemple / vérification |
|---|---|---|
| `constructor()` | Sans paramètre, appelle le constructeur ERC-20 avec « Mock USD Coin » et « mUSDC ». N'appelle pas `_mint` ; aucune allocation initiale dans le code du projet. | Déployer localement puis lire `name()` et `symbol()`. Voir `testTokenMetadata`. |
| `decimals() → uint8` | Lecture pure publique sans argument. Renvoie toujours 6, sans appel externe, mouvement ni événement. N'arrondit aucun montant. | Une unité affichée de mUSDC représente 1 000 000 unités brutes ; voir `testTokenMetadata`. |
| `mint(to, amount)` | Fonction externe ouverte à **tout appelant**, sans rôle administrateur ni plafond ajouté. Délègue à `_mint` hérité : création d'unités, augmentation du solde du destinataire et de l'offre ; événement ERC-20 `Transfer(address(0), to, amount)`. Un destinataire nul n'est pas valide pour l'ERC-20 utilisé. Pas de valeur de retour. | Pour financer Léa en test : `mint(lea, 1_000_000_000)` représente 1 000 mUSDC. Voir `testMint`. Ne pas présenter ce jeton comme ayant une valeur économique garantie. |

Lectures et écritures publiques héritées utiles à la démo (elles s'appellent sur **MockUSDC**, pas sur ClaimPay) :

| Méthode ERC-20 | Interprétation |
|---|---|
| `name()`, `symbol()` | Libellé et symbole fournis au constructeur ; ces métadonnées ne prouvent pas l'identité d'un jeton. |
| `totalSupply()` | Quantité totale créée, en unités brutes ; différente du solde sous séquestre. |
| `balanceOf(account)` | Solde brut de l'adresse. Lire le solde de ClaimPay ne donne pas le solde d'un accord individuel. |
| `allowance(owner, spender)` | Montant que `spender` est autorisé à prélever à `owner`. Une autorisation seule ne finance pas l'accord. |
| `approve(spender, amount)` | L'appelant autorise par exemple ClaimPay à prélever la somme des jalons. Émet `Approval` ; ne paie pas Marc et ne valide pas un jalon. |
| `transfer(to, amount)` | Déplace des jetons du solde de l'appelant au destinataire. Un envoi manuel à ClaimPay ne crée ni accord ni jalon. |
| `transferFrom(from, to, amount)` | Déplace les jetons dans la limite de l'autorisation ; c'est l'opération employée au financement, via SafeERC20. Solde ou autorisation insuffisants peuvent faire échouer l'appel. |

## Comment vérifie-t-on que deux accords restent indépendants ?

`testFuzzSettlementIsolatedAcrossAgreements` fait varier les deux montants déposés par le même client. Les accords ont des prestataires distincts, mais utilisent tous deux le jalon d’indice `0`. Après paiement du premier prestataire, le premier accord est terminé ; le second reste actif et contesté, sa proposition de remboursement existe toujours et le contrat conserve exactement son montant dans ce scénario. Après acceptation du remboursement, seul le client reçoit ce montant. La CI citée en tête a exécuté ce scénario sur 256 paires de montants ; il ne s’agit pas d’une preuve pour toutes les séquences possibles.

## Trois choses à pouvoir expliquer à l'oral

1. **Qui décide ?** Avec tiers, l'adresse choisie tranche entre deux issues. Sans tiers, une partie propose et l'autre accepte. ClaimPay ne juge pas la prestation, ne consulte pas de tribunal et ne prévoit pas de déblocage par délai. Si l'acteur requis n'agit pas, le jalon peut rester bloqué.
2. **Quand l'argent change-t-il de mains ?** À la création, le total passe du client au contrat. À l'approbation ou à l'exécution d'une résolution, seul le montant du jalon sort. Une proposition ou une contestation, même confirmée, n'est pas un paiement.
3. **Qu'observe Angular ?** Avant l'écriture : rôle, réseau, adresse du jeton et état du jalon. Après confirmation : journaux émis par la bonne adresse puis relecture des états et soldes. Les journalisations ERC-20 proviennent du jeton ; les événements du cycle métier proviennent de ClaimPay.

### À vérifier avant de figer cette documentation

Vérifier l'ABI générée contre ces signatures et ordres de retour, rejouer les tests, mesurer le coût avec plusieurs jalons et comparer les reçus d'une démo aux événements décrits. Les noms, limites de gaz, adresses et réseaux doivent être révisés si le contrat change. Aucun secret, portefeuille réel ni adresse de déploiement non vérifiée ne doit être ajouté à ce guide.
