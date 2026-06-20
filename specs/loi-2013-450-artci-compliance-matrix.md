# Matrice de conformité — loi n°2013-450 & exigences ARTCI

> Spec pour **GitHub issue #5 — Analyse de conformité loi n°2013-450 & exigences ARTCI**
> (Épic E6 — Conformité, légal & gouvernance · Effort **L** · Priorité **Must** · labels `compliance` `docs`).
> Critère d'acceptation de l'issue : **une matrice de conformité « exigence → contrôle technique → preuve »,
> validée par le conseil juridique.**
>
> Ceci est **un document de planification uniquement — ne rien implémenter ici.** Un agent de code
> ultérieur exécutera la checklist. Le livrable de cette issue est *documentaire* (une matrice + ses
> artefacts d'appui), pas du code applicatif.

---

## Problem Statement

Le lancement commercial est conditionné à l'**homologation ARTCI** (issue #30), qui exige de prouver que
la plateforme respecte la **loi ivoirienne n°2013-450 du 19 juin 2013 relative à la protection des données
à caractère personnel** et les exigences de l'ARTCI (autorité de protection des données en Côte d'Ivoire).
Le PRD (§5) impose un « alignement strict » sur cette loi et l'hébergement obligatoire des données sur le
territoire national, mais **aucun artefact ne fait aujourd'hui le lien explicite, exigence par exigence,
entre le texte de loi et l'architecture technique du produit.**

Le projet possède déjà une architecture *local-first / zero-knowledge* fortement orientée vie privée
(chiffrement AES-256-GCM côté patient, blobs opaques indexés par UUID anonyme, QR éphémère ~120 s,
déchiffrement en RAM uniquement, hébergement souverain) décrite dans le PRD et figée dans les ADR
`0001`–`0008`. Mais **« avoir de bons contrôles » ne suffit pas** : l'ARTCI et le conseil juridique
attendent une **traçabilité formelle** montrant, pour *chaque* obligation légale, (1) quelle exigence
technique/organisationnelle la satisfait, (2) où vit la preuve, et (3) qui en est responsable.

**Le manque :** il n'existe ni registre des exigences légales atomisées, ni catalogue de contrôles mappés,
ni catalogue de preuves, ni journal de validation juridique, ni détection des écarts (exigence sans
contrôle, ou contrôle sans preuve). Cette issue comble ce manque en produisant la **matrice de conformité**
et ses artefacts d'appui, base probante du dossier d'homologation (#30).

## Goals

1. **Un registre d'exigences légales** atomisé à partir de la loi n°2013-450 et des exigences ARTCI :
   chaque obligation = une ligne identifiée (`REQ-LEX-NN`), avec sa source (article / texte ARTCI),
   sa catégorie (résidence, consentement, droits du patient, sécurité, formalités préalables, durée de
   conservation, etc.) et son caractère obligatoire.
2. **Un catalogue de contrôles** (`CTRL-NN`) techniques et organisationnels, chacun rattaché à l'ADR et/ou
   à l'issue qui le décide/l'implémente (p. ex. ADR 0005 hébergement souverain, #10 AES-256-GCM, #9 service
   zero-knowledge, #16 QR éphémère, #17/#19 RAM-only + wipe, #7 consentement, #8 hébergement, #6 modèle de
   menace).
3. **Un catalogue de preuves** (`PREUVE-NN`) : pour chaque contrôle, l'artefact qui le démontre (vecteurs
   de test NIST, test « le serveur ne peut pas déchiffrer », capture réseau « pas de PII en clair »,
   attestation de localisation des données, rapport de pentest, texte de consentement validé, etc.) —
   avec son statut de disponibilité (existant / planifié / à produire).
4. **La matrice de conformité** liant `exigence → contrôle(s) → preuve(s)`, avec statut
   (`Conforme` / `Partiel` / `Planifié` / `Écart`), responsable, et **colonne de validation juridique**.
5. **Détection et suivi des écarts** : toute exigence `Must` sans contrôle, ou sans preuve, ou sans issue
   porteuse, est listée comme **écart** et tracée vers une issue (existante ou à créer).
