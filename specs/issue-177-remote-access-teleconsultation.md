# Accès distant téléconsultation — lien éphémère fragment URL (issue #177)

## Problem Statement

Le flux actuel exige une proximité physique : le médecin doit scanner physiquement le QR du patient.
Pour une téléconsultation (spécialiste distant, urgence nocturne), ce flux est bloquant. L'issue #177
introduit un **deuxième mode d'accès** : le patient génère un lien éphémère 120 s qu'il envoie par
SMS, WhatsApp ou e-mail. Le médecin clique et ouvre le dossier dans sa PWA sans scan caméra.

## Goals

1. Patient : bouton "Envoyer à distance" dans l'écran QR, avec dialog de confirmation explicite.
2. Patient : partage du lien via le plugin `share_plus` (SMS, WhatsApp, e-mail, …).
3. Médecin : la PWA détecte au montage un fragment URL `#<payload>` sur la route `/access` et
   déchiffre le dossier sans caméra — même flux que le scan QR.
4. Backend : audit log `uuid + timestamp + IP` sur chaque `GET /blob/:uuid` (sans jamais logguer
   la clé — invariant ZK maintenu).
5. Invariant zero-knowledge préservé : la clé de session est **uniquement** dans le fragment URL
   (jamais transmise au serveur selon la spec RFC 3986).

## Non-Goals

- Blob one-time HTTP 410 : incompatible avec le flux de sync patient (`_syncFromCloud` fait aussi
  `GET /blob/:uuid`). Marqué TODO dans le backend, à traiter séparément si un endpoint dédié est créé.
- Transcodage audio côté backend (WebM → AAC) : #176.
- Modification de la politique de rétention des blobs : #114.

## Relevant Repository Context

- `app-patient/lib/src/qr/access_token.dart` : `QrPayload.toQrString()` sérialise le payload JSON.
  `toLinkFragment()` wrappera la même sérialisation en base64url dans le fragment.
- `app-patient/lib/src/ui/qr_screen.dart` : `_QrView` affiche le QR + countdown. Le bouton
  "Envoyer à distance" y sera ajouté.
- `app-medecin/src/screens/ScanScreen.tsx` : `handleQrData()` contient toute la logique
  parse → fetch → decrypt. Elle sera extraite dans `src/lib/processQrPayload.ts`.
- `app-medecin/src/app.tsx` : gestion d'état `Screen`. Un `useEffect` sur le montage détectera
  le hash et appellera `processQrPayload`.
- `backend/src/main.rs` : `get_blob` — ajout du log audit.
- Caddy (Dockerfile app-medecin) : `try_files {path} /index.html` déjà en place → la route
  `/access` sert déjà `index.html`. Pas de configuration serveur supplémentaire nécessaire.
- Service Worker (workbox) : ne cache jamais `/blob/*` ni `/media/*` (NetworkOnly) — inchangé.

## Proposed Implementation

### `app-patient/lib/src/qr/access_token.dart`

```dart
/// Generates a remote-access link for teleconsultation (#177).
/// The payload is base64url-encoded (no padding) in the URL fragment —
/// it is NEVER sent to the server (RFC 3986 §3.5).
String toLinkFragment(String doctorPwaUrl) {
  final encoded = base64Url.encode(utf8.encode(toQrString())).replaceAll('=', '');
  return '$doctorPwaUrl/access#$encoded';
}
```

### `app-patient/lib/src/ui/qr_screen.dart`

- Ajouter `final String? doctorPwaUrl` à `QrScreen`.
- Dans `_buildBody()`, calculer `linkFragment` depuis `_payload?.toLinkFragment(doctorPwaUrl)`.
- Dans `_QrView`, ajouter `final String? linkFragment` et le bouton "Envoyer à distance" conditionnel.
- Dialog de confirmation `_RemoteSendConfirmDialog`.
- `Share.share(message)` de `package:share_plus/share_plus.dart`.

### `app-patient/lib/src/ui/main_shell.dart`

- Ajouter `final String? doctorPwaUrl` et passer à `QrScreen`.

### `app-patient/lib/main.dart` + `main_dev.dart`

- Ajouter `_kDoctorPwaUrl` (staging / dev) et passer à `MainShell`.

### `app-medecin/src/lib/processQrPayload.ts` (NEW)

- `QrPayload` interface (déplacée depuis `ScanScreen.tsx`).
- `QrScanResult` interface.
- `decodeQrLinkFragment(fragment: string): string` — base64url sans padding → JSON string.
- `processQrPayload(raw: string): Promise<QrScanResult>` — logique extraite de `handleQrData`.

### `app-medecin/src/screens/ScanScreen.tsx`

- Importer `{ processQrPayload, type QrPayload }` depuis `../lib/processQrPayload`.
- Re-exporter `QrPayload` pour compatibilité ascendante (`app.tsx`).
- Remplacer le corps de `handleQrData` par un appel à `processQrPayload`.

### `app-medecin/src/app.tsx`

- Importer `processQrPayload`, `decodeQrLinkFragment`.
- Ajouter `useState<string | null>(null)` pour `accessError`.
- Ajouter `"access-loading"` au type `Screen`.
- `useEffect` sur le montage : si `window.location.hash` présent → décoder → appeler
  `processQrPayload` → transitionner vers `"record"` ou afficher une `SnackBar` d'erreur.
- Nettoyer le hash de l'URL via `history.replaceState` avant de traiter.

### `backend/src/main.rs`

