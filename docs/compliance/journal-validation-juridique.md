# Journal de validation juridique

> **Sign-off** du conseil juridique, **exigence par exigence**. C'est l'artefact qui matérialise le
> **critère d'acceptation** de [#5](https://github.com/kortiene/HealthTech/issues/5) :
> **« matrice de conformité validée par le conseil juridique »**.
>
> **Condition de « matrice validée » :** **toutes** les exigences `Must` de
> [`exigences-legales.md`](./exigences-legales.md) sont **signées sans réserve bloquante**.

## Mode d'emploi

Pour chaque exigence, le réviseur juridique consigne : **verdict** (`Validé` / `Validé avec réserves` /
`Refusé` / `En attente`), **date**, **réviseur**, et **commentaires/réserves**. Une réserve **bloquante**
empêche le statut « validée » de la matrice ; une réserve **non bloquante** est suivie comme amélioration.

> **État au démarrage :** **aucun sign-off n'a encore eu lieu.** Toutes les exigences sont **En attente**.
> Ce journal sera renseigné lors de la revue par le conseil juridique. Les champs date/réviseur portent
> `[à compléter]`.

## Journal des verdicts

| REQ | M/S | Verdict | Date | Réviseur | Commentaires / réserves |
| --- | --- | --- | --- | --- | --- |
| REQ-LEX-01 | Must | En attente | `[à compléter]` | `[à compléter]` | Confirmer la formalité préalable applicable. |
| REQ-LEX-02 | Must | En attente | `[à compléter]` | `[à compléter]` | **Régime données de santé** (autorisation vs déclaration) à trancher — [ECART-05](./ecarts.md). |
| REQ-LEX-03 | Must | En attente | `[à compléter]` | `[à compléter]` | Base légale = consentement à confirmer. |
| REQ-LEX-04 | Must | En attente | `[à compléter]` | `[à compléter]` | Valider les exigences de contenu du consentement ([#7](https://github.com/kortiene/HealthTech/issues/7)). |
| REQ-LEX-05 | Should | En attente | `[à compléter]` | `[à compléter]` | Régime mineurs / personnes protégées — [ECART-05](./ecarts.md). |
| REQ-LEX-06 | Must | En attente | `[à compléter]` | `[à compléter]` | Finalité à valider sur le registre des traitements. |
| REQ-LEX-07 | Must | En attente | `[à compléter]` | `[à compléter]` | Minimisation appuyée par le zero-knowledge. |
| REQ-LEX-08 | Must | En attente | `[à compléter]` | `[à compléter]` | — |
| REQ-LEX-09 | Must | En attente | `[à compléter]` | `[à compléter]` | — |
| REQ-LEX-10 | Must | En attente | `[à compléter]` | `[à compléter]` | **Rétention** à arbitrer — [ECART-01](./ecarts.md). |
| REQ-LEX-11 | Must | En attente | `[à compléter]` | `[à compléter]` | Contenu de l'information à valider ([#7](https://github.com/kortiene/HealthTech/issues/7)). |
| REQ-LEX-12 | Must | En attente | `[à compléter]` | `[à compléter]` | Droit d'accès couvert par le local-first. |
| REQ-LEX-13 | Must | En attente | `[à compléter]` | `[à compléter]` | — |
| REQ-LEX-14 | Must | En attente | `[à compléter]` | `[à compléter]` | Mécanisme d'opposition à concevoir — [ECART-02](./ecarts.md). |
| REQ-LEX-15 | Must | En attente | `[à compléter]` | `[à compléter]` | **Crypto-effacement** à valider juridiquement — [ECART-02](./ecarts.md). |
| REQ-LEX-16 | Must | En attente | `[à compléter]` | `[à compléter]` | Mesures de sécurité (crypto, ZK) — preuves planifiées. |
| REQ-LEX-17 | Must | En attente | `[à compléter]` | `[à compléter]` | Secret médical — réserve RAM-only navigateur à noter. |
| REQ-LEX-18 | Must | En attente | `[à compléter]` | `[à compléter]` | Accès contrôlé par le patient (QR éphémère). |
| REQ-LEX-19 | Must | En attente | `[à compléter]` | `[à compléter]` | **Base légale de la localisation** à préciser — [ECART-07](./ecarts.md). |
| REQ-LEX-20 | Must | En attente | `[à compléter]` | `[à compléter]` | Transferts transfrontaliers — [ECART-07](./ecarts.md). |
| REQ-LEX-21 | Must | En attente | `[à compléter]` | `[à compléter]` | Registre des traitements produit (projet). |
| REQ-LEX-22 | Should | En attente | `[à compléter]` | `[à compléter]` | Désignation DPO — [ECART-04](./ecarts.md). |
| REQ-LEX-23 | Must | En attente | `[à compléter]` | `[à compléter]` | Notification de violation — [ECART-03](./ecarts.md). |
| REQ-LEX-24 | Must | En attente | `[à compléter]` | `[à compléter]` | Clauses hébergeur ([#8](https://github.com/kortiene/HealthTech/issues/8)). |
| REQ-LEX-25 | Must | En attente | `[à compléter]` | `[à compléter]` | Journalisation sans PII/clés. |

## Synthèse de validation

| Indicateur | Valeur |
| --- | --- |
| Exigences `Must` totales | 22 (+ REQ-LEX-23 `Must [à confirmer]`) |
| Exigences `Must` validées sans réserve bloquante | **0** |
| **Matrice validée ?** | **Non** — critère d'acceptation de #5 **non atteint** |

> Le statut « **Matrice validée** » ne sera affiché que lorsque la ligne « validées sans réserve bloquante »
> couvrira **toutes** les exigences `Must`. Tant que ce n'est pas le cas, la matrice reste un **projet**.
