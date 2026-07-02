# Protocole de validation — accessibilité & robustesse bas de gamme

> **Issue porteuse :** [#29 — Accessibilité & robustesse sur smartphones d'entrée de gamme](../../BACKLOG.md) · Épic **E4 — Performance & UX** · Jalon **M4** · labels `ux` `tech-debt`.
> **Preuve visée :** critère d'acceptation #29 — « **parcours patient et médecin validés sur appareil de référence bas de gamme** ».
> **Appareil de référence :** [`low-end-device-profile.md`](./low-end-device-profile.md).
> **Statut :** **document reproductible** prêt à l'emploi. Les **mesures terrain** (deux parcours sur l'appareil Infinix réel, injection de coupures) restent une **démarche humaine** non close par cette issue — même discipline d'honnêteté que le pentest (#25), l'homologation (#30) et l'utilisabilité (#28). Voir §8 (gabarit, statut « à produire »).

Ce protocole cadre une validation menée **par des humains** sur **matériel réel**. #29 livre
l'instrument (profil + protocole + garde-fous anti-régression CI) ; il ne réalise pas la campagne.
Les résultats seront collectés lors de **#31 (pilote Abidjan)** ou d'une campagne dédiée
(mutualisable avec #28), puis consignés au gabarit du §8. Symétrique du
[protocole d'utilisabilité](./usability-test-protocol.md) (#28), mais orienté **robustesse +
accessibilité** et couvrant **les deux parcours**.

---

## 1. Objectif & critère mesurable

- **Objectif :** vérifier que les deux parcours se complètent **sans perte de données** et restent
  **utilisables** sur l'appareil de référence **saturé**, **sous coupures**.
- **Parcours patient :** onboarding (compte chiffré) → génération QR d'accès → sauvegarde du dossier.
- **Parcours médecin :** `scan` → `read` (info vitale en tête) → `edit` (note/ordonnance) →
  `terminate` (rechiffrer + envoyer/enqueue + wipe).
- **Critère :** les deux parcours aboutissent à un **état observable cohérent** (dossier à jour ou
  consultation « en attente de synchro »), **sans perte silencieuse** et **sans doublon**, même
  après saturation disque et interruption brutale.

---

## 2. Environnement de test

- **Appareil :** appareil de référence (§1 du [profil](./low-end-device-profile.md)) — type Infinix
  32 Go, RAM 2–3 Go, API min.
- **Stockage :** amené à l'espace libre cible **« quasi saturé »** (< 500 Mo) selon le profil.
- **Réseau :** lien **3G/Edge simulé**, profil **`3G-STABLE`** (#27,
  [`docs/perf/decryption-budget.md`](../perf/decryption-budget.md)).
- **Données :** **synthétiques uniquement** — aucune PII ni donnée médicale réelle (persona « Awa »,
  allergie Pénicilline). Conforme à la résidence des données (ARTCI / loi n°2013-450).

---

## 3. Scénario « stockage saturé »

1. Amener l'appareil à l'espace libre cible (< 500 Mo) — remplir avec des fichiers synthétiques.
2. Exécuter le parcours patient puis médecin de bout en bout.
3. **Vérifier :**
   - l'app reste **réactive** (pas de blocage / ANR) ;
   - un échec d'écriture locale (« disque plein ») **échoue proprement** : l'enqueue hors-ligne
     lève `OfflineQueueUnavailable`, la session est **wipée quand même**, et l'UI **alerte fort**
     (jamais une perte silencieuse) ;
   - **rien de sensible** n'est écrit sur disque (plaintext, clé de session, payload QR) ;
   - l'empreinte de la file reste bornée (`StorageBudget.maxQueueFootprintBytes`).

---

## 4. Scénario « micro-coupure »

Injecter une interruption brutale (retrait batterie / kill process) à des **points critiques** :

| Point d'interruption | Invariant à vérifier au redémarrage |
|----------------------|-------------------------------------|
| Pendant le chiffrement (avant PUT) | Aucun plaintext/clé résiduel ; rien n'a été perdu de façon incohérente. |
| Pendant le PUT réseau | `put` **puis** `remove` : l'item reste en file, re-PUT au prochain drain (UUID idempotent) → **pas de doublon**. |
| Entre `put` et `remove` | Idem : livraison **at-least-once** + PUT idempotent = **un** état serveur final. |
| Après enqueue, avant wipe | La coupure vide la RAM *de facto* ; l'invariant est qu'**aucun plaintext/clé** n'a été écrit avant la coupure. |
| Pendant le wipe | Le wipe est **inconditionnel** (`finally`) ; une coupure ne laisse pas de clé exploitable persistée. |

Au redémarrage : la file SQLCipher (WAL) est **relue cohérente** et **draine sans doublon**
(#22). La **durabilité WAL réelle** (survie à un vrai kill process) est un test **device-backed**
non exécutable en CI host-only — voir §9.

---

## 5. Grille d'accessibilité

| Critère | Vérification |
|---------|--------------|
| **Échelle de texte max** | Aucun overflow/troncature de l'info vitale (allergies) ni des libellés d'action. |
| **TalkBack** | Chaque action clé (`Ajouter une note / ordonnance`, `Terminer`, `Synchroniser`, boutons d'onboarding) a un libellé ; les allergies sont annoncées de façon autonome ; les titres de section sont des en-têtes. |
| **Contraste AA** | Lisibilité plein jour (repris de la norme UX #28). |
| **Cibles tactiles ≥ 48 dp** | Actions clés atteignables sans erreur. |
| **Usage à une main** | Actions principales dans la zone du pouce ; mono-flux « zéro menu ». |

Instrument : **Accessibility Scanner** (Android) sur appareil. Les invariants **automatisables**
(cibles, `Semantics`, `textScaleFactor`) roulent en CI (widget tests `test/ux/`, phase tests).

---

## 6. Perf sous contrainte

- Rejouer la cible **< 3 s** (#27) scan → dossier affiché sur l'appareil saturé sous `3G-STABLE`.
- Rejouer le proxy **< 5 min** (#28) du parcours médecin ; instrument optionnel
  [`task_timing.dart`](../../app-patient/lib/src/doctor/task_timing.dart) (durées + labels
  uniquement — **jamais** de PII/donnée médicale/clé/payload QR).
- Consigner les écarts par rapport aux mesures sur machine de dev.

---

## 7. Critères de réussite

| Critère | Seuil |
|---------|-------|
| Perte de données (stockage saturé + coupures) | **0** (alerte forte tolérée ; perte silencieuse interdite) |
| Doublon après reprise de file | **0** |
| Plaintext / clé / payload QR écrit sur disque | **0** |
| Overflow de l'info vitale / des actions à grande échelle de texte | **0** |
| Action clé sans libellé TalkBack ou < 48 dp | **0** |
| Perf scan → affichage sous `3G-STABLE` saturé | **< 3 s** (report, #27) |

Un résultat sous ces seuils déclenche un correctif de robustesse/accessibilité ciblé puis un
re-test, avant de considérer le critère d'acceptation satisfait.

---

## 8. Gabarit de compte-rendu

> **Statut :** **à produire** — aucune validation terrain n'a encore eu lieu. Ce gabarit n'affirme
> aucun résultat tant que les mesures ne sont pas collectées sur l'appareil réel (#31 / campagne
> dédiée).

```
Campagne : <date> · Surface : <Flutter de référence | PWA> · Opérateur : <code>
Appareil : <modèle Infinix bas de gamme> · Espace libre : <Mo> · Réseau : 3G-STABLE simulé (#27)

Robustesse — stockage saturé :
- App réactive sous saturation : PASS/FAIL
- Échec disque → alerte forte, session wipée, 0 perte silencieuse : PASS/FAIL
- 0 plaintext/clé/payload QR écrit : PASS/FAIL

Robustesse — micro-coupures (points d'injection §4) :
| Point           | Perte | Doublon | Plaintext/clé résiduel | Verdict |
| avant PUT       | 0     | 0       | non                    | PASS    |
| pendant PUT     | ...   | ...     | ...                    | ...     |
| put→remove      | ...   | ...     | ...                    | ...     |
| enqueue→wipe    | ...   | ...     | ...                    | ...     |
| pendant wipe    | ...   | ...     | ...                    | ...     |

Accessibilité (grille §5) :
| Critère                       | Verdict | Notes |
| Échelle texte max (0 overflow)| ...     | ...   |
| TalkBack (libellés)           | ...     | ...   |
| Contraste AA                  | ...     | ...   |
| Cibles ≥ 48 dp                | ...     | ...   |
| Usage à une main              | ...     | ...   |

Perf sous contrainte : scan→affichage <mm:ss.mmm> (seuil < 3 s : PASS/FAIL)

Conclusion critère #29 : <VALIDÉ | ITÉRATION REQUISE> — décision humaine, tracée vers #31.
```

---

## 9. Restant (hors CI host-only)

- **Device-backed :** durabilité WAL SQLCipher sous **vrai** kill process ; illisibilité de la file
  sans clé Keystore ; déchiffrement RAM-only sous **faible RAM réelle** ; audit **Accessibility
  Scanner** / axe-core sur appareil. Non exécutables dans la CI host-only actuelle.
- **Terrain / humain :** la **validation des deux parcours** sur l'appareil Infinix réel selon ce
  protocole — produit la **preuve du critère d'acceptation** ; résultats consignés au §8.
- **PWA `app-medecin` :** le flux de consultation n'y est pas encore porté (#17/#21/#22) ; la
  validation médecin porte pour l'instant sur la **surface Flutter de référence** (`app-patient`),
  miroitée dans la PWA à l'arrivée du flux (cohérent avec #28).

---

## 10. Éthique & confidentialité

- **Consentement** des participants aligné sur la politique participants (#7), distinct du
  consentement patient produit.
- **Aucune captation** de PII / donnée médicale réelle ; **aucun** enregistrement de payload QR, de
  clé de session ni de contenu de dossier.
- **Résidence :** tout artefact (chronos, journaux, captures d'espace disque) reste sur le
  territoire et conforme au registre des traitements (#5).
