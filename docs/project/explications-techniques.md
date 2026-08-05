# HealthTech — Explications techniques simplifiées

> Document interne — à destination de toute l'équipe, y compris non-technique.

---

## 1. C'est quoi la clé maître ?

Imagine un coffre-fort posé sur le téléphone du patient. Ce coffre contient toutes les données médicales.

**La clé maître = la clé de ce coffre.**

Concrètement :
- Au premier lancement, une clé aléatoire de 256 bits est générée par la puce du téléphone (pas par l'utilisateur).
- Cette clé est stockée protégée à l'intérieur du Keystore du téléphone (voir section 4 pour ce qu'est le Keystore).
- Quand tu entres ton PIN, l'app déverrouille temporairement cette clé pour lire ou écrire les données, puis l'efface immédiatement (voir section 1a ci-dessous).

> **Important** : le PIN ne génère pas la clé. Il sert uniquement à autoriser l'accès à la clé. Ce sont deux choses distinctes. Si tu oublies ton PIN, la clé existe encore mais tu ne peux plus y accéder.

---

### 1a. "Déverrouille temporairement" — qu'est-ce que ça veut dire exactement ? Et qu'est-ce qui est effacé ?

La clé maître (256 bits = 32 bytes, taille standard AES-256) sort brièvement du TEE lors de chaque opération. C'est un compromis architectural conscient et documenté (ADR 0006).

#### Comment elle est protégée — l'envelope encryption

Le TEE possède sa propre clé interne appelée **KEK** (Key-Encryption-Key). Elle est générée par le Keystore lui-même, non-exportable — elle ne quitte jamais la puce.

```
┌─────────────────────────────────────────────────────────┐
│                    TEE / StrongBox                       │
│   KEK  ←── non-exportable, ne sort JAMAIS du TEE        │
└─────────────────────┬───────────────────────────────────┘
                      │ chiffre / déchiffre
                      ▼
              Blob scellé sur disque
              (clé maître chiffrée par le KEK)
                      │ sort brièvement en RAM (millisecondes)
                      ▼
              Module Rust → chiffre les données médicales
```

Ce qui ne sort jamais : le **KEK**. Sans lui, le blob sur le disque est illisible même si on le récupère.
Ce qui sort brièvement : la **clé maître**, passée à Rust, puis effacée immédiatement.

#### Pourquoi ne pas utiliser une clé non-exportable directement ?

C'est la question logique — et elle a été explicitement posée et rejetée dans l'ADR 0006 :

> *"Alternative considered and rejected : direct wrapped-key import of the Rust key as a non-exportable Keystore key — more complex, less portable."*

La raison : **une clé générée par Rust ne peut pas être une clé non-exportable Android Keystore**. Le Keystore n'accepte comme non-exportable que les clés qu'il génère lui-même. Si la clé était non-exportable, Rust ne pourrait pas l'utiliser — et il faudrait trois implémentations crypto séparées (Kotlin/Android, Swift/iOS, JavaScript/PWA) au lieu d'une seule Rust.

Le trade-off accepté : **fenêtre d'exposition de quelques millisecondes en RAM** contre **une seule implémentation crypto auditée** qui fonctionne partout.

#### Ce qui se passe en pratique, pas à pas

La clé maître apparaît bien dans le heap Dart — pas de transfert direct FFI qui bypasse Dart. Le code lui-même le documente comme une limitation connue :

> *"Uint8List is not deterministically zeroizable (ADR 0001) — best-effort overwrite."*

```
Kotlin MethodChannel renvoie les bytes
    → codec StandardMessageCodec les sérialise   ← copie #1 (buffer codec)
    → Dart les désérialise en Uint8List heap     ← copie #2 (heap Dart)
    → FFI flutter_rust_bridge les copie en Rust  ← copie #3 (heap Rust)

fillRange(..., 0) efface copie #2   ← best-effort seulement
wipe(handle) efface copie #3        ← garanti (Rust zeroize)
copie #1 codec buffer               ← non effacée
```

**Pourquoi "best-effort" et pas une garantie pour Dart ?**

- Le GC Dart peut *déplacer* un `Uint8List` en mémoire lors d'une compaction — l'ancienne adresse n'est pas effacée, seulement la nouvelle.
- Le compilateur peut élider un `fillRange` comme dead store (écriture dans un buffer qui ne sera plus lu). Rust évite ça avec des écritures `volatile` via le crate `zeroize` — Dart n'a pas d'équivalent.

C'est précisément pourquoi tout le chiffrement vit en Rust et non en Dart : Rust garantit ce que Dart ne peut pas. La clé traverse le heap Dart le temps minimal possible (aller-retour MethodChannel → FFI), durée minimisée mais non éliminable avec cette architecture.

---

## 2. Le médecin peut-il enregistrer sans connexion internet ?

**Non.** Le médecin a besoin d'internet pour deux actions critiques :

