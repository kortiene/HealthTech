# Registre des activités de traitement

> Artefact d'**accountability** ([REQ-LEX-21](./exigences-legales.md)) — contrôle **CTRL-24**, preuve
> **PREUVE-17**. Recense chaque traitement de données à caractère personnel mis en œuvre par la plateforme.
>
> ⚠️ **Aucune donnée patient réelle** ne figure ici : uniquement des **catégories**, finalités, durées et
> mesures. La **répartition des rôles RT / sous-traitant** (patient / médecin / plateforme / hébergeur)
> est une **question ouverte** ([ECART-06](./ecarts.md)) ; les durées de conservation sont à arbitrer
> ([ECART-01](./ecarts.md)).

## Identité (à compléter par la gouvernance)

| Champ | Valeur |
| --- | --- |
| Responsable de traitement | **`[à désigner]`** (entité exploitant HealthTech) — répartition RT/sous-traitant : [ECART-06](./ecarts.md) |
| Correspondant / DPO | **`[à désigner si requis]`** ([ECART-04](./ecarts.md)) |
| Sous-traitant principal | **Hébergeur souverain in-country** ([#8](https://github.com/kortiene/HealthTech/issues/8), [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md)) |

---

## T-01 — Dossier médical du patient (cœur du service)

| Rubrique | Contenu |
| --- | --- |
| **Finalité** | Permettre au patient de détenir, transporter et partager son dossier médical chiffré ; permettre au professionnel de le consulter/compléter lors d'une consultation autorisée par le patient. |
| **Catégories de personnes** | Patients (personnes concernées) ; professionnels de santé (utilisateurs accédant via autorisation patient). |
| **Catégories de données** | **Données de santé (sensibles)** : antécédents, notes, ordonnances — **chiffrées côté patient (AES-256-GCM)** ; côté serveur : **blob opaque** + **UUID anonyme** + métadonnées non identifiantes (version/taille du chiffré, horodatages, paramètres KDF publics). |
| **Destinataires** | Professionnel de santé désigné par le patient via **QR éphémère ~120 s** ; serveur de stockage (**ne voit que des blobs opaques**, zero-knowledge). |
| **Localisation / résidence** | **Côte d'Ivoire uniquement** (hébergement souverain ; garde-fou IaC `country == "CI"`). |
| **Transferts hors pays** | **Aucun** (pas de cloud étranger dans le chemin de données). |
| **Durée de conservation** | **`[à définir]`** — arbitrage droit à l'oubli ↔ rétention médicale minimale ([ECART-01](./ecarts.md)). |
| **Mesures de sécurité** | CTRL-01 (chiffrement client), CTRL-02 (zero-knowledge), CTRL-03/04 (clés), CTRL-23 (TLS), CTRL-13 (métadonnées non identifiantes). |
| **Base légale** | Consentement du patient ([REQ-LEX-03/04](./exigences-legales.md)). |

## T-02 — Compte patient & clés cryptographiques

| Rubrique | Contenu |
| --- | --- |
| **Finalité** | Création d'un compte chiffré localement ; génération/scellement de la clé maîtresse ; récupération sur nouvel appareil. |
| **Catégories de personnes** | Patients. |
| **Catégories de données** | Identifiant de compte (n° CMU / téléphone) **traité localement, jamais envoyé en clair** ; clé maîtresse **scellée dans l'Android Keystore, jamais exportée** ; paramètres PBKDF2 (sel + itérations, **publics par conception**). |
| **Destinataires** | **Aucun côté serveur** pour les clés (client-side only). |
| **Localisation / résidence** | Appareil du patient (local-first). |
| **Transferts hors pays** | Aucun. |
| **Durée de conservation** | Tant que le compte est actif ; suppression = crypto-effacement ([ECART-02](./ecarts.md)). |
| **Mesures de sécurité** | CTRL-03 (Keystore), CTRL-04 (PBKDF2), CTRL-17 (local-first). |
| **Base légale** | Exécution du service demandé par le patient + consentement. |

## T-03 — Partage de consultation (accès professionnel)

| Rubrique | Contenu |
| --- | --- |
| **Finalité** | Octroyer un accès **éphémère et contrôlé par le patient** au dossier, le temps d'une consultation. |
| **Catégories de personnes** | Patients ; professionnels de santé. |
| **Catégories de données** | Clé de session symétrique transmise **via le QR** (jamais persistée hors du QR) ; dossier **déchiffré en RAM uniquement** côté professionnel. |
| **Destinataires** | Professionnel autorisé par le patient. |
| **Localisation / résidence** | RAM du terminal professionnel (éphémère) ; serveur in-country pour le blob. |
| **Transferts hors pays** | Aucun. |
| **Durée de conservation** | **Éphémère** : QR ~120 s ; session wipée au clic « Terminer » / 15 min d'inactivité ([REQ-LEX-10](./exigences-legales.md)). |
| **Mesures de sécurité** | CTRL-05 (QR éphémère), CTRL-06 (RAM-only), CTRL-07 (wipe). *(Réserve : RAM-only navigateur best-effort — [ADR 0000](../adr/0000-index.md) risque #1.)* |
| **Base légale** | Consentement / acte explicite du patient (génération du QR). |

## T-04 — Médias médicaux lourds (radiographies, scans)

| Rubrique | Contenu |
| --- | --- |
| **Finalité** | Stocker hors du téléphone les images médicales lourdes ; n'embarquer qu'une **URL éphémère** dans le dossier texte. |
| **Catégories de personnes** | Patients. |
| **Catégories de données** | Images médicales **chiffrées**, stockées sur objet souverain (MinIO) ; **URL presigned éphémère** révocable. |
| **Destinataires** | Patient ; professionnel autorisé (via URL éphémère). |
| **Localisation / résidence** | Objet souverain in-country. |
| **Transferts hors pays** | Aucun. |
| **Durée de conservation** | URL : courte TTL ; objet : **`[à définir]`** ([ECART-01](./ecarts.md)). |
| **Mesures de sécurité** | CTRL-11 (médias hors téléphone + URL éphémère), CTRL-08 (hébergement souverain). |
| **Base légale** | Consentement du patient. |

## T-05 — File d'attente hors-ligne (médecin)

| Rubrique | Contenu |
| --- | --- |
| **Finalité** | Ne perdre aucune donnée de consultation lors d'une coupure réseau/courant ; synchroniser au retour. |
| **Catégories de personnes** | Patients (données de consultation) ; professionnel. |
| **Catégories de données** | Ordonnance/note **déjà chiffrée (AES-256-GCM)** — SQLCipher (Android) ou IndexedDB-ciphertext (PWA web). **Aucun plaintext sur disque.** |
| **Destinataires** | Serveur in-country (à la synchronisation). |
| **Localisation / résidence** | Appareil professionnel (chiffré) puis serveur in-country. |
| **Transferts hors pays** | Aucun. |
| **Durée de conservation** | Jusqu'à synchronisation réussie ([#21](https://github.com/kortiene/HealthTech/issues/21), [#22](https://github.com/kortiene/HealthTech/issues/22)). |
| **Mesures de sécurité** | CTRL-01 (chiffrement), [ADR 0006](../adr/0006-offline-storage-and-keys.md). |
| **Base légale** | Consentement / exécution de la consultation autorisée. |

## T-06 — Secrets opérationnels (hors périmètre données patient)

| Rubrique | Contenu |
| --- | --- |
| **Finalité** | Faire fonctionner l'infrastructure (mots de passe DB, clés MinIO, clé de signature des URL, clé TLS, clés de sauvegarde). |
| **Catégories de données** | **Secrets opérationnels uniquement** — **jamais** de clé patient, de clé de session, ni de PII ([ADR 0007](../adr/0007-secrets-and-environments.md)). |
| **Localisation / résidence** | In-country (SOPS + age ; racine de confiance in-country). |
| **Transferts hors pays** | Aucun (pas de KMS étranger). |
| **Mesures de sécurité** | CTRL-10, CTRL-14 ; frontière secrets opérationnels ↔ clés patient préservée. |

---

> **Note.** Ce registre est un **projet** : finalités, bases légales, durées et rôles doivent être
> **revus et arrêtés** avec le conseil juridique et la gouvernance avant le dépôt ARTCI
> ([#30](https://github.com/kortiene/HealthTech/issues/30)).
