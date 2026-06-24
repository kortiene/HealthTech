# Politique de sécurité — HealthTech

## Portée

Ce document décrit la politique de divulgation responsable des vulnérabilités pour la plateforme **HealthTech** — plateforme de santé numérique décentralisée (Côte d'Ivoire), conçue selon une architecture **local-first / zero-knowledge**.

## Signaler une vulnérabilité

> **Ne pas ouvrir une issue GitHub publique pour une vulnérabilité de sécurité.** Les issues GitHub sont publiques et exposeraient la vulnérabilité avant qu'elle soit corrigée.

Envoyez un rapport de vulnérabilité à l'adresse :

**security@[domaine-du-projet]** *(à compléter lors de la mise en production — issue [#8](https://github.com/kortiene/HealthTech/issues/8))*

En attendant la mise en production, utiliser le mécanisme de **Security Advisory** de GitHub :
`https://github.com/kortiene/HealthTech/security/advisories/new`

### Informations à inclure dans le rapport

- Description de la vulnérabilité
- Composant affecté (app patient, app médecin, backend, crypto-core)
- Étapes de reproduction
- Impact potentiel (confidentialité des données médicales, intégrité, disponibilité)
- Preuve de concept (si disponible et responsable)
- Suggestions de correction (optionnel)

## Délais de réponse

| Étape | Délai cible |
|-------|-------------|
| Accusé de réception | 48 heures |
| Évaluation de la sévérité | 5 jours ouvrés |
| Correction (vulnérabilité Critique/Haute) | 30 jours |
| Correction (vulnérabilité Modérée/Faible) | 90 jours |
| Divulgation coordonnée | Après correction et accord |

## Classification des sévérités

| Sévérité | Exemples |
|----------|---------|
| **Critique** | Déchiffrement de dossier médical côté serveur ; extraction de clé maîtresse ; contournement du zero-knowledge |
| **Haute** | QR valide au-delà de 120 s ; données en clair persistées sur disque médecin ; PBKDF2 bypassable |
| **Modérée** | Fuite de métadonnées non identifiantes ; DoS de disponibilité sans perte de données |
| **Faible** | Divulgation d'informations non sensibles ; UX de sécurité dégradée |

## Contraintes de sécurité absolues

Les contre-mesures suivantes ne doivent **jamais** être affaiblies, quelle que soit la vulnérabilité rapportée :

1. **Zero-knowledge** : le serveur ne peut pas déchiffrer les données — toute « correction » introduisant un déchiffrement côté serveur est refusée.
2. **Chiffrement AES-256-GCM** : le niveau de chiffrement ne peut pas être réduit.
3. **Clé maîtresse** : ne peut jamais être exportée en clair hors de l'Android Keystore.
4. **Accès d'urgence** : aucune porte dérobée (backdoor) serveur ne sera introduite, même sous pression légale ou médicale (voir ECART-08 dans [`docs/threat-model/stride-threat-model.md`](./docs/threat-model/stride-threat-model.md)).
5. **Résidence des données** : aucune donnée patient ne peut transiter ou être stockée hors du territoire national ivoirien.

## Modèle de menace

Le modèle de menace complet (STRIDE) est disponible dans :
[`docs/threat-model/stride-threat-model.md`](./docs/threat-model/stride-threat-model.md)

Il couvre les menaces : vol de téléphone, serveur compromis, MITM réseau, QR code intercepté, attaque sur la phrase de passe de récupération, répudiation d'actes médicaux, déni de service, et accès d'urgence.

## Périmètre des tests de sécurité autorisés

Les chercheurs en sécurité sont invités à tester :

- L'architecture zero-knowledge du backend
- La robustesse du chiffrement AES-256-GCM et de la gestion des nonces
- L'expiration et l'unicité des QR codes d'accès
- La résistance de la dérivation PBKDF2 au brute-force
- L'absence de données en clair côté serveur ou dans les logs
- La conformité de la résidence des données

**Hors périmètre :**
- Tests sur les environnements de production ou de staging avec des données réelles
- Attaques par déni de service visant à perturber le service
- Ingénierie sociale ciblant les membres de l'équipe

## Récompenses (Bug Bounty)

Un programme de bug bounty formel sera établi au moment du lancement commercial ([#31](https://github.com/kortiene/HealthTech/issues/31)). En attendant, les chercheurs ayant contribué à identifier des vulnérabilités significatives seront crédités dans les notes de version avec leur accord.

## Conformité réglementaire

Les vulnérabilités affectant la protection des données personnelles seront également notifiées à l'**ARTCI** (Autorité de Régulation des Télécommunications/TIC de Côte d'Ivoire) conformément à la loi n°2013-450 et au contrat d'homologation ([#30](https://github.com/kortiene/HealthTech/issues/30)).

Voir la procédure d'incident : [`docs/compliance/ecarts.md`](./docs/compliance/ecarts.md) (ECART-03 — à instruire).

---

*Document lié à l'issue [#6](https://github.com/kortiene/HealthTech/issues/6) — Modèle de menace & politique de sécurité.*
