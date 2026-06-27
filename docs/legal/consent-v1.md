# Textes juridiques HealthTech — version 1.0

> **STATUT : DRAFT — en attente de validation par le conseil juridique.**
>
> Ces textes couvrent les exigences de la loi ivoirienne n°2013-450 du 20 juin 2013 relative
> à la protection des données à caractère personnel et les recommandations de l'ARTCI.
> Chaque passage marqué `[à confirmer]` doit être validé par le conseil juridique avant toute
> mise en production.
>
> **Version :** 1.0 — corresponds to `consentBundleVersion = '1.0'` in
> `app-patient/lib/src/legal/consent_model.dart`.
>
> **Langue de référence :** Français.

---

## 1. Politique de consentement

### 1.1 Objet et base légale

HealthTech collecte et traite des données à caractère personnel et des données de santé aux seules
fins décrites dans la présente politique. Le traitement repose sur le **consentement explicite**
de la personne concernée, conformément à la loi n°2013-450 du 20 juin 2013 `[article à confirmer]`
et aux exigences de l'Autorité de Régulation des Télécommunications / TIC de Côte d'Ivoire (ARTCI).

### 1.2 Nature du consentement

Le consentement est :

- **Libre** — aucune condition de service général n'est subordonnée à l'acceptation de traitements
  facultatifs.
- **Spécifique** — chaque finalité est identifiée distinctement (voir § 2.2 de la politique de
  confidentialité ci-dessous).
- **Éclairé** — l'ensemble des informations nécessaires à une décision informée est fourni avant
  toute acceptation.
- **Univoque** — l'acceptation résulte d'un acte positif et délibéré de l'utilisateur (case à
  cocher ou bouton d'acceptation explicite).

### 1.3 Ce à quoi vous consentez

En acceptant, vous autorisez HealthTech à :

1. Stocker votre dossier médical personnel sous forme chiffrée (AES-256-GCM) sur votre appareil
   et sur un serveur d'hébergement situé en Côte d'Ivoire.
2. Vous permettre de partager temporairement votre dossier avec un professionnel de santé de votre
   choix, via un code QR éphémère valable environ 120 secondes.
3. Générer et conserver une empreinte de votre numéro CMU ou de téléphone pour la création de votre
   compte, sans jamais la transmettre en clair à un tiers.

### 1.4 Ce à quoi vous ne consentez pas

- Aucune vente, cession ni location de vos données à des tiers.
- Aucun traitement de vos données à des fins de profilage commercial.
- Aucun transfert de vos données en dehors du territoire ivoirien.

### 1.5 Retrait du consentement

Vous pouvez retirer votre consentement à tout moment en supprimant votre compte depuis l'application.
La suppression entraîne la destruction cryptographique de votre clé maîtresse (crypto-effacement),
rendant votre dossier inaccessible et irrécupérable. `[Procédure de suppression du blob serveur à
préciser — ECART-02]`.

### 1.6 Mineurs et personnes protégées

`[ECART-05 — le régime de consentement applicable aux mineurs et aux personnes sous tutelle selon
la loi n°2013-450 est en cours de confirmation par le conseil juridique. Cette clause sera complétée
avant la mise en production.]`

À titre provisoire, l'accès à l'application est réservé aux personnes majeures (18 ans ou plus) ou
disposant de l'autorisation de leur représentant légal.

### 1.7 Contact et réclamations

Pour exercer vos droits ou formuler une réclamation relative à la protection de vos données :

- **Responsable de traitement :** `[à désigner — ECART-06]`
- **Correspondant Données Personnelles / DPO :** `[à désigner si requis — ECART-04]`
- **ARTCI :** `[coordonnées officielles à confirmer]`

---

## 2. Conditions Générales d'Utilisation (CGU)

### 2.1 Objet

Les présentes Conditions Générales d'Utilisation régissent l'accès et l'utilisation de
l'application mobile HealthTech (ci-après « l'Application ») éditée par `[entité exploitante —
à désigner]`.

### 2.2 Accès au service

L'Application est fournie gratuitement aux patients et aux professionnels de santé inscrits. Elle
nécessite un appareil Android compatible et une connexion internet pour la synchronisation du blob
chiffré. Les fonctionnalités de consultation du dossier sont disponibles hors connexion.

### 2.3 Obligations de l'utilisateur

En utilisant l'Application, vous vous engagez à :

- Fournir des informations exactes lors de la création de votre compte.
- Conserver votre phrase de récupération en lieu sûr : sa perte rend votre dossier définitivement
  inaccessible.
- Ne pas partager votre code QR d'accès avec des personnes non autorisées.
- Ne pas tenter de contourner les mécanismes de chiffrement ou de sécurité de l'Application.

### 2.4 Responsabilité de l'éditeur

HealthTech met en œuvre les mesures techniques et organisationnelles décrites dans la politique de
confidentialité (§ 3) pour assurer la sécurité de vos données. L'éditeur ne peut être tenu
responsable :

