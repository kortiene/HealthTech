# Protocole de test d'utilisabilité — interface médecin (< 5 min)

> **Issue porteuse :** [#28 — Affûtage UX médecin (prise en main < 5 min)](../../BACKLOG.md) · Épic **E4 — Performance & UX** · label `ux`.
> **Preuve visée :** critère d'acceptation NFR UX ([`PRD_HealthTech.md`](../../PRD_HealthTech.md) §5) — « Un médecin non formé réalise une consultation complète en < 5 min lors d'un test utilisateur ».
> **Norme de conception liée :** [`medecin-ux-guidelines.md`](./medecin-ux-guidelines.md).
> **Statut :** **document reproductible** prêt à l'emploi. Les **mesures terrain** restent une
> **démarche humaine** non close par cette issue — même discipline d'honnêteté que le dossier
> d'homologation (#30) et le périmètre pentest (#25). Voir §8 (gabarit de compte-rendu, statut
> « à produire »).

Ce protocole cadre une campagne de tests d'utilisabilité menée **par des humains** avec de
**vrais médecins**. #28 livre l'instrument (protocole + outillage de mesure + garde-fou
anti-régression) ; il ne réalise pas la campagne. Les résultats seront collectés lors de
**#31 (pilote Abidjan)** ou d'une campagne dédiée, puis consignés au gabarit du §8.

---

## 1. Objectif & hypothèse mesurable

- **Objectif :** vérifier qu'un médecin **non formé au produit** réalise une **consultation
  complète** en **moins de 5 minutes**.