6. **Artefacts d'accountability d'appui** : un **registre des traitements** (registre des activités de
   traitement) et une **cartographie des données / flux** matérialisant la frontière zero-knowledge
   (le serveur ne voit que des blobs opaques + UUID anonymes).
7. **Un workflow de validation par le conseil juridique** : journal de revue/sign-off horodaté par exigence,
   condition de « matrice validée » (toutes les exigences `Must` signées) — c'est le critère d'acceptation.
8. **Une matrice maintenable et vérifiable** : format stable, références croisées résolvables (issues/ADR),
   et un contrôle de complétude automatisable (chaque ligne a contrôle + preuve + responsable + statut),
   prêt à alimenter le **dossier d'homologation ARTCI (#30)**.

## Non-Goals

- **Soumission effective du dossier d'homologation à l'ARTCI** et constitution complète du dossier — c'est
  **#30** (cette issue *fournit* la matrice probante que #30 consomme).
- **Modèle de menace / politique de sécurité (STRIDE)** — c'est **#6**. La matrice *référence* le threat
  model comme contrôle/preuve de sécurité, sans le rédiger.
- **Rédaction des écrans de consentement, CGU et politique de confidentialité** — c'est **#7**. La matrice
  *exige* et *trace* ces textes, sans les écrire ; elle pourra recenser les exigences de contenu.
- **Provisionnement réel de l'hébergement souverain et obtention de l'attestation de localisation** — c'est
  **#8**. La matrice *exige* la preuve de résidence, sans provisionner l'infrastructure.
- **Implémentation des contrôles techniques** (crypto #10, service ZK #9, QR #16, wipe #19, etc.) — ces
  contrôles sont décidés/planifiés ailleurs ; cette issue ne fait que les **cartographier** et pointer la
  preuve attendue. Aucun statut « Conforme » ne doit être affirmé pour un contrôle non encore livré.
- **Avis juridique faisant autorité.** L'agent de code *rédige* la matrice ; **l'interprétation et la
  validation de droit ivoirien relèvent du conseil juridique** (le sign-off est le livrable de fin).
- **Toute modification de la cryptographie ou de l'architecture.** Si la matrice révèle un écart, on crée
  une issue ; on n'« ajuste » jamais un contrôle pour qu'il « coche la case » au prix d'un affaiblissement.

## Relevant Repository Context

**État du dépôt.** Projet *greenfield* côté fonctionnel : il existe le PRD (`PRD_HealthTech.md`), le backlog
(`BACKLOG.md`), les ADR (`docs/adr/0000`–`0008`), un **squelette de monorepo polyglotte** (Flutter
`app-patient/`, PWA Preact `app-medecin/`, crate Rust `crypto-core/`, backend Rust/Axum `backend/`, IaC
`infra/`) et un spec existant (`specs/environments-and-secrets-management.md`). **Aucune logique métier de
sécurité n'est encore implémentée** — donc, dans la matrice, la majorité des contrôles techniques sont au
statut *Planifié* (décidés par ADR/backlog) et non *Conforme*. Il n'existe **aucun répertoire
`docs/compliance/`** : cette issue le crée.

**Sur la stack (nuance importante).** Le backlog #1 présentait la stack comme « à trancher ». Elle a depuis
été **arrêtée par les ADR 0001–0008** (Flutter / PWA Preact / cœur crypto Rust unique / backend Rust-Axum /
MinIO+PostgreSQL souverains / SOPS+age / CI GitHub Actions). **Pour cette issue, c'est largement sans
incidence :** une matrice de conformité s'exprime au **niveau exigence/architecture** (résidence des
données, zero-knowledge, chiffrement authentifié, accès éphémère contrôlé par le patient), pas au niveau
langage/framework. La matrice doit donc rester **agnostique de la stack** dans la formulation des exigences,
tout en **pointant les contrôles concrets décidés par les ADR** comme éléments de preuve. Les seules
décisions *encore réellement ouvertes* sont **spécifiques à la conformité** et listées dans *Open
Questions* (régime déclaration vs autorisation pour données de santé, désignation d'un correspondant/DPO,
durées de conservation, procédure de notification de violation, base légale exacte de la localisation
stricte). Le **format/outillage de vérification** de la matrice (Markdown vs CSV ; linter de complétude
intégré à la CI #3) est lui aussi *stack-dépendant* et à confirmer.

**Conventions à respecter.**
- Spec sous `specs/`, en-têtes de sections standardisés (cf. `specs/environments-and-secrets-management.md`).
- Décisions structurantes capturées en **ADR** dans `docs/adr/` (format *Status · Context · Decision ·
  Consequences · Alternatives*, indexé dans `0000-index.md`).
- Références croisées explicites vers les issues (`#NN`) et ADR (`0005`…) ; documentation en **français**
  (domaine juridique ivoirien francophone ; le conseil juridique travaille sur le texte français).
- Invariants produit non négociables (PRD §4) : chiffrement client AES-256-GCM avant tout transit ;
  serveur zero-knowledge (blobs opaques + UUID anonymes) ; QR ~120 s ; déchiffrement RAM-only + wipe de fin
  de session ; résidence en Côte d'Ivoire ; dossier texte ≤ 500 Ko ; pas d'image lourde sur le téléphone
  (URL éphémère seulement) ; ne jamais journaliser données médicales en clair, clés ou PII.

## Proposed Implementation

Produire un ensemble d'artefacts documentaires versionnés sous **`docs/compliance/`**, la matrice étant la
pièce maîtresse. Approche en couches (exigences → contrôles → preuves → matrice → validation).

### 1. Arborescence des livrables (`docs/compliance/`)

- `README.md` — objet, méthodologie, mode d'emploi de la matrice, glossaire (RT = responsable de
  traitement, sous-traitant, donnée sensible, etc.), conventions d'identifiants (`REQ-LEX-NN`, `CTRL-NN`,
  `PREUVE-NN`), liens vers PRD/ADR/issues.
