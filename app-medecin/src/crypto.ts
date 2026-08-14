/**
 * Session-blob crypto pour la PWA médecin (#108).
 *
 * Mode : dev (build Vite non-prod) → XOR 0x5A stub, miroir de _DevCryptoCore Flutter.
 *        prod (import.meta.env.PROD) → WebCrypto AES-256-GCM, miroir de FrbCryptoCore / Rust aes-gcm.
 *
 * Format fil (prod) :
 *   chiffrement → nonce (12 octets, CSPRNG) ‖ ciphertext+tag (AES-256-GCM)
 *   déchiffrement ← nonce (12 octets) ‖ ciphertext+tag
 *
 * Ce module couvre UNIQUEMENT le blob de session (/blob/{uuid}).
 * Le chiffrement par-fichier média (NoteScreen, VoiceNoteScreen) utilise
 * des contentKey individuelles et sera traité avec le WASM crypto-core (#102).
 */

const MODE: "dev" | "prod" = import.meta.env.PROD ? "prod" : "dev";

// ── Interface publique ────────────────────────────────────────────────────────

export interface SessionCrypto {
  decrypt(blob: Uint8Array): Promise<Uint8Array>;
  encrypt(plaintext: Uint8Array): Promise<Uint8Array>;
}

// ── Helpers internes ──────────────────────────────────────────────────────────

function b64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function xorBytes(data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) out[i] = data[i] ^ 0x5a;
  return out;
}

// ── Mode dev (XOR 0x5A) ───────────────────────────────────────────────────────

const devCrypto: SessionCrypto = {
  decrypt: async (blob) => xorBytes(blob),
  encrypt: async (plain) => xorBytes(plain),
};

// ── Mode prod (WebCrypto AES-256-GCM) ────────────────────────────────────────

async function makeProdCrypto(keyB64url: string): Promise<SessionCrypto> {
  const keyBytes = b64urlDecode(keyB64url);
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes as unknown as Uint8Array<ArrayBuffer>,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );

  return {
    async decrypt(blob) {
      if (blob.length < 13) throw new Error("blob trop court — nonce AES-GCM absent");
      const nonce = blob.slice(0, 12);
      const ciphertext = blob.slice(12);
      const buf = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: nonce },
        key,
        ciphertext,
      );
      return new Uint8Array(buf);
    },

    async encrypt(plaintext) {
      const nonce = crypto.getRandomValues(new Uint8Array(12));
      const ciphertext = new Uint8Array(
        await crypto.subtle.encrypt(
          { name: "AES-GCM", iv: nonce },
          key,
          plaintext as unknown as Uint8Array<ArrayBuffer>,
        ),
      );
      const out = new Uint8Array(12 + ciphertext.length);
      out.set(nonce, 0);
      out.set(ciphertext, 12);
      return out;
    },
  };
}

// ── Factory publique ──────────────────────────────────────────────────────────

/**
 * Crée un SessionCrypto depuis la clé de session base64url du QR payload
 * (`qrPayload.key`). À appeler une seule fois par scan QR ; conserver en
 * état mémoire pour la durée de la session (ne jamais persister).
 */
export async function createSessionCrypto(
  sessionKeyB64url: string,
): Promise<SessionCrypto> {
  if (MODE === "prod") return makeProdCrypto(sessionKeyB64url);
  return devCrypto;
}