1. **Scanner le QR** → il télécharge le blob chiffré depuis le serveur.
2. **Enregistrer la consultation** → il envoie les données mises à jour au serveur.

Si le médecin n'a pas de connexion au moment d'enregistrer, la sauvegarde échoue et il voit un message d'erreur.

**Comment le patient récupère la note ?**

Quand le patient ferme l'écran QR, l'app va automatiquement chercher la dernière version sur le serveur. Si le patient était hors ligne à ce moment, la mise à jour apparaîtra au prochain lancement de l'app (qui fait aussi une lecture cloud au démarrage).

---

## 3. Le QR expire après 120 secondes — alors pourquoi le médecin peut encore écrire après ?

**C'est tout à fait normal.** Les 120 secondes ne limitent pas la durée de la consultation — elles protègent uniquement la **fenêtre de scan**.

| Moment | Ce qui se passe |
|--------|----------------|
| Patient appuie sur "Partager" | QR généré, horloge de 120 s démarre |
| Médecin scanne le QR dans les 120 s | ✅ Il télécharge et déchiffre les données |
| QR expiré avant le scan | ❌ "QR expiré — demandez un nouveau code au patient" |
| QR scanné avec succès | Session établie — **le médecin peut travailler sans limite de temps** |
| Médecin clique "Enregistrer" | Il envoie la consultation — pas de limite de temps |

**Pourquoi 120 s seulement pour le scan ?** Si quelqu'un prenait une photo du QR affiché sur le téléphone du patient (dans une salle d'attente, par exemple), il ne pourrait s'en servir que dans les 2 minutes. Une fois ce délai passé, le QR est révoqué.

---

## 4. C'est quoi le Keystore TEE ?

**TEE = Trusted Execution Environment** = une mini-puce séparée à l'intérieur du processeur Android, isolée de tout le reste du téléphone.

Analogie : imagine que le processeur principal soit une grande salle commune. Le TEE est un coffre-fort scellé *à l'intérieur de cette salle*, auquel même le système Android ne peut pas accéder directement.

```
┌─────────────────────────────────────┐
│           Téléphone Android         │
│  ┌───────────────────────────────┐  │
│  │     Processeur principal      │  │
│  │  (Android, apps, virus…)      │  │
│  │   ┌───────────────────────┐   │  │
│  │   │   TEE (puce dédiée)   │   │  │
│  │   │   🔑 Clé maître       │   │  │
│  │   │   (intouchable)       │   │  │
│  │   └───────────────────────┘   │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Ce que ça garantit :**
- Même si un virus infecte Android, il ne peut pas extraire la clé maître.
- Même si quelqu'un rootait le téléphone, la clé reste dans la puce.
- En cas de vol, sans PIN + TEE, les données sont illisibles.

**Limite importante :** les téléphones très bas de gamme (ex. Infinix 32 Go) ont parfois un TEE logiciel au lieu d'une vraie puce matérielle. C'est moins sûr. C'est pourquoi des tests sur ces appareils sont planifiés (#29).

---

## 5. Le CMU et le numéro de téléphone servent à quoi ?

Le **CMU** = Carte de Mutuelle Universelle = le numéro d'assurance maladie ivoirien.

Ces deux champs sont saisis **uniquement à l'onboarding** (création de compte). Ils servent à :

- Identifier le patient de manière unique sur son propre téléphone.
- Permettre une récupération de compte future si le téléphone est perdu.

Ce qu'ils **ne font pas** :
- Ils ne partent **jamais sur le serveur** — le serveur ne les voit jamais.
- Ils ne sont **jamais dans les logs**.
- Dans les paramètres, le CMU est affiché masqué : `CMU-2025-••••XX`.

Le serveur ne connaît qu'un identifiant aléatoire (`anonymousUuid`) — impossible à relier à une vraie identité.

---

## 6. Pourquoi "Crypto-Core Rust" est en cours — et pourquoi pas le vrai Rust en mode dev ?

### Ce qui existe déjà

Le code Rust de chiffrement (`crypto-core/`) est écrit et contient la vraie implémentation AES-256-GCM. Ce n'est pas le problème.

### Ce qui manque

Pour que Flutter utilise ce code Rust, il faut :

1. **Générer les bindings Flutter-Rust-Bridge** : un outil de codegen qui lit le code Rust et génère automatiquement le code Dart correspondant. Cette étape n'a pas encore été faite — les fichiers générés ne sont pas dans le repo.

2. **Compiler des librairies natives** : le code Rust doit être compilé en fichiers `.so` pour chaque type de processeur Android (arm64, armv7, x86_64), et en `.dylib` pour iOS. Ces compilations n'ont pas été faites.

3. **Compiler en WebAssembly** pour la PWA médecin : le même code Rust compilé en `.wasm` pour tourner dans le navigateur.

### Pourquoi utiliser un stub (XOR) en dev ?

Installer Rust + Android NDK + LLVM + les toolchains de cross-compilation représente un setup lourd pour chaque développeur. Pour travailler sur l'UI sans cette complexité, on utilise `_DevCryptoCore` — un faux chiffrement qui fait XOR avec `0x5A`.

**Conséquence directe** : si quelqu'un essaie de lancer `main.dart` (version production) sans avoir compilé les librairies Rust, l'app plante immédiatement avec l'erreur `CryptoCoreUnavailable`. C'est volontaire — impossible de shipper accidentellement sans le vrai chiffrement.

> ⚠️ **`main_dev.dart`** avec le XOR ne doit **jamais** être compilé en version de production. Il sert uniquement à tester l'interface.

---

## 7. "Keystore TEE Kotlin" — c'est quoi concrètement ?

C'est la même chose que le point 4, mais vu du côté **code à écrire**.

Android expose son TEE via une API native appelée `Android Keystore`. Flutter est écrit en Dart — il ne peut pas appeler cette API directement. Il faut donc écrire un "pont" en Kotlin (le langage Android natif), qu'on appelle `MethodChannel`, qui fait le lien entre le Dart et le Keystore.

Ce pont Kotlin n'est pas encore écrit. Il y a actuellement un fichier vide avec `// TODO`. Sans ça, la clé maître est protégée de façon moins robuste.

