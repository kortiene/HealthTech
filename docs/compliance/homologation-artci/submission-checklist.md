# Checklist de complétude avant dépôt ARTCI (gate humain)

> **Point d'entrée :** [`README.md`](./README.md). Alignée sur le **critère de soumission** du
> [tableau de readiness](./readiness-dashboard.md) §3. Ordonnée **par bloqueur**.
>
> ⚠️ **Ne cocher une case qu'après vérification factuelle contre l'artefact source.** Tant que la checklist
> n'est pas **entièrement** cochée, **ne pas déposer** : le dossier reste un projet.

## Bloqueurs (doivent tous être levés)

- [ ] **B1 — Sign-off juridique complet.** Les 22 exigences `Must` sont **`Validé`** sans réserve bloquante
      au [journal de validation juridique](../journal-validation-juridique.md). *Aujourd'hui : 0/22.*
- [ ] **B2 — Attestation de localisation signée.** L'opérateur souverain (#8) est contracté, le bring-up
      in-country réalisé, et l'[attestation](../attestation-localisation-donnees.md) (`PREUVE-05`) est
      **signée**. *Aujourd'hui : modèle prêt, non signé.*
- [ ] **B3 — Rapport de pentest livré + corrigé.** Le rapport (`PREUVE-14`, #25) est livré ; toutes les
      vulnérabilités **`Critical`/`High` corrigées et re-testées**. *Aujourd'hui : non produit.*
- [ ] **B4 — Nature de la formalité tranchée** ([ECART-05](../ecarts.md)) et **format de dépôt** ARTCI
      confirmé (voir [`formalite-prealable.md`](./formalite-prealable.md)).

## Écarts obligatoires résolus

- [ ] **ECART-01** — Politique de rétention documentée (PIECE-13 / `PREUVE-25`).
- [ ] **ECART-02** — Flux d'effacement + crypto-effacement validé (PIECE-14 / `PREUVE-21`).
- [ ] **ECART-03** — Runbook incident + notification de violation (PIECE-15 / `PREUVE-24`).
- [ ] **ECART-04** — Désignation DPO / correspondant (PIECE-16 / `PREUVE-26`).
- [ ] **ECART-06 / ECART-07** — Rôles RT/sous-traitant et base légale de la localisation clarifiés
      (impactent PIECE-01, PIECE-07, PIECE-09).

## Pièces « À produire » livrées

- [ ] **PIECE-05** — Avis de revue crypto indépendante (#26).
- [ ] **PIECE-09** — Contrat / clauses hébergeur (DPA, #8).
- [ ] **PIECE-10 / PIECE-11** — Consentement + textes d'information **validés juridiquement** (#7) — passent
      de *draft* à validé.
- [ ] **PIECE-12** — Preuve d'horodatage du consentement (#13).
- [ ] **PIECE-17** — Test « le serveur ne peut pas déchiffrer » livré (#9).

## Cohérence & honnêteté du dossier

- [ ] Le [gate de complétude/cohérence](../../../scripts/check-homologation-dossier.sh) passe sans erreur.
- [ ] **Aucune** pièce marquée « Prête » ne s'adosse à une preuve non `Existant`.
- [ ] Tous les liens relatifs du dossier résolvent.
- [ ] **Aucune** donnée patient / clé / PII n'a été introduite dans une pièce du dossier.
- [ ] **Aucune** mention n'affirme que l'homologation est **obtenue** avant réception de l'acte ARTCI
      (`PREUVE-13`).

## Dépôt (humain — hors périmètre agent)

- [ ] Dossier **déposé** auprès de l'ARTCI dans le format exigé.
- [ ] **Récépissé / décision** (`PREUVE-13`) reçu et **consigné** (voir [`formalite-prealable.md`](./formalite-prealable.md) §4).

> **Homologation obtenue à 100 %** (KPI du PRD §1/§5) = **uniquement** lorsque l'acte favorable de l'ARTCI
> est reçu et consigné. L'existence des pièces ci-dessus en est un **prérequis**, pas une garantie.
