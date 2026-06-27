# Spec — Structure & schéma du dossier médical (issue #15)

## Problème

Le dossier médical est le payload chiffré AES-256-GCM stocké sur le serveur.
Son format et sa taille doivent être définis avant que la boucle de consultation
(M2) ou la sauvegarde cloud (US-1.3) puissent être implémentées. Sans garde-fou
de taille, un dossier trop volumineux empêcherait l'affichage en < 3 s sur une
connexion Edge/3G (NFR, PRD §5).

## Objectifs

- G1 : schéma JSON **versionné** (champ `v`) permettant la migration sans casse.
- G2 : **garde-fou bloquant** au-delà de 500 Kio de texte brut sérialisé.
- G3 : **avertissement** à 80 % (≥ 400 Kio) pour déclencher la troncature
  préventive avant blocage.
- G4 : **stratégie de troncature** deterministe : suppression des consultations
  les plus anciennes en premier jusqu'à repasser sous le seuil.
- G5 : le dossier ne contient **jamais de données binaires** (images,
  radiographies) — uniquement des URL éphémères (PRD §4).

## Non-objectifs

- Compression (gzip/brotli) : différée post-M1 ; la limite de 500 Kio est
  suffisante pour du texte sans compression.
- Validation FHIR ou schéma ICD-10 complet : hors scope de M1.
- Migration automatique : le migrateur lit `v` et applique des patches ; son
  implémentation est laissée à une issue dédiée.

## Schéma v1

```json
{
  "v": 1,
  "patient_id": "<uuid-v4>",
  "demographics": {
    "given_name": "Awa",
    "birth_year": 1996,
    "sex": "F",
    "blood_type": "O+"
  },
  "allergies": [
    { "substance": "Pénicilline", "severity": "severe", "noted_at": "2024-01-15" }
  ],
  "chronic_conditions": [
    { "name": "Diabète type 2", "icd10": "E11", "since": "2020" }
  ],
  "medications": [
    {
      "name": "Metformine",
      "dose": "500 mg",
      "frequency": "2x/jour",
      "prescribed_at": "2024-01-15",
      "prescribed_by": "<practitioner-uuid>"
    }
  ],
  "consultations": [
    {
      "id": "<uuid-v4>",
      "date": "2024-01-15",
      "practitioner_ref": "<uuid-v4>",
      "summary": "Contrôle glycémie, résultats normaux.",
      "prescription": "Continuer Metformine.",
      "image_urls": ["https://cdn.healthtech.ci/img/abc123?token=…"]
    }
  ],
  "immunizations": [
    { "name": "Hépatite B", "date": "2010-03-01", "dose": 1 }
  ],
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-15T10:30:00Z"
}
```

### Règles du schéma

| Champ | Type | Nullable | Règle |
|---|---|---|---|
| `v` | int | non | Toujours présent ; actuellement `1` |
| `patient_id` | UUID string | non | Identifiant local opaque, jamais corrélé avec CMU/téléphone |
| `demographics.*` | mixed | oui | Patient-contrôlé ; `sex` : `M`, `F`, `O`, ou `null` |
| `consultations[].image_urls` | `string[]` | non | URLs éphémères uniquement — aucune donnée binaire |
| `created_at`, `updated_at` | ISO-8601 UTC | non | Timestamps en zone UTC |

## Garde-fou de taille

```
const maxPlaintextBytes  = 512 000   // 500 Kio — bloquant
const warnPlaintextBytes = 409 600   // 400 Kio — avertissement (80 %)
```

L'encodage de référence est **UTF-8** (le sérialiseur JSON Dart produit de l'UTF-8).

### Stratégie de troncature (`RecordSizeGuard.truncate`)

1. Sérialiser le dossier en JSON UTF-8.
2. Si `size >= maxPlaintextBytes` : lever `RecordTooLargeException`.
3. Tant que `size >= maxPlaintextBytes` et qu'il reste des consultations :
   a. Supprimer la consultation avec la date la plus ancienne (`date` ASC).
   b. Re-sérialiser et re-mesurer.
4. Si le dossier est encore trop grand après suppression de toutes les
   consultations : lever `RecordTooLargeException` (données fixes trop larges).

La troncature est **déterministe et réversible** (les consultations supprimées
restent dans le blob cloud de la version précédente).

## Composants touchés

| Composant | Fichier | Action |
|---|---|---|
| Patient app | `lib/src/record/medical_record.dart` | Nouveau — modèle + sérialisation |
| Patient app | `lib/src/record/record_size_guard.dart` | Nouveau — garde-fou + troncature |
| Patient app | `test/record/medical_record_test.dart` | Nouveau — round-trip + migration |
| Patient app | `test/record/record_size_guard_test.dart` | Nouveau — seuils + troncature |
| Specs | `specs/medical-record-schema.md` | Ce fichier |

## Critères d'acceptation

- [x] Champ `v: 1` présent dans le JSON sérialisé de tout `MedicalRecord`.
- [x] `RecordSizeGuard.validate` lève `RecordTooLargeException` si le JSON UTF-8
  dépasse 512 000 octets.
- [x] `RecordSizeGuard.validate` lève `RecordSizeWarning` (ou équivalent) entre
  409 600 et 512 000 octets.
- [x] `RecordSizeGuard.truncate` supprime les consultations les plus anciennes
  jusqu'à passer sous le seuil, ou lève `RecordTooLargeException` si impossible.
- [x] Round-trip JSON : `MedicalRecord.fromJson(r.toJson()) == r`.
- [x] Aucune donnée binaire dans le schéma (`image_urls` = strings uniquement).

## Décisions de sécurité & confidentialité

- `patient_id` est un UUID v4 local généré à la création du compte. Il ne
  transite jamais en clair vers le serveur (il est inclus dans le blob chiffré).
- Le dossier entier est le payload de `encrypt_record` (#10) : la frontière
  zéro-connaissance est maintenue.
- Aucune clé, aucun token, aucune URL de déchiffrement n'est inclus dans le
  schéma ; les `image_urls` sont des URLs signées éphémères sans credential
  embarqué.

## Risques

- Si les sections fixes (demographics, allergies, conditions, medications,
  immunizations) dépassent 500 Kio à elles seules, la troncature des
  consultations ne suffit pas. Dans ce cas `RecordTooLargeException` est levée
  et l'app doit demander au patient de réduire la taille de ses données fixes.
- La limite de 500 Kio est sur le **texte brut JSON**. Si l'overhead JSON
  (clés, guillemets, indentation) devient significatif, envisager MessagePack
  ou gzip en post-M1.