- Extraire `client_ip: Option<IpAddr>` avant le rate-limit check.
- Ajouter `tracing::info!(target: "audit", ...)` sur le `Ok(Some(...))` de `get_blob`.
- Jamais logguer la clé, le payload déchiffré ou le corps de la requête.

## Affected Files / Packages / Modules

| Fichier | Type |
|---|---|
| `specs/issue-177-remote-access-teleconsultation.md` | NEW (ce fichier) |
| `app-patient/pubspec.yaml` | MODIFY — add share_plus |
| `app-patient/lib/main.dart` | MODIFY — _kDoctorPwaUrl |
| `app-patient/lib/main_dev.dart` | MODIFY — _kDoctorPwaUrl |
| `app-patient/lib/src/ui/main_shell.dart` | MODIFY — doctorPwaUrl field |
| `app-patient/lib/src/qr/access_token.dart` | MODIFY — toLinkFragment() |
| `app-patient/lib/src/ui/qr_screen.dart` | MODIFY — bouton + dialog |
| `app-medecin/src/lib/processQrPayload.ts` | NEW |
| `app-medecin/src/screens/ScanScreen.tsx` | MODIFY — refactor |
| `app-medecin/src/app.tsx` | MODIFY — hash detection |
| `backend/src/main.rs` | MODIFY — audit log |
| `app-patient/test/qr/access_token_test.dart` | MODIFY — toLinkFragment tests |
| `app-medecin/src/lib/processQrPayload.test.ts` | NEW |

## API / Interface Changes

- `QrPayload` : nouvelle méthode `toLinkFragment(String doctorPwaUrl)`.
- `QrScreen` : nouveau paramètre optionnel `String? doctorPwaUrl`.
- `MainShell` : nouveau paramètre optionnel `String? doctorPwaUrl`.
- PWA médecin : nouvelle route `/access#<fragment>` gérée côté client.
- Backend : nouveau log `target: "audit"` sur `GET /blob/:uuid` (pas de changement de l'API HTTP).

## Data Model / Protocol Changes

Aucun changement au format du blob chiffré ni au schéma de base de données.

Le fragment URL transporte le même JSON que `toQrString()`, simplement encodé en base64url sans padding.
Format : `https://<pwa_domain>/access#<base64url_nopad(toQrString())>`.

## Security & Compliance Considerations

- **ZK invariant** : le fragment `#…` n'est **jamais** transmis au serveur (RFC 3986 §3.5).
  La clé de session est uniquement côté client. ✓
- **TTL 120 s** : identique au QR. `exp` est dans le payload, vérifié par la PWA médecin. ✓
- **Write token** : inclus dans le fragment pour les sessions `readWrite` (même comportement que
  le QR). Le médecin présente `Authorization: Bearer {wt}` sur PUT. ✓
- **Consentement patient explicite** : dialog de confirmation avant le partage. ✓
- **Audit log** : `uuid + timestamp + IP` loggués côté backend. Jamais la clé ni le contenu. ✓
- **Risque résiduel** : le lien peut être transféré par le médecin (vs QR qui implique la proximité).
  Mitigations : TTL 120 s, dialog de confirmation, audit log IP.
- **Historique navigateur** : le fragment `#…` peut être dans l'historique du navigateur du médecin
  après utilisation. La PWA nettoie le hash avec `history.replaceState` avant traitement. ✓
- **Un seul traitement** : `history.replaceState` empêche le retraitement sur refresh. ✓

## Testing Plan

- `access_token_test.dart` : round-trip `toLinkFragment` → décode → JSON équivalent à `toQrString()`.
- `processQrPayload.test.ts` : validation JSON invalide, `v != 1`, champs manquants, expiry passé.
  Helper `decodeQrLinkFragment` round-trip.
- `qr_screen_test.dart` (existant) : pas de régression — `doctorPwaUrl` est optionnel, tests
  existants ne le passent pas → bouton absent → comportement inchangé.
- `walkthrough.test.ts` (existant) : `useEffect` mocké → hash check ne s'exécute pas → pas de régression.

## Documentation Updates

Aucune mise à jour du BACKLOG ou des ADRs requise — la décision de base (fragment URL ZK) est
documentée dans l'issue et dans ce spec.

## Risks and Open Questions

1. **blob one-time (HTTP 410)** : non implémenté car incompatible avec le flux patient
   `_syncFromCloud`. À traiter dans une issue dédiée avec un endpoint `/session/:uuid` distinct.
2. **share_plus version** : `^10.0.0` utilisé. Si indisponible à la résolution, passer à `^9.0.0`.
3. **URL du doctor PWA** : `_kDoctorPwaUrl` est codé en dur (staging). En production, cette valeur
   doit être injectée via les variables d'environnement SOPS (ADR 0007) — à prévoir en #114 ou
   dans l'ADR prod.

## Implementation Checklist

- [x] Spec créé
- [ ] `access_token.dart` — `toLinkFragment()`
- [ ] `pubspec.yaml` — `share_plus`
- [ ] `qr_screen.dart` — bouton + dialog
- [ ] `main_shell.dart` — `doctorPwaUrl`
- [ ] `main.dart` + `main_dev.dart` — `_kDoctorPwaUrl`
- [ ] `processQrPayload.ts` — NEW
- [ ] `ScanScreen.tsx` — refactor + re-export
- [ ] `app.tsx` — hash detection
- [ ] `backend/src/main.rs` — audit log
- [ ] Tests `access_token_test.dart`
- [ ] Tests `processQrPayload.test.ts`
- [ ] `dart format` OK
- [ ] `flutter analyze` OK
- [ ] `npm run typecheck` / vitest OK
- [ ] `cargo fmt --check` OK
