# Design Brief — HealthTech

## Application Patient (Flutter) · Interface Médecin (PWA Preact)

**Version :** 1.0 — Juillet 2026  
**Destinataires :** IA de code (implémentation Flutter + Preact)  
**Langue de l'UI :** Français ivoirien

---

## 0. Mission

Produire un design **moderne, épuré et intuitif** pour deux surfaces :

1. **App Patient** — Flutter, Android entrée de gamme + macOS dev
2. **Interface Médecin** — PWA Preact + TypeScript, mobile-first

Le code existant contient toute la logique métier (crypto, services, controllers). L'IA ne modifie **que** les fichiers UI : widgets `build()`, thème Flutter, composants Preact, CSS.

**Liberté totale sur :** mise en page, animations, choix de composants, hiérarchie visuelle.  
**Non négociable :** les contraintes listées ci-dessous.

---

## 1. Contexte & Personas

### Awa — Patiente, 28 ans

Smartphone Infinix entrée de gamme, souvent saturé, réseau 3G instable. Usage rapide, à une main, en déplacement. Elle ne lit pas de notices.

### Dr. Koné — Médecin généraliste, 42 ans

~30 patients par jour. Debout, en pleine lumière de clinique. Il a besoin que ça marche immédiatement, sans formation. Chaque seconde compte.

---

## 2. Système de Design

### 2.1 Palette de couleurs

```
PRIMAIRE — vert émeraude (santé, confiance, nature ivoirienne)
  primary-900:  #003D39
  primary-700:  #006C67   ← couleur principale (boutons, AppBar, accents)
  primary-500:  #00A89E   ← couleur active, focus
  primary-100:  #E0F5F4   ← fonds de chips, icônes cercles
  primary-50:   #F0FAFA   ← fond d'écran global

NEUTRALES
  neutral-900:  #1A1A1A   ← texte principal
  neutral-700:  #3D3D3D   ← texte secondaire
  neutral-500:  #737373   ← labels, placeholders
  neutral-200:  #E5E5E5   ← dividers, bordures
  neutral-100:  #F5F5F5   ← fond inputs
  white:        #FFFFFF

ACCENT — ambre chaud (actions critiques : "Terminer", CTA urgent)
  accent-700:   #D97706
  accent-500:   #F59E0B
  accent-100:   #FEF3C7

SÉMANTIQUES
  success:      #059669
  warning:      #D97706
  error:        #DC2626
  error-bg:     #FEF2F2
  allergy:      #B91C1C   ← réservé aux allergies (données médicales critiques)
  allergy-bg:   #FFF1F2
```

### 2.2 Typographie

Police : **Inter** (Google Fonts — libre, excellente lisibilité écran)  
Fallback : `system-ui, -apple-system, sans-serif`

```
display:    700  32px  line-height 1.2
headline:   700  24px  line-height 1.3
title:      600  18px  line-height 1.4
title-sm:   600  16px  line-height 1.4
body-lg:    400  16px  line-height 1.5
body:       400  14px  line-height 1.5
label:      500  13px  line-height 1.4
caption:    400  11px  line-height 1.4
```

**Règle :** toute information vitale (allergies, groupe sanguin, médicaments) est affichée en `body-lg` minimum.

### 2.3 Rayons et élévation

Design majoritairement **flat** (pas de fortes ombres portées). Les cartes et groupes d'informations ont des coins arrondis généreux. Les boutons et inputs suivent le même language arrondi. L'élévation est utilisée avec parcimonie — uniquement pour ce qui flotte physiquement (FAB, modals).

### 2.4 Iconographie

**Material Symbols Rounded** — style outline au repos, filled à l'état actif.

Icônes clés :

```
qr_code_scanner   → scanner (médecin)
qr_code           → afficher QR (patient)
folder_shared     → dossier médical
note_add          → ajouter note/ordonnance
check_circle      → terminer consultation
sync              → synchroniser
wifi_off          → hors-ligne
warning_amber     → allergie
person            → démographie patient
medical_services  → médecin/santé
medication        → médicaments
history           → historique
timer             → compte à rebours
lock              → sécurité/chiffrement
```

---

## 3. Contraintes non négociables

### 3.1 Accessibilité