- De la perte du dossier résultant de la perte de la phrase de récupération.
- Des interruptions de service indépendantes de sa volonté (coupures réseau, force majeure).
- De l'utilisation frauduleuse de votre code QR si vous l'avez communiqué à un tiers.

### 2.5 Propriété intellectuelle

L'Application et son code source sont protégés par le droit applicable en matière de propriété
intellectuelle. Aucune licence n'est accordée sur le code source. Les textes de santé et les
ordonnances contenus dans votre dossier vous appartiennent.

### 2.6 Modification des CGU

En cas de modification substantielle des présentes CGU, une notification sera affichée dans
l'Application. L'utilisation continuée de l'Application après notification vaut acceptation des
nouvelles conditions.

### 2.7 Droit applicable et juridiction

Les présentes CGU sont régies par le droit ivoirien. Tout litige sera soumis à la compétence des
juridictions compétentes de Côte d'Ivoire `[ville à préciser]`.

---

## 3. Politique de confidentialité

### 3.1 Identité du responsable de traitement

`[Entité exploitant HealthTech — à désigner avant la mise en production, ECART-06]`

### 3.2 Données collectées et finalités

| Donnée | Finalité | Base légale | Durée de conservation |
|---|---|---|---|
| Empreinte du n° CMU / téléphone | Identification du compte patient | Consentement | Durée d'activité du compte `[ECART-01]` |
| Dossier médical chiffré (blob opaque) | Stockage et partage de santé | Consentement | Durée d'activité du compte `[ECART-01]` |
| Clé maîtresse scellée (hardware) | Déchiffrement local uniquement | Exécution du service | Durée d'activité du compte |
| Horodatage de consentement | Preuve de recueil (REQ-LEX-04) | Obligation légale | `[ECART-01]` |
| UUID anonyme du blob | Adressage du blob sur le serveur | Intérêt légitime (sécurité) | Durée d'activité du compte |

> **Note :** Le serveur de stockage ne reçoit et ne stocke que le **blob chiffré opaque** et l'UUID
> anonyme. Il n'a accès à aucune donnée identifiante, aucune clé de chiffrement, aucun contenu
> médical.

### 3.3 Destinataires des données

- **Professionnel de santé autorisé** — accès RAM uniquement, via code QR éphémère (~120 s),
  initié par le patient.
- **Hébergeur souverain** — stocke uniquement le blob opaque en Côte d'Ivoire.
- **Aucun tiers commercial, aucun sous-traitant hors Côte d'Ivoire.**

### 3.4 Transferts hors Côte d'Ivoire

**Aucun.** Toutes les données sont hébergées sur le territoire ivoirien, conformément à la loi
n°2013-450 et aux recommandations de l'ARTCI `[base légale exacte de la localisation à préciser —
ECART-07]`.

### 3.5 Droits de la personne concernée

Conformément à la loi n°2013-450 `[articles à confirmer]`, vous disposez des droits suivants :

- **Droit d'accès** — votre dossier médical est accessible hors ligne sur votre appareil à tout
  moment (architecture local-first).
- **Droit de rectification** — vous pouvez modifier votre dossier directement dans l'Application.
- **Droit à l'effacement** — la suppression du compte entraîne la destruction cryptographique de
  la clé maîtresse, rendant le blob serveur inaccessible `[procédure de suppression du blob à
  compléter — ECART-02]`.
- **Droit à la limitation du traitement** — contacter le responsable de traitement `[ECART-06]`.
- **Droit d'opposition** — contacter le responsable de traitement `[ECART-02, ECART-06]`.
- **Droit à la portabilité** — export en JSON chiffré planifié `[issue à créer]`.

Pour exercer ces droits : `[coordonnées du responsable de traitement — à désigner]`.

### 3.6 Sécurité

HealthTech met en œuvre les mesures suivantes :

- **Chiffrement AES-256-GCM** du dossier médical côté patient (jamais en clair sur le réseau).
- **Clé maîtresse scellée dans l'Android Keystore** (StrongBox → TEE), non exportable.
- **Zero-knowledge** : le serveur ne stocke que des blobs opaques et ne peut déchiffrer aucune donnée.
- **Transit TLS** entre l'application et le serveur d'hébergement.
- **Accès professionnel éphémère** : code QR valable ~120 s, déchiffrement en mémoire vive
  uniquement, effacement en fin de session.

### 3.7 Cookies et traceurs

L'Application mobile **n'utilise pas de cookies**. Aucun traceur tiers n'est intégré.

### 3.8 Contact ARTCI

Pour toute réclamation relative à la protection de vos données auprès de l'autorité de contrôle :

**ARTCI — Autorité de Régulation des Télécommunications / TIC de Côte d'Ivoire**
`[adresse et coordonnées officielles à confirmer]`

### 3.9 Mise à jour de la politique

La présente politique peut être mise à jour. La version en vigueur est identifiée par son numéro
de version (`1.0` à la date de rédaction de ce document). Toute mise à jour substantielle fera
l'objet d'une notification dans l'Application et pourra requérir un nouveau consentement.

---

*Document version 1.0 — DRAFT — à valider par le conseil juridique avant toute mise en production.*
