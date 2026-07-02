# Guide UX de l'interface médecin (normatif)

> **Issue porteuse :** [#28 — Affûtage UX médecin (prise en main < 5 min)](../../BACKLOG.md) · Épic **E4 — Performance & UX** · Jalon **M4** · label `ux`.
> **Implémente :** NFR UX ([`PRD_HealthTech.md`](../../PRD_HealthTech.md) §5 — « L'application du médecin doit pouvoir être prise en main avec moins de 5 minutes de formation, interface ultra-épurée, pas de menus complexes »).
> **Décision d'architecture liée :** [ADR 0002 — Interface médecin : PWA installable](../adr/0002-doctor-interface-pwa.md) (« learnable in < 5 minutes », « ultra-simple single-flow UI »).
> **Langue faisant foi :** **français** (marché ivoirien). Aucune i18n multi-langues (hors périmètre).
> **Statut :** norme **opposable**. Toute PR touchant l'UI médecin (surface Flutter de référence `app-patient/` **ou** PWA `app-medecin/`) doit passer la [checklist de revue UX](#9-checklist-de-revue-ux) de ce document.

Ce guide est la **source unique de vérité** UX pour l'interface médecin. Les deux surfaces
qui la matérialisent — l'implémentation Flutter de référence (`app-patient/lib/src/ui/`,
host-testable, #17–#22) et la PWA de production (`app-medecin/`, ADR 0002, dont le flux de
consultation arrive avec #17/#21/#22) — s'y réfèrent et ne doivent pas diverger. Ce que ce
guide **n'est pas** : il ne modifie ni la cryptographie, ni le format de blob, ni le protocole
réseau, ni le modèle de menace (#28 est purement UX/outillage).

---

## 1. Principe directeur : mono-flux « zéro menu »

Le cœur de la consultation est **un seul parcours linéaire**, du scan à la fin de session.

**Interdit** dans le cœur de consultation :

- menus hamburger, tiroirs de navigation (drawers), barres d'onglets ;
- écrans de réglages/préférences insérés dans le flux ;
- navigation hiérarchique imbriquée (« Menu → Sous-menu → Action ») ;
- boîtes de dialogue en cascade, confirmations superflues.

**Autorisé**, mais **périphérique et non bloquant** :

- actions secondaires attachées à l'écran courant (ex. « Synchroniser » dans l'AppBar,
  badge « N en attente ») — elles n'interrompent jamais le parcours principal ;
- retour arrière système (bouton matériel / geste), qui reste cohérent avec le flux.

**Justification.** Le persona Dr. Koné voit ~30 patients/jour ; chaque friction cognitive et
chaque seconde comptent. Un parcours unique, prévisible, sans arborescence à mémoriser, est la
condition du « < 5 min sans formation ».

---

## 2. Parcours canonique de référence

Le parcours canonique compte **4 étapes** et **3 écrans**. C'est la **ligne de base** contre
laquelle tout ajout futur est évalué (voir le budget d'étapes, §7).

| # | Étape (label machine) | Écran | Interaction minimale du médecin |
|---|-----------------------|-------|---------------------------------|
| 1 | `scan`      | Scanner le QR (`scan_screen.dart`)        | **Viser** le QR patient (aucune saisie). |
| 2 | `read`      | Dossier médical (`record_view_screen.dart`) | **Lire** — l'info vitale est en tête, sans défilement. |
| 3 | `edit`      | Note / ordonnance (`consultation_edit_screen.dart`) | **Un appui** sur le FAB → formulaire rapide → **Valider**. |
| 4 | `terminate` | Retour au dossier → action « Terminer »   | **Un appui** sur « Terminer » → rechiffrement + envoi/enqueue + wipe → confirmation. |

- Les libellés machine `scan` / `read` / `edit` / `terminate` sont **figés** et partagés par le
  garde-fou de parcours (§7) et l'instrumentation temps-tâche (§8). Source de vérité :
  [`app-patient/lib/src/doctor/ux_budget.dart`](../../app-patient/lib/src/doctor/ux_budget.dart)
  (`UxBudget.canonicalSteps`).
- **Budget d'étapes / d'écrans** (`UxBudget.maxConsultationSteps` = 4,
  `UxBudget.maxConsultationScreens` = 3). Ajouter une étape ou un écran au cœur de consultation
  **exige** de relever explicitement le budget (donc une revue consciente) — le garde-fou échoue
  sinon.

---

## 3. Hiérarchie de l'information critique

L'ordre et la proéminence des sections du dossier sont **normatifs**. L'information
**vitale pour la sécurité du soin** passe avant tout le reste :

1. **Informations** (démographie minimale : prénom, année de naissance, sexe, groupe sanguin).
2. **Allergies** — **jamais « sous le pli » sans indicateur**. Une allergie sévère doit être
   perceptible sans défilement.
3. **Pathologies chroniques.**
4. **Médicaments** en cours.
5. **Consultations** (historique, du plus pertinent au plus ancien).

- L'ordre ci-dessus est figé dans `UxBudget.criticalSectionOrder` et vérifié par le test
  d'invariants UX (§7). L'implémentation Flutter de référence
  ([`record_view_screen.dart`](../../app-patient/lib/src/ui/record_view_screen.dart)) le respecte
  déjà ; la PWA devra le respecter à l'arrivée du flux.
- **Règle de sécurité clinique :** allergies et pathologies chroniques précèdent toujours
  l'historique de consultation. Ne jamais reléguer une allergie derrière une section optionnelle.

---

## 4. Ergonomie clinique

Contraintes minimales pour un usage debout, à une main, en plein jour, sur appareil bas de gamme :

- **Cibles tactiles ≥ 48 dp (Android/Flutter) / ≥ 44 px (web/PWA)** pour toute action.
- **Contraste AA minimum** (WCAG 2.1) sur texte et icônes d'action.
- **Typographie lisible en plein jour** : pas de gris clair sur blanc pour l'info critique.
- **Utilisabilité à une main** : les actions primaires (FAB « Ajouter », « Terminer ») restent
  atteignables ; pas d'action vitale reléguée en haut-gauche hors de portée du pouce.
- **Aucune dépendance au survol** (`hover`) ni au clic droit — inutilisables au doigt.
- **Aucune saisie superflue** : le scan ne demande aucune frappe ; le formulaire d'édition est
  minimal (note libre + lignes d'ordonnance).

L'approfondissement accessibilité et la validation sur appareil de référence relèvent de **#29**
(`ux` `tech-debt`). #28 pose les invariants ; #29 les mesure sur device.

---

## 5. Microcopie française

Registre professionnel, **ton orienté action**, vocabulaire médical local. Règle d'or pour tout
message d'erreur ou d'état : **« message = cause + action à faire »** (modèle repris de
[`scan_screen.dart`](../../app-patient/lib/src/ui/scan_screen.dart) `_errorMessage`).

### Catalogue des chaînes clés (source de vérité)

| Contexte | Chaîne (FR) |
|----------|-------------|
| Titre — scan | « Scanner le QR médical » |
| Titre — dossier | « Dossier médical » |
| Action — ajouter | « Ajouter une note / ordonnance » |
| Action — terminer | « Terminer » |
| Action — synchroniser | « Synchroniser » / « N en attente — synchroniser » |
| Erreur — QR expiré | « QR expiré — demandez un nouveau code au patient » |
| Erreur — session introuvable | « Session introuvable — QR peut-être expiré » |
| Erreur — serveur | « Serveur indisponible — vérifiez la connexion » |
| Erreur — déchiffrement | « Erreur de déchiffrement — QR invalide » |
| État — enregistré hors-ligne | « Consultation enregistrée hors-ligne — synchro à la reconnexion » |
| Confirmation — synchro | « N consultation(s) synchronisée(s). » |

Ces chaînes existent déjà côté Flutter. Le test d'invariants UX (§7) vérifie la présence des
**libellés d'action clés** (« Ajouter une note / ordonnance », « Terminer ») et l'absence de
menu. Toute nouvelle chaîne suit la même règle cause+action.

---

## 6. Feedback d'état obligatoire

L'UX doit **rendre visibles** les états de sécurité du modèle zero-knowledge — sans jamais les
contourner :

- **Compte à rebours QR (~120 s)** côté patient (#16) : l'expiration est claire et guide vers un
  nouveau code (déjà présent dans le message d'erreur de scan).
- **Déchiffrement (< 3 s, #27)** : indicateur de progression pendant `fetchAndDecrypt` ; jamais
  d'écran vide sans retour.
- **Hors-ligne / « N en attente »** : état **rassurant, jamais un rouge d'erreur** pour un simple
  hors-ligne — « Consultation enregistrée hors-ligne — synchro à la reconnexion » (#21/#22).
- **Wipe / fin de session** : la fin de session (#19) est **visiblement confirmée** (overlay de
  traitement puis fermeture) ; l'UX ne doit pas donner l'illusion qu'un dossier reste ouvert
  après « Terminer ».
- **Médias lourds** : présentés comme **liens éphémères** (#23), jamais mis en cache local
  d'image.

---

## 7. Gestion des erreurs

**Chaque erreur mappe une action de récupération.** Modèle de référence :
`scan_screen.dart._errorMessage` (switch exhaustif `ExpiredQrCode` / `BlobNotFound` /
`BackendUnavailable` / `DecryptError` → message cause+action). Une erreur inconnue tombe sur un
message générique sûr (« Erreur inattendue ») sans fuite technique.

- Ne jamais afficher de **trace technique**, d'exception brute, de payload QR ni d'identifiant
  interne à l'écran.
- Un échec réseau **non bloquant** (hors-ligne) n'est **pas** une erreur : c'est un état
  rassurant (§6).
- Le seul cas d'alerte « forte » est la perte potentielle de données (upload **et** file locale
  échouent — `OfflineQueueUnavailable`), signalée explicitement (déjà câblé).

---

## 8. Anti-patterns explicitement bannis

- Boîtes de dialogue en cascade / confirmations superflues (« Êtes-vous sûr ? » redondants).
- Réglages avancés ou options techniques **dans** le flux de consultation.
- Jargon technique visible (noms de classes, codes d'erreur, stack traces, UUID bruts).
- Menus imbriqués, hamburger, onglets pour le cœur de consultation (§1).
- Rouge d'erreur pour un simple état hors-ligne.
- Toute étape qui **maintient une référence au dossier déchiffré** au-delà de la session, ou qui
  empêche le wipe RAM / le reload-to-drop-heap de la PWA (ADR 0002).
- Toute journalisation de donnée médicale en clair, de clé, de payload QR ou de PII (voir la
  norme de l'instrumentation temps-tâche, ci-dessous).

---

## 9. Instrumentation temps-tâche (contrat)

L'utilitaire de mesure de durée des étapes de test utilisateur
([`task_timing.dart`](../../app-patient/lib/src/doctor/task_timing.dart)) a un **contrat de
sécurité dur** que toute contribution doit préserver :

- il n'accepte que les **libellés d'étape canoniques** (`scan`, `read`, `edit`, `terminate`) et
  des **durées en millisecondes** ;
- il **ne journalise / n'exporte jamais** de donnée médicale, de clé, de payload QR ni de PII ;
- il est **désactivé par défaut** (`enabled == false`) — activable uniquement en mode test ;
- sa sortie (CSV/JSON) ne contient que des labels d'étape + des entiers.

Ce contrat est prouvé par le **test de redaction** (`task_timing_test.dart`). Le proxy temps-tâche
**machine** produit par le garde-fou (§ ci-dessous) est un **signal de régression**, jamais une
**preuve** du « < 5 min » humain — celle-ci vient du [protocole de test utilisateur](./usability-test-protocol.md).

---

## 10. Checklist de revue UX

À dérouler pour **toute PR** modifiant l'UI médecin (à intégrer au `review_phase`) :

- [ ] **Mono-flux préservé** : aucun menu hamburger / drawer / onglet ajouté au cœur de consultation (§1).
- [ ] **Budget respecté** : le parcours canonique reste ≤ `UxBudget.maxConsultationSteps` étapes et
      ≤ `UxBudget.maxConsultationScreens` écrans ; tout dépassement relève **explicitement** le
      budget avec justification (§2, §7-code).
- [ ] **Hiérarchie critique** : allergies/pathologies avant l'historique ; aucune allergie « sous le
      pli » sans indicateur (§3).
- [ ] **Ergonomie clinique** : cibles ≥ 48 dp/44 px, contraste AA, pas de dépendance au survol (§4).
- [ ] **Microcopie FR** : nouvelles chaînes en français, règle cause+action pour erreurs/états (§5).
- [ ] **Feedback d'état** : déchiffrement, hors-ligne rassurant, confirmation de wipe présents (§6).
- [ ] **Erreurs actionnables** : chaque erreur mappe une action ; aucune fuite technique (§7).
- [ ] **Anti-patterns** : aucun de la liste §8.
- [ ] **Sécurité** : rien ne journalise/persiste de plaintext, clé, payload QR ou PII ; le contrat de
      l'instrumentation (§9) est intact.
- [ ] **Garde-fou vert** : `just ux-check` passe ; `flutter test` (dont `test/ux/`) et `npm test`
      (PWA) restent verts.