- Cibles tactiles **≥ 48 dp** (Flutter) / **≥ 44 px** (PWA) pour toute action interactive.
- Contraste texte **WCAG 2.1 AA** minimum, en particulier sur fond coloré.
- Tout texte wrappé (`softWrap: true`) — jamais de troncature silencieuse sur l'info critique.
- Flutter : sections avec `Semantics(header: true)`, allergies avec `MergeSemantics` + label explicite.
- PWA : `role="region"` sur chaque section, `aria-label` sur tout bouton icône seul, `role="alert"` sur les erreurs.

### 3.2 Hiérarchie des informations du dossier médical

L'ordre des sections est **figé** (exigence de sécurité clinique) :

1. Informations (démographie)
2. **Allergies** — doit être visuellement distingué et immédiatement visible s'il y a des allergies
3. Pathologies chroniques
4. Médicaments en cours
5. Historique des consultations

Une allergie ne doit **jamais** être reléguée derrière un scroll sans indicateur visible.

### 3.3 Parcours médecin — mono-flux strict

Le parcours de consultation est linéaire : `Scan → Dossier → Édition → Terminer`.

**Interdit dans le cœur de consultation :**

- Menu hamburger, tiroir de navigation, barre d'onglets
- Écrans de réglages ou sous-menus insérés dans le flux
- Boîtes de dialogue en cascade

### 3.4 États hors-ligne — ton rassurant

Un état hors-ligne n'est **pas une erreur**. Il doit être exprimé avec la couleur `warning` (ambre) et un message rassurant — jamais en rouge, jamais comme un échec.

### 3.5 Microcopie (chaînes FR imposées)

```
Titre scan               : "Scanner le QR médical"
Titre dossier            : "Dossier médical"
Action ajouter           : "Ajouter une note / ordonnance"
Action terminer          : "Terminer"
Action synchroniser      : "Synchroniser" / "N en attente — synchroniser"
QR expiré                : "QR expiré — demandez un nouveau code au patient"
Serveur indisponible     : "Serveur indisponible — vérifiez la connexion"
Erreur déchiffrement     : "Erreur de déchiffrement — QR invalide"
Enregistré hors-ligne    : "Consultation enregistrée hors-ligne — synchro à la reconnexion"
Synchro réussie          : "N consultation(s) synchronisée(s)."
```

---

## 4. Écrans — ce qu'ils doivent communiquer

> L'IA choisit librement la mise en page, les composants, les animations.  
> Cette section décrit uniquement le **contenu**, les **états** et les **actions** de chaque écran.

---

### 4.1 Onboarding Patient — Étape Consentement

**Ce que l'utilisateur comprend à cet écran :**

- C'est une application de santé sécurisée, ses données restent sur son téléphone.
- Il doit accepter la politique de confidentialité pour continuer.

**Contenu :**

- Identité visuelle / logo de l'application
- Texte de politique de confidentialité (loi ivoirienne n°2013-450, chiffrement local, aucune donnée en clair)
- Un seul bouton d'action : `"J'accepte et je continue"` (key: `consent_accept`)

**États :** aucun état d'erreur possible sur cet écran.

---

### 4.2 Onboarding Patient — Étape Identité

**Ce que l'utilisateur comprend :**

- Ses informations ne quitteront jamais son téléphone en clair — message rassurant requis.
- Il doit renseigner son numéro CMU et son numéro de téléphone.

**Contenu :**

- Signal de confiance/sécurité visible (icône cadenas ou similaire, avec message court)
- Champ numéro CMU (key: `cmu_field`, hint: `CMU-2025-XXXXXX`, type: text)
- Champ téléphone (key: `phone_field`, hint: `+225 07 00 00 00 00`, type: phone)
- Bouton de validation : `"Créer mon compte"` (key: `create_account`)
- Zone d'affichage d'erreur (conditionnelle)

**États :**

- Idle : formulaire vide
- Erreur champs vides : message `"Veuillez remplir tous les champs."`
- Erreur keystore : message technique simplifié

---

### 4.3 Onboarding — Création en cours

**Ce que l'utilisateur comprend :**

- L'application génère sa clé de chiffrement, c'est normal que ça prenne quelques secondes.

**Contenu :**

- Indicateur de chargement
- Message rassurant : `"Sécurisation de votre compte…"` ou similaire
- Sous-texte : `"Génération de votre clé de chiffrement"` ou similaire