- `exigences-legales.md` — **registre des exigences** atomisées (source → énoncé → catégorie → obligation).
- `controles.md` — **catalogue des contrôles** techniques/organisationnels (chacun → ADR/issue porteuse).
- `loi-2013-450-artci-matrix.md` — **la matrice** `exigence → contrôle(s) → preuve(s) → statut →
  responsable → validation juridique` (cœur du livrable ; voir gabarit ci-dessous). Optionnellement
  doublée d'un `*.csv` machine-lisible si l'outillage de vérification le requiert (à confirmer avec #3).
- `registre-des-traitements.md` — registre des activités de traitement (finalité, catégories de données et
  de personnes, destinataires, durée de conservation, mesures de sécurité, transferts).
- `cartographie-donnees-et-flux.md` — inventaire des données + schéma de flux matérialisant la frontière
  zero-knowledge (ce qui reste sur l'appareil vs ce qui transite chiffré vs ce que voit le serveur).
- `journal-validation-juridique.md` — **journal de sign-off** du conseil juridique (exigence, verdict, date,
  réviseur, commentaires/réserves).
- `ecarts.md` — registre des **écarts** (exigence `Must` non couverte) → issue porteuse (existante/à créer).

### 2. Méthodologie (déroulé pour l'agent + le conseil juridique)

1. **Sourcer le droit applicable** (avec le conseil juridique) : texte officiel de la loi n°2013-450,
   textes/décisions/lignes directrices de l'ARTCI, et toute règle sectorielle santé applicable. Consigner
   les références exactes (article, alinéa) dans `exigences-legales.md`. *Ne pas inventer de numéros
   d'articles* : laisser des emplacements `[à confirmer — conseil juridique]` plutôt qu'une citation non
   vérifiée.
2. **Atomiser les exigences** : une obligation = une ligne `REQ-LEX-NN` (énoncé en langage clair + citation
   source + catégorie + `Must/Should`). Catégories cibles : *Formalités préalables (déclaration /
   autorisation)*, *Base légale & consentement*, *Données sensibles (santé)*, *Principes (finalité,
   minimisation, exactitude)*, *Durée de conservation*, *Droits de la personne concernée (information,
   accès, rectification, opposition, suppression/oubli)*, *Sécurité & confidentialité*, *Résidence &
   transferts transfrontaliers*, *Accountability (registre, correspondant/DPO)*, *Violations de données
   (notification)*, *Sous-traitance (hébergeur)*.
3. **Construire le catalogue de contrôles** depuis l'architecture décidée (ADR 0001–0008) et le backlog
   (issues), chaque `CTRL-NN` rattaché à sa source de vérité.
4. **Mapper** chaque `REQ-LEX-NN` → un ou plusieurs `CTRL-NN` → une ou plusieurs `PREUVE-NN`, et fixer le
   **statut** (Conforme / Partiel / Planifié / Écart) honnêtement selon l'état réel de livraison.
5. **Identifier les écarts** : toute exigence sans contrôle, sans preuve, ou sans issue → `ecarts.md` +
   proposition d'issue.
6. **Validation juridique** : le conseil juridique revoit ligne à ligne, consigne son verdict dans
   `journal-validation-juridique.md`. La matrice est « validée » quand toutes les exigences `Must` sont
   signées sans réserve bloquante (= critère d'acceptation atteint).
7. **Alimenter #30** : la matrice validée + le registre + l'attestation de localisation deviennent des
   pièces du dossier d'homologation.

### 3. Gabarit de la matrice (colonnes obligatoires)

| Col. | Contenu |
| --- | --- |
| `REQ-LEX-NN` | Identifiant exigence |
| Source légale | Loi n°2013-450 art. … / référence ARTCI |
| Exigence (langage clair) | Ce que la loi impose |
| Catégorie | Résidence / Consentement / Droits patient / Sécurité / … |
| `Must/Should` | Caractère obligatoire |
| Contrôle(s) `CTRL-NN` | Mesure(s) technique(s)/organisationnelle(s) |
| ADR / Issue porteuse | `0005`, `#9`, `#16`, … |
| Preuve(s) `PREUVE-NN` | Artefact démontrant le contrôle |
| Statut | Conforme / Partiel / Planifié / Écart |
| Responsable | Owner |
| Validation juridique | Oui/Non + date + réserves |

### 4. Extrait illustratif (non exhaustif — à compléter avec le conseil juridique)

> ⚠️ Citations d'articles **à confirmer** par le conseil juridique ; les contrôles ci-dessous sont
> majoritairement au statut *Planifié* (décidés par ADR/backlog, non encore implémentés).

| REQ | Exigence (résumé) | Contrôle(s) | ADR/Issue | Preuve attendue | Statut |
| --- | --- | --- | --- | --- | --- |
| REQ-LEX-01 | **Résidence des données** sur le territoire national | Hébergement souverain in-country, aucun cloud étranger dans le chemin de données ; clés de secrets in-country | ADR 0005, ADR 0007, #8 | Attestation de localisation ; garde-fou IaC `country == "CI"` ; contrat hébergeur | Planifié |
| REQ-LEX-02 | **Restriction des transferts transfrontaliers** | Aucun service managé étranger ; URL média éphémères servies depuis MinIO in-country | ADR 0005, #23 | Audit d'architecture/dépendances ; revue réseau | Planifié |
| REQ-LEX-03 | **Donnée de santé (sensible)** : base légale renforcée / autorisation préalable | Consentement explicite patient ; demande d'autorisation ARTCI | #7, #30 | Texte de consentement validé ; décision d'autorisation ARTCI | Écart (à instruire) |
| REQ-LEX-04 | **Consentement libre, spécifique, éclairé** | Écrans de consentement + CGU + politique de confidentialité dans l'onboarding | #7, #13 | Textes validés juridiquement ; horodatage de capture du consentement | Planifié |
| REQ-LEX-05 | **Droit d'accès** de la personne concernée | Modèle local-first : le patient détient et lit son dossier ; récupération de clé | #15, #12 | Démo app patient affichant le dossier complet | Planifié |
| REQ-LEX-06 | **Droit de rectification** | Édition du dossier + rechiffrement | #18, #15 | Parcours d'édition → rechiffrement | Planifié |
| REQ-LEX-07 | **Droit à la suppression / opposition** | Suppression du blob par UUID ; **crypto-effacement** (destruction de la clé rend le blob irrécupérable) | #9 | Endpoint de suppression ; preuve d'irréversibilité ; *(flux de suppression à concevoir)* | Écart (à instruire) |
| REQ-LEX-08 | **Sécurité & confidentialité** (mesures techniques) | AES-256-GCM côté client ; Android Keystore ; TLS ; zero-knowledge ; threat model ; pentest ; revue crypto | #10, #11, #9, #6, #25, #26 | Vecteurs NIST (#10) ; test « serveur ne peut pas déchiffrer » (#9) ; rapport pentest (#25) | Planifié |
| REQ-LEX-09 | **Confidentialité de l'accès / partage contrôlé par le patient** | QR éphémère ~120 s ; déchiffrement RAM-only + wipe de fin de session | #16, #17, #19 | Test d'expiration QR ; analyse mémoire/disque (pas d'écriture en clair) | Planifié |
| REQ-LEX-10 | **Minimisation / finalité** | Serveur ne stocke que métadonnées non identifiantes + UUID anonymes ; dossier ≤ 500 Ko | ADR 0005, #15 | Schéma DB ; garde-fou 500 Ko (#15) | Planifié |
| REQ-LEX-11 | **Durée de conservation limitée** | Politique de rétention *(à définir)* ; URL média expirantes ; QR 120 s ; wipe de session | #23, #16, #19 | Politique de rétention documentée ; tests d'expiration | Écart (à instruire) |
| REQ-LEX-12 | **Notification des violations de données** | Procédure d'incident/notification ARTCI & personnes *(à définir)* | #6 (référence) | Runbook d'incident ; modèle de notification | Écart (à instruire) |
| REQ-LEX-13 | **Accountability — registre des traitements** | Registre des activités de traitement | #5 (cette issue) | `registre-des-traitements.md` | Planifié |
| REQ-LEX-14 | **Correspondant / DPO** *(si requis)* | Désignation d'un correspondant à la protection des données *(décision de gouvernance)* | — | Acte de désignation | Écart (à confirmer) |
| REQ-LEX-15 | **Formalités préalables** (déclaration/autorisation) | Dépôt ARTCI | #30 | Récépissé / décision ARTCI | Planifié |
| REQ-LEX-16 | **Encadrement de la sous-traitance** (hébergeur) | Clauses contractuelles avec l'opérateur d'hébergement | #8 | Contrat / clauses de protection des données | Planifié |
| REQ-LEX-17 | **Journalisation sans PII/clés/clair** | Politique de rédaction des logs (jamais de données médicales en clair, clés, PII) | ADR 0007 | Audit des logs ; configuration de redaction | Planifié |

### 5. Maintenabilité & vérification

- Identifiants stables et références croisées résolvables (chaque `#NN`/ADR cité existe).
- **Contrôle de complétude** (script léger, *outillage à confirmer avec #3*) : chaque ligne `Must` a au
  moins un contrôle, une preuve, un responsable, un statut ; aucun contrôle orphelin ; aucun écart non tracé.
- **Invariant de non-régression conformité** : un test/lint vérifie que la matrice ne décrit jamais un
  contrôle impliquant un déchiffrement côté serveur ou un stockage de clé/PII en clair (garde-fou anti
  « coche-la-case-au-prix-de-la-crypto »).

## Affected Files / Packages / Modules

**À créer :**
- `docs/compliance/README.md`
- `docs/compliance/exigences-legales.md`
- `docs/compliance/controles.md`
- `docs/compliance/loi-2013-450-artci-matrix.md` *(+ `.csv` optionnel)*
- `docs/compliance/registre-des-traitements.md`
- `docs/compliance/cartographie-donnees-et-flux.md`
- `docs/compliance/journal-validation-juridique.md`
- `docs/compliance/ecarts.md`
- *(optionnel)* `docs/adr/0009-compliance-governance.md` — une fois le régime (déclaration/autorisation),
  la rétention et la désignation correspondant/DPO confirmés par le conseil juridique.

**À lire (sources d'autorité pour le mapping) :**
- `PRD_HealthTech.md` (§4 sécurité, §5 NFR conformité) ; `BACKLOG.md` (E6, #6/#7/#8/#9/#30 et dépendances).
- `docs/adr/0000-index.md`, `0003`–`0008` (contrôles techniques) ; `specs/environments-and-secrets-management.md`.
- Squelette : `infra/terraform/` (garde-fou résidence `country`), `backend/`, `crypto-core/` (référence de
  contrôle uniquement — **ne rien modifier**).

**À mettre à jour :**
- `BACKLOG.md` (lier #5 au spec et aux livrables ; ajouter les issues d'écart découvertes).
- `docs/adr/0000-index.md` (si un ADR 0009 conformité est ajouté).

## API / Interface Changes

**None.** Livrable purement documentaire ; aucune CLI, API publique, endpoint réseau, ni surface
QR/jeton d'accès n'est ajoutée ou modifiée. La matrice *décrit* des surfaces décidées ailleurs (p. ex.
`PUT/GET /blob/{uuid}` de #9, le QR ~120 s de #16) à des fins de preuve, sans les créer.

## Data Model / Protocol Changes

**None** au sens applicatif. Aucun schéma d'enregistrement, format de blob chiffré, persistance ou
sérialisation n'est modifié. Les seuls « schémas » introduits sont **documentaires** : la structure
tabulaire de la matrice et le gabarit du registre des traitements (sous `docs/compliance/`). La
cartographie des données *décrit* le modèle existant (UUID anonyme ↔ blob AES-256-GCM, métadonnées non
identifiantes) sans le changer.

## Security & Compliance Considerations

Cette issue *est* l'artefact de conformité ; elle doit refléter et **renforcer** les invariants, jamais les
diluer :

- **Zero-knowledge & chiffrement client.** La matrice doit démontrer que le dossier est chiffré côté
  patient en **AES-256-GCM** avant tout transit, et que le serveur ne détient que des **blobs opaques
  indexés par UUID anonymes** (preuve attendue : test « le serveur ne peut pas déchiffrer », #9 ; vecteurs
  NIST, #10). C'est l'argument central de conformité (minimisation, sécurité, et de fait quasi-anonymisation
  côté serveur).
- **Gestion des clés.** Clé maîtresse générée sur l'appareil, scellée dans l'Android Keystore, jamais
  exportée en clair (ADR 0006, #11) ; récupération PBKDF2 (#12). La matrice ne doit **jamais** proposer un
  contrôle qui ferait transiter ou stocker une clé côté serveur. Le crypto-effacement (destruction de clé =
  irrécupérabilité) sera proposé comme mécanisme du droit à l'effacement — **à valider juridiquement**.
- **Accès éphémère contrôlé par le patient.** QR ~120 s (#16) ; déchiffrement **en RAM uniquement** + wipe
  de fin de session / inactivité (#17, #19). Preuve attendue : tests d'expiration et analyse
  mémoire/disque. *(Réserve connue, ADR 0000 risque #1 : le RAM-only en navigateur est « best-effort » — à
  signaler honnêtement dans la matrice et au pentest #25.)*
- **Résidence des données (ARTCI / loi n°2013-450).** Hébergement exclusivement sur sol ivoirien, aucun
  cloud étranger dans le chemin de données, clés de secrets in-country (ADR 0005, ADR 0007, #8). Preuve :
  attestation de localisation + garde-fou IaC `country == "CI"`.
- **Budget de 500 Ko & médias lourds.** Le dossier texte chiffré reste ≤ 500 Ko (#15) ; **aucune image
  médicale lourde n'est stockée sur le téléphone** — seule une **URL éphémère** est intégrée (#23). Ces
  contraintes appuient minimisation et sécurité dans la matrice.
- **Journalisation / redaction.** Ne **jamais** journaliser de données médicales en clair, de clés ou de
  PII (cohérent avec ADR 0007 « ne logge jamais de valeur de secret »). Ceci vaut aussi pour les artefacts
  de conformité eux-mêmes : la matrice, le registre et la cartographie **ne doivent contenir aucune donnée
  patient réelle** (uniquement catégories, schémas, flux).
- **Frontière secrets opérationnels vs clés patient.** Rappeler que la conformité ne déplace jamais des
  clés patient dans un coffre-fort serveur (préservation de la frontière de l'ADR 0007).

## Testing Plan

Livrable documentaire → tests de **documentation / traçabilité** (pas de tests crypto nouveaux ; la matrice
*référence* ceux de #9/#10/#25) :

- **Lint Markdown & intégrité des liens** : toutes les références `#NN` / ADR / fichiers résolvent.
- **Validation de schéma de la matrice** : chaque ligne possède les colonnes obligatoires (REQ, source,
  contrôle, preuve, statut, responsable, validation).
- **Gate de complétude** : chaque exigence `Must` a ≥ 1 contrôle, ≥ 1 preuve, un responsable et un statut ;
  aucun contrôle orphelin ; chaque écart est tracé vers une issue.
- **Test de traçabilité backlog** : chaque issue porteuse citée existe dans `BACKLOG.md` ; toute exigence
  sans issue porteuse apparaît dans `ecarts.md`.
- **Invariant anti-régression conformité** : un check échoue si la matrice décrit un contrôle impliquant un
  déchiffrement serveur ou un stockage clé/PII en clair.
- **Gate de validation juridique** : la matrice n'est marquée « validée » que si
  `journal-validation-juridique.md` couvre toutes les exigences `Must` (critère d'acceptation de #5).
- *(Outillage du gate — script langage X / action CI — **à confirmer avec #3** ; garder agnostique.)*

## Documentation Updates

- **`BACKLOG.md`** : référencer ce spec et les livrables `docs/compliance/` sous #5 ; ajouter les issues
  d'écart découvertes (p. ex. flux de suppression/effacement, procédure de notification de violation,
  politique de rétention, désignation correspondant/DPO si requis).
- **`docs/adr/`** : ajouter `0009-compliance-governance.md` (et l'entrée dans `0000-index.md`) une fois
  confirmés par le conseil juridique : régime déclaration vs autorisation, durées de conservation,
  désignation correspondant/DPO, procédure de notification de violation.
- **`PRD_HealthTech.md`** : ajouter dans §5 un renvoi vers la matrice de conformité comme preuve de
  l'« alignement strict » revendiqué.
- **Liens croisés** : #30 (dossier d'homologation) pointe la matrice comme pièce probante principale ; #6
  (threat model) et #7 (consentement/CGU) sont liés depuis les lignes correspondantes.
- **`docs/compliance/README.md`** : point d'entrée de navigation du volet conformité.

## Risks and Open Questions

1. **Interprétation juridique faisant autorité.** L'agent de code n'est pas juriste : il *structure* et
   *pré-remplit*, mais l'exactitude des citations et la couverture relèvent du **conseil juridique**.
   Risque de matrice incomplète/erronée sans cette validation → le sign-off est bloquant.
2. **Régime applicable aux données de santé.** Les données de santé sont des **données sensibles** :
   relèvent-elles d'une **autorisation préalable** ARTCI (et non d'une simple déclaration) ? À confirmer.
3. **Base légale de la localisation stricte.** Le PRD impose le stockage national ; est-ce une obligation
   statutaire dure, ou une mitigation de risque dérivée des restrictions de transfert transfrontalier ? À
   préciser avec le conseil juridique (impacte la formulation de REQ-LEX-01/02).
4. **Tension « droit à l'oubli » vs rétention médicale obligatoire.** Le droit de suppression peut entrer
   en conflit avec des durées de conservation **minimales** légalement imposées aux dossiers médicaux. À
   arbitrer (qui est responsable de traitement pour quelle donnée — patient, médecin, plateforme ?).
5. **Crypto-effacement comme suppression légale.** La destruction de la clé (rendant le blob illisible)
   est-elle juridiquement acceptable comme « effacement » au sens de la loi ? À valider.
6. **Rôles RT / sous-traitant.** Le médecin et la plateforme sont-ils responsables conjoints, le médecin
   responsable et la plateforme sous-traitant, ou autre ? Détermine plusieurs obligations.
7. **Notification de violation.** Délais et destinataires (ARTCI / personnes concernées) à définir → issue
   d'écart probable.
8. **Correspondant / DPO.** Désignation requise ou recommandée ? Décision de gouvernance.
9. **Accès d'urgence (break-glass).** L'accès strictement contrôlé par le patient via QR pose la question
   du patient inconscient/incapable. Probablement hors périmètre #5, mais à **signaler** car potentiellement
   exigé/encadré par la régulation santé.
10. **Consentement des mineurs / personnes protégées** : régime spécifique à confirmer.
11. **Format & outillage de la matrice** (Markdown vs CSV ; linter de complétude dans la CI #3) :
    *stack-dépendant*, à confirmer.
12. **Langue.** Version française faisant foi (droit ivoirien) ; un résumé anglais pour auditeurs
    internationaux est-il souhaité ? À confirmer.

## Implementation Checklist

1. Créer le répertoire `docs/compliance/` et `README.md` (objet, méthodologie, conventions d'ID, glossaire,
   liens PRD/ADR/issues).
2. Avec le conseil juridique, sourcer la loi n°2013-450 + textes/lignes directrices ARTCI + règles
   sectorielles santé ; consigner les références exactes (laisser `[à confirmer]` plutôt qu'inventer).
3. Rédiger `exigences-legales.md` : atomiser chaque obligation en `REQ-LEX-NN` (source, énoncé clair,
   catégorie, Must/Should).
4. Rédiger `controles.md` : cataloguer les `CTRL-NN` depuis les ADR 0001–0008 et les issues du backlog,
   chacun rattaché à sa source de vérité.
5. Rédiger `loi-2013-450-artci-matrix.md` selon le gabarit de colonnes ; mapper exigence → contrôle(s) →
   preuve(s) ; fixer un statut honnête (Conforme / Partiel / Planifié / Écart) selon l'état réel.
6. Produire `registre-des-traitements.md` et `cartographie-donnees-et-flux.md` (frontière zero-knowledge),
   **sans aucune donnée patient réelle**.
7. Rédiger `ecarts.md` : lister chaque exigence `Must` non couverte → issue porteuse (existante / à créer) ;
   proposer la création des issues manquantes (suppression/effacement, notification de violation, rétention,
   correspondant/DPO le cas échéant).
8. Mettre en place les contrôles de qualité (lint Markdown + liens, validation de schéma, gate de
   complétude, invariant anti-régression conformité, gate de traçabilité backlog) — *outillage à confirmer
   avec #3*.
9. Faire réviser la matrice par le conseil juridique ; consigner les verdicts dans
   `journal-validation-juridique.md` jusqu'au sign-off de toutes les exigences `Must` (= critère
   d'acceptation).
10. Mettre à jour `BACKLOG.md` (#5 + issues d'écart), `PRD_HealthTech.md` (§5 renvoi matrice) et, si les
    décisions de gouvernance sont confirmées, ajouter `docs/adr/0009-compliance-governance.md` + entrée
    d'index.
11. Lier la matrice validée depuis #30 (dossier d'homologation) comme pièce probante principale.
12. Vérifier qu'aucun fichier ne contient de données patient réelles, de clés ou de PII, et que la matrice
    ne décrit aucun contrôle affaiblissant la crypto ou le modèle zero-knowledge.
