# Registre des écarts de conformité

> Toute exigence `Must` **sans contrôle**, **sans preuve**, ou **sans issue porteuse** est tracée ici
> (`ECART-NN`) → vers une **issue existante** ou une **issue à créer**. Référencé depuis
> [`loi-2013-450-artci-matrix.md`](./loi-2013-450-artci-matrix.md).
>
> **Règle d'or :** un écart se résout en **créant une issue** et en concevant le contrôle proprement —
> **jamais** en affaiblissant la cryptographie ni le modèle zero-knowledge pour « cocher la case ».

## Légende

- **Type :** *Conception* (contrôle technique à concevoir) · *Gouvernance* (décision RT/DPO/rétention) ·
  *Juridique* (interprétation à confirmer).
- **Issue :** `existante #NN` ou **`à créer`** (proposition de titre fournie).

---

| ID | Exigence(s) | Écart constaté | Type | Issue porteuse | Action proposée |
| --- | --- | --- | --- | --- | --- |
| **ECART-01** | REQ-LEX-10 | **Pas de politique de rétention** : durées de conservation non définies ; tension droit à l'oubli ↔ rétention médicale **minimale** non arbitrée. | Gouvernance / Juridique | **à créer** | Issue *« Politique de rétention & purge des données (santé) »* : fixer durées par catégorie, mécanisme de purge, arbitrage avec les durées médicales légales. |
| **ECART-02** | REQ-LEX-15, REQ-LEX-14 | **Flux de suppression / effacement non conçu** ; acceptabilité juridique du **crypto-effacement** (destruction de clé) comme « effacement » **non validée**. | Conception / Juridique | **à créer** | Issue *« Flux droit à l'effacement (suppression blob par UUID + crypto-effacement) »* : concevoir l'endpoint de suppression, prouver l'irréversibilité, faire valider le crypto-effacement. |
| **ECART-03** | REQ-LEX-23 | **Aucune procédure de notification de violation** (délais, destinataires ARTCI / personnes). | Conception / Gouvernance | **à créer** | Issue *« Procédure d'incident & notification de violation (ARTCI + personnes concernées) »* : runbook + modèle de notification ; délais à confirmer juridiquement. |
| **ECART-04** | REQ-LEX-22 | **Désignation correspondant / DPO** non décidée (requise ou recommandée ?). | Gouvernance / Juridique | **à créer** | Issue *« Décision de gouvernance : désignation d'un correspondant/DPO »* ; consigner dans un ADR 0009 si confirmé. |
| **ECART-05** | REQ-LEX-02, REQ-LEX-05 | **Régime applicable aux données de santé** (autorisation préalable vs déclaration) et **consentement des mineurs** **non tranchés**. | Juridique | partiellement [#30](https://github.com/kortiene/HealthTech/issues/30) ; sinon **à créer** | Confirmer le régime ARTCI pour données sensibles + régime mineurs ; alimente [#7](https://github.com/kortiene/HealthTech/issues/7) (consentement) et [#30](https://github.com/kortiene/HealthTech/issues/30) (dossier). |
| **ECART-06** | REQ-LEX-21, REQ-LEX-24 (transverse) | **Répartition des rôles RT / sous-traitant** (patient / médecin / plateforme / hébergeur) **non déterminée** — conditionne plusieurs obligations. | Juridique / Gouvernance | **à créer** | Issue *« Qualification des rôles responsable de traitement / sous-traitant »* ; intègre le registre des traitements. |
| **ECART-07** | REQ-LEX-19, REQ-LEX-20 | **Base légale exacte de la localisation stricte** (obligation statutaire dure vs mitigation des restrictions de transfert) **à préciser** — impacte la formulation de REQ-LEX-01/02/19/20 **et le libellé de l'[attestation de localisation](./attestation-localisation-donnees.md) (§5)**. | Juridique | **à créer** (ou clarifié dans [#30](https://github.com/kortiene/HealthTech/issues/30)) | Faire trancher la base légale ; ajuster la formulation des exigences résidence/transferts **et figer §5 de l'attestation**. |
| **ECART-08** | *(hors périmètre #5 — signalé)* | **Accès d'urgence (break-glass)** : patient inconscient/incapable vs accès strictement contrôlé par QR — potentiellement exigé/encadré par la régulation santé. | Conception / Juridique | **à créer** *(probablement post-#5)* | Issue *« Accès d'urgence / break-glass — analyse de risque & d'admissibilité »* ; **ne pas** introduire de porte dérobée serveur. |

---

## Suivi

| ID | Statut | Date d'ouverture | Issue créée ? |
| --- | --- | --- | --- |
| ECART-01 | Ouvert | `[à dater]` | Non — proposition |
| ECART-02 | Ouvert | `[à dater]` | Non — proposition |
| ECART-03 | Ouvert | `[à dater]` | Non — proposition |
| ECART-04 | Ouvert | `[à dater]` | Non — proposition |
| ECART-05 | Ouvert | `[à dater]` | Partiel (#30) |
| ECART-06 | Ouvert | `[à dater]` | Non — proposition |
| ECART-07 | Ouvert | `[à dater]` | Non — proposition |
| ECART-08 | Signalé | `[à dater]` | Non — post-#5 |

> **Note.** La création effective des issues d'écart relève de l'orchestration GitHub (hors de cette phase
> de code). Les propositions de titres ci-dessus sont prêtes à être ouvertes. Voir aussi la mise à jour de
> [`BACKLOG.md`](../../BACKLOG.md) sous l'issue #5.