---

### 4.4 Écran Accueil Patient

**Ce que l'utilisateur comprend :**

- Il a deux actions possibles depuis cet écran.

**Contenu :**

- Identité visuelle de l'app
- Action principale : partager son dossier → génère un QR (navigue vers 4.5)
- Action secondaire : scanner un dossier (interface médecin) → navigue vers ScanScreen

---

### 4.5 Écran QR Patient

**Ce que l'utilisateur comprend :**

- Il doit présenter ce QR à son médecin.
- Le code expire, il doit surveiller le chrono.
- Il peut en générer un nouveau si expiré.

**Contenu — état QR affiché :**

- Image QR (260 dp minimum, fond blanc garanti)
- Compte à rebours en secondes :
  - > 60 s : ton neutre/rassurant (primary ou vert)
  - 30–60 s : ton d'attention (warning ambre)
  - < 30 s : ton urgent avec animation (pulsation) — jamais rouge pur
- Texte de guidage : `"Montrez ce code à votre médecin"`
- Mention sécurité : `"Valable 120 s · Partagez uniquement avec votre médecin"`

**Contenu — état chargement :**

- Indicateur de progression

**Contenu — état expiré :**

- Signal visuel clair (icône timer_off ou similaire)
- Message : `"Code expiré — Pour votre sécurité, générez un nouveau code."`
- Bouton : `"Nouveau code"`

**Contenu — état erreur :**

- Message d'erreur + bouton réessayer

---

### 4.6 Écran Scan QR (interface médecin, Flutter)

**Ce que l'utilisateur comprend :**

- Il doit viser le QR du patient avec sa caméra.
- Le traitement est en cours après le scan.

**Contenu :**

- Flux caméra plein écran
- Aide visuelle pour cadrer le QR (le style du cadre est libre)
- Titre : `"Scanner le QR médical"`
- Instruction de guidage
- Indicateur de traitement après scan (texte : `"Chargement du dossier…"`)

**Messages d'erreur (snackbar) :**

- QR expiré : chaîne §3.5
- Serveur off : chaîne §3.5
- Déchiffrement : chaîne §3.5

---

### 4.7 Écran Dossier Médical

**Ce que le médecin comprend :**

- Voici les informations médicales du patient, dans l'ordre critique.
- Il peut ajouter une note/ordonnance.
- Il peut terminer la consultation.
- Si des consultations sont en attente de synchro, c'est visible mais rassurant.

**Contenu de l'AppBar :**

- Titre `"Dossier médical"` + prénom patient si disponible
- Badge/bouton sync si `pendingCount > 0` : couleur `accent`, texte `"N en attente"`, action `_syncNow`
- Bouton `"Terminer"` : couleur `accent-700`, toujours visible

**Contenu du corps (sections, dans cet ordre impératif) :**

**Section Informations** (toujours affichée) :

- Prénom (`givenName`)
- Année de naissance (`birthYear`)
- Sexe (`sex`)
- Groupe sanguin (`bloodType`)

**Section Allergies** (uniquement si non vide — visuellement distinguée, couleur `allergy`) :

- Paires substance / sévérité — si sévérité = "sévère" : emphasis visuel
- Ne doit jamais disparaître derrière un scroll sans indicateur

**Section Pathologies chroniques** (si non vide) :

- Paires nom / code CIM-10

**Section Médicaments** (si non vide) :

- Paires médicament / dose · fréquence

**Section Consultations** (si non vide, du plus récent au plus ancien) :

- Date, résumé, ordonnance si présente

**Actions :**

- FAB : `"Ajouter une note / ordonnance"` → ConsultationEditScreen
- Timer idle 15 min → déclenche `_terminateSession` automatiquement

**États :**

- Terminaison en cours : overlay bloquant avec message `"Fermeture sécurisée…"`
- Hors-ligne après "Terminer" : snackbar `warning` avec chaîne §3.5
- Synchro en cours : indicateur sur le bouton sync
- Échec double (upload + queue) : snackbar `error` 8 s

---

### 4.8 Écran Édition — Note / Ordonnance

**Ce que le médecin comprend :**

- Il ajoute une note clinique libre et/ou une ordonnance structurée.
- L'enregistrement re-chiffre le dossier en mémoire.