---

## 8. Les risques identifiés — explications simples

### Risque 1 — Crypto SPOF *(Moyen)*

*"Une seule implémentation de chiffrement pour tout le projet"*

**Avantage :** une seule chose à auditer et à maintenir.

**Risque :** si on découvre un bug dans cette implémentation Rust (ex. une faille dans la façon dont les nonces sont générés), tous les composants sont touchés en même temps — app Android, iOS, et PWA.

**Mitigation :** surveiller étroitement les dépendances (cargo-deny), bloquer les mises à jour non contrôlées, faire auditer le code par un expert indépendant.

---

### Risque 2 — RAM-only navigateur *(Moyen)*

*"Les données du médecin sont en mémoire RAM du navigateur"*

Quand le médecin voit les données patient, elles sont déchiffrées dans la RAM du navigateur. En théorie, le système d'exploitation peut copier cette RAM sur le disque (mécanisme appelé "swap") sans que JavaScript le sache. On ne peut pas garantir à 100 % que les données ne touchent jamais le disque.

**Mitigation :** vider la mémoire dès que le médecin ferme la session, limiter le temps d'affichage, tester via pentest.

---

### Risque 3 — Android Keystore bas de gamme *(Moyen)*

*"Pas de vraie puce sécurisée sur les téléphones moins chers"*

Comme expliqué au point 4, sur un Infinix à bas prix, il peut ne pas y avoir de vrai TEE matériel. Dans ce cas, la clé est protégée de façon logicielle — moins résistante si quelqu'un obtient un accès root au téléphone.

**Mitigation :** détecter le type de protection disponible, adapter le comportement, tester sur appareils réels (#29).

---

### Risque 4 — Footprint mémoire Flutter *(Élevé — à valider en priorité)*

*"L'app peut ne pas se lancer correctement sur les petits téléphones"*

Flutter consomme de la mémoire. Un téléphone Infinix avec 2 Go de RAM et plusieurs apps en arrière-plan peut ne pas avoir assez de mémoire libre pour lancer HealthTech, ou l'app peut être tuée par Android en plein milieu d'une consultation.

**C'est le risque le plus concret avant un lancement.** Il faut absolument tester sur de vrais appareils bas de gamme avant de continuer le développement — si ça ne passe pas, c'est un bloquant.

**Mitigation :** device-lab gate (#29), mesure sur Infinix réel.

---

### Risque 5 — PBKDF2 lent sur petit CPU *(Faible)*

*"La vérification du PIN peut prendre quelques secondes sur un vieux processeur"*

PBKDF2 est volontairement lent (pour empêcher quelqu'un d'essayer des milliers de PINs par force brute). Sur un CPU rapide, c'est imperceptible. Sur un vieux CPU Infinix, ça peut prendre 3 à 5 secondes — ce qui est frustrant pour l'utilisateur.

**Mitigation :** mesurer sur appareils réels et ajuster le nombre d'itérations selon le résultat.

---

### Risque 6 — Datacenter unique *(Faible)*

*"Un seul serveur en Côte d'Ivoire = un seul point de panne"*

Si le serveur tombe en panne, les patients ne peuvent pas synchroniser leurs données. **Mais** — point important — l'app continue de fonctionner en local. Le patient peut toujours afficher son dossier et générer un QR pour le médecin. La panne empêche uniquement la synchronisation cloud, pas l'usage quotidien.

**Mitigation :** redondance dans le même datacenter ivoirien (HA in-country), pas de failover étranger pour rester conforme ARTCI.

---

*Document généré le 2026-08-04 — HealthTech*
