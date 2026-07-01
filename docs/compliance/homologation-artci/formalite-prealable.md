# Note de procédure — formalité préalable ARTCI

> **Point d'entrée :** [`README.md`](./README.md). **Écart juridique associé :** [ECART-05](../ecarts.md)
> (régime données de santé / mineurs). **Suivi du récépissé :** `PREUVE-13` (voir [`piece-list.md`](./piece-list.md), PIECE-18).
>
> ⚠️ **Aucun numéro d'article ni délai ARTCI n'est inventé dans cette note.** Les points non confirmés
> portent la mention **`[à confirmer — conseil juridique]`**.

## 1. Nature de la formalité — `[à confirmer — conseil juridique]`

Le traitement porte sur des **données de santé** (données sensibles au sens de la
[loi n°2013-450](../README.md#6-glossaire)). Deux régimes de **formalité préalable** existent en pratique
ARTCI :

- **Déclaration** préalable ; ou
- **Autorisation préalable** (régime renforcé, souvent applicable aux catégories sensibles).

**La nature exacte applicable à HealthTech n'est pas tranchée** et relève du conseil juridique — voir
[ECART-05](../ecarts.md). Cette note **ne présume pas** du régime et **ne cite aucun délai** tant qu'il n'est
pas confirmé. La différence conditionne : les **pièces obligatoires**, le **format**, et le **type d'acte**
attendu en retour (récépissé de déclaration *vs* décision d'autorisation).

## 2. Destinataire & format de dépôt — `[à confirmer]`

- **Destinataire :** ARTCI (autorité de contrôle, Côte d'Ivoire).
- **Format de dépôt** (portail en ligne, dossier papier, modèle imposé par l'ARTCI) : **non documenté ici
  faute de source vérifiée** — `[à confirmer — conseil juridique]`. **Ne rien inventer.**
- **Langue :** français (langue faisant foi). Confirmer si l'ARTCI exige une version FR de **chaque** pièce
  technique (certaines specs/tests du dépôt sont bilingues).

## 3. Pièces obligatoires

La liste des pièces à joindre dépend du régime (§1). Le **catalogue transmissible** figure dans
[`piece-list.md`](./piece-list.md) (`PIECE-01 … PIECE-18`). Le sous-ensemble strictement obligatoire est à
**confirmer juridiquement** une fois le régime tranché ; a minima, le registre des traitements (PIECE-01),
la cartographie (PIECE-02), l'attestation de localisation (PIECE-07) et les textes de consentement/information
(PIECE-10, PIECE-11) en font partie.

## 4. Suivi du récépissé / décision (`PREUVE-13`)

- L'acte délivré par l'ARTCI (récépissé de déclaration **ou** décision d'autorisation) constitue
  **`PREUVE-13`**, aujourd'hui **« À produire »** ([`piece-list.md`](./piece-list.md), PIECE-18).
- **Consignation :** à réception, enregistrer le **numéro et la date** de l'acte dans
  [`../controles.md`](../controles.md) (ligne `PREUVE-13`) et mettre à jour le statut de PIECE-18 dans
  [`piece-list.md`](./piece-list.md) ; le fichier de l'acte lui-même sera archivé auprès du conseil
  juridique (hors dépôt de code — **aucune PII dans le repo**).

## 5. Étapes humaines / juridiques — **hors périmètre agent de code**

Les étapes suivantes sont **externes** et **ne sont pas** réalisées par un agent de code :

1. Trancher la **nature de la formalité** (ECART-05) — *conseil juridique.*
2. Constituer/valider les **pièces obligatoires** manquantes (attestation signée #8, pentest #25, écarts). 
3. **Déposer** le dossier auprès de l'ARTCI dans le format exigé — *conseil juridique.*
4. Assurer les **échanges** avec l'ARTCI et **obtenir** le récépissé/décision.
5. **Consigner** l'acte reçu (`PREUVE-13`) et clôturer la checklist ([`submission-checklist.md`](./submission-checklist.md)).

> Le rôle de l'agent de code s'arrête à la **constitution et la vérification** du dossier. Le **dépôt** et
> l'**obtention de l'homologation** sont une démarche humaine/juridique. Voir la
> [checklist de soumission](./submission-checklist.md) comme **gate humain** avant tout dépôt réel.