- **Définition de « consultation complète » :** les **4 étapes du parcours canonique**
  (`scan` → `read` → `edit` → `terminate`, cf. [guide UX §2](./medecin-ux-guidelines.md#2-parcours-canonique-de-référence))
  aboutissant à un **dossier mis à jour observable** (note/ordonnance ajoutée, session terminée).
- **Hypothèse :** médiane du temps-tâche < 5 min **et** ≥ 80 % des participants sous le seuil,
  **sans échec** sur les étapes vitales.
- **Début du chrono :** présentation du QR patient (le médecin lance le `scan`).
  **Fin du chrono :** confirmation visible de fin de session (wipe, retour à l'écran de scan).

---

## 2. Panel

- **Profil :** médecins généralistes, **non formés** au produit, représentatifs du persona
  **Dr. Koné** (forte cadence patient, contexte ivoirien).
- **Taille d'échantillon :** **5 à 8 participants** — taille recommandée pour un test
  d'utilisabilité qualitatif (au-delà de ~5, le rendement marginal en détection de problèmes
  majeurs décroît ; 8 donne une marge sur les no-shows). Justifier tout écart.
- **Recrutement :** hors relation hiérarchique avec l'équipe produit (biais de complaisance) ;
  aucun participant n'a co-conçu l'interface.

---

## 3. Environnement de test

- **Appareil de référence :** smartphone **bas de gamme** (type Infinix, cf. **#29**), stockage
  quasi saturé pour être réaliste.
- **Réseau :** lien **3G/Edge simulé**. Aligner le profil sur le **`3G-STABLE`** documenté pour
  la performance (#27, [`docs/perf/decryption-budget.md`](../perf/decryption-budget.md) :
  ~750 kbit/s, ~150 ms RTT) afin que le déchiffrement < 3 s soit représentatif.
- **Surface testée :** préciser **Flutter de référence** (`app-patient`) **ou** PWA
  (`app-medecin`) — la PWA n'est éligible qu'une fois son flux de consultation porté
  (#17/#21/#22). Voir *Risks* de la spec #28.
- **Données :** **synthétiques uniquement** — aucun dossier patient réel, aucune PII réelle
  (persona « Awa », allergie Pénicilline, cf. jeu de test host). Conforme à la résidence des
  données (ARTCI / loi n°2013-450) : aucun artefact contenant de la PII réelle ne quitte le
  territoire ni n'est stocké.

---

## 4. Scénario scripté

Consigne au facilitateur : **ne pas guider** ; noter hésitations, erreurs, verbatims ;
n'intervenir qu'en cas de blocage total (marqué comme échec de tâche).

1. « Un patient se présente et vous montre son QR code. **Scannez-le.** » *(étape `scan`)*
2. « **Consultez** son dossier. Quelles sont ses allergies ? » *(étape `read` — vérifie que
   l'info vitale est trouvée sans effort ; cf. hiérarchie §3 du guide).*
3. « **Ajoutez** une note de consultation et une ordonnance (paludisme : Artéméther-luméfantrine,
   3 jours). » *(étape `edit`)*
4. « **Terminez** la consultation. » *(étape `terminate`)*

Ce qui est **chronométré** : du début de l'étape 1 (scan) à la confirmation de l'étape 4.

---

## 5. Instruments de mesure

- **Temps-tâche** : chronométrage par étape et total. Instrument logiciel optionnel :
  [`task_timing.dart`](../../app-patient/lib/src/doctor/task_timing.dart) (durées + labels
  d'étape uniquement ; **jamais de PII/donnée médicale/clé** — voir §6). Export CSV/JSON de
  durées anonymes exploitable par le §8.
- **SUS (System Usability Scale)** — questionnaire 10 items, **traduit en français**, administré
  après la session (score 0–100).
- **Taux de succès/échec par tâche** (4 tâches du §4).
- **Comptage d'erreurs et d'hésitations** (observateur).
- **Verbatims** (notes libres, anonymisées).

---

## 6. Éthique & confidentialité

- **Consentement** éclairé des participants **avant** la session, aligné sur la politique de
  consentement participants (#7) — **distinct** du consentement patient produit.
- **Aucune captation** de PII ni de donnée médicale réelle ; données de session **anonymisées**
  (identifiant participant = code opaque, ex. `P01`).
- **Aucun enregistrement** ne contient de payload QR, de clé de session, ni de contenu de dossier.
- **Résidence :** tout artefact de campagne (chronos, scores, verbatims) reste sur le territoire
  et conforme au registre des traitements (#5).
- L'instrument de chronométrage respecte le **contrat de sécurité** du guide UX
  ([§9](./medecin-ux-guidelines.md#9-instrumentation-temps-tâche-contrat)), prouvé par le test de
  redaction.

---

## 7. Critères de réussite

| Critère | Seuil |
|---------|-------|
| Temps-tâche total (médiane) | **< 5 min** |
| Participants sous le seuil | **≥ 80 %** |
| Échec sur une étape **vitale** (`scan`, `read` allergie, `terminate`) | **0** |
| Score SUS moyen | **≥ 75** (cible « bon », à confirmer) |

Un résultat sous ces seuils déclenche une itération UX (guidée par le guide §1–§8) puis un
re-test, avant de considérer la NFR UX satisfaite.

---

## 8. Gabarit de compte-rendu

> **Statut :** **à produire** — aucune campagne n'a encore eu lieu. Ce gabarit n'affirme aucun
> résultat tant que les mesures terrain ne sont pas collectées (#31 / campagne dédiée).

```
Campagne : <date> · Surface : <Flutter de référence | PWA> · Facilitateur : <code>
Appareil : <modèle bas de gamme> · Réseau : 3G-STABLE simulé (#27)

Participants : N=<5–8>
| ID  | Temps total | scan | read | edit | terminate | SUS | Échecs | Notes |
| P01 | mm:ss       | ...  | ...  | ...  | ...       | ..  | ...    | ...   |
| ... |             |      |      |      |           |     |        |       |

Synthèse :
- Médiane temps-tâche : mm:ss (seuil < 5:00 : PASS/FAIL)
- % sous le seuil : xx % (seuil ≥ 80 % : PASS/FAIL)
- SUS moyen : xx (cible ≥ 75 : PASS/FAIL)
- Échecs sur étapes vitales : n (seuil 0 : PASS/FAIL)

Problèmes UX observés (rattachés au guide §) → actions correctives :
- ...

Conclusion NFR UX : <SATISFAITE | ITÉRATION REQUISE> — décision humaine, tracée vers #31.
```

---

## 9. Traçabilité

- **PRD §5** (NFR UX) → ce protocole + [guide UX](./medecin-ux-guidelines.md).
- **#31 (pilote Abidjan)** consommera ce protocole (mutualisation possible avec le pilote pour
  éviter la duplication d'effort terrain).
- **#29 (bas de gamme)** valide l'environnement de test (appareil de référence).
- Le **garde-fou anti-régression** automatisé (`test/ux/` côté Flutter, `walkthrough.test.ts`
  côté PWA, `just ux-check`) protège le parcours **entre** deux campagnes terrain coûteuses ;
  il n'en est **pas** un substitut.