**Contenu :**

- Champ note libre (multilignes, label `"Note de consultation"`, placeholder `"Observations, diagnostic…"`)
- Section ordonnance :
  - Liste de lignes (une par médicament) : médicament / dose / fréquence / durée en jours
  - Possibilité d'ajouter des lignes : `"+ Ajouter un médicament"`
  - Possibilité de retirer une ligne
- Zone d'erreur conditionnelle
- Bouton de validation : `"Enregistrer la consultation"`

**États :**

- Sauvegarde en cours : bouton avec indicateur de chargement, désactivé
- Erreur dossier plein : `"Dossier plein — impossible d'ajouter la note."`
- Erreur crypto : `"Chiffrement indisponible — réessayez plus tard."`
- Erreur générique : `"Échec de l'enregistrement — réessayez."`

---

## 5. Configuration technique Flutter (ThemeData)

L'IA doit créer `lib/src/design/app_theme.dart` avec un `ThemeData` Material 3 complet utilisant le système de couleurs et de typographie définis en §2.

Points obligatoires du thème :

- `useMaterial3: true`
- `ColorScheme` : `primary = #006C67`, `secondary = #D97706`, `error = #DC2626`, `surface = #FFFFFF`, `background = #F0FAFA`
- `TextTheme` : police Inter via `google_fonts`, échelle §2.2
- `AppBarTheme` : fond blanc, elevation 0, séparateur bas subtil
- `CardTheme` : elevation 0, bordure subtile, rayon généreux
- `InputDecorationTheme` : fond neutral-100, bordure focus primary-500
- `FilledButtonTheme` : fond primary-700, largeur maximale par défaut, hauteur ≥ 52 dp
- `FloatingActionButtonTheme` : fond primary-700, forme arrondie
- `SnackBarTheme` : floating, comportement et rayon cohérents
- `scaffoldBackgroundColor` : primary-50

Dépendances à ajouter dans `pubspec.yaml` :

```yaml
google_fonts: ^6.2.1
material_symbols_icons: ^4.2810.0
```

---

## 6. Configuration technique PWA

L'IA doit créer `src/design/tokens.css` avec toutes les couleurs (§2.1), la typographie (§2.2) et les espacements en variables CSS `--var-name`.

Import dans `index.html` :

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link
  href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
  rel="stylesheet"
/>
<link
  href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded"
  rel="stylesheet"
/>
<meta
  name="viewport"
  content="width=device-width, initial-scale=1, viewport-fit=cover"
/>
```

Architecture de navigation : **pas de router externe** — un simple `useState<Screen>` dans `app.tsx` suffit (le flux est linéaire : `scan → record → edit → terminating`). Les stubs de données pour le preview sont les bienvenus pour rendre le design visible sans backend.

---

## 7. Livrables attendus

### Flutter

- `lib/src/design/app_theme.dart`
- `lib/src/ui/home_screen.dart` _(nouveau)_
- `lib/src/ui/onboarding_screen.dart` _(refonte UI uniquement)_
- `lib/src/ui/qr_screen.dart` _(refonte UI uniquement)_
- `lib/src/ui/scan_screen.dart` _(refonte UI uniquement)_
- `lib/src/ui/record_view_screen.dart` _(refonte UI uniquement)_
- `lib/src/ui/consultation_edit_screen.dart` _(refonte UI uniquement)_
- `pubspec.yaml` _(ajout des dépendances design)_

### PWA Preact

- `src/design/tokens.css`
- `src/components/*.tsx` (AppBar, SectionCard, AllergySectionCard, InfoRow, SyncBadge, TerminateButton, SnackBar, Spinner)
- `src/screens/*.tsx` (ScanScreen, RecordScreen, EditScreen, TerminatingOverlay)
- `src/app.tsx` _(refonte avec router d'état + stubs de preview)_
- `index.html` _(fonts + viewport)_

### Critère de réussite

- `flutter run --target lib/main.dart` compile et affiche la nouvelle UI
- `npm run dev` dans `app-medecin/` affiche les 4 écrans navigables avec du contenu de preview
- Aucune régression sur `flutter test` et `npm test`
- La logique métier (services, crypto, controllers, `session.ts`) n'est pas modifiée
