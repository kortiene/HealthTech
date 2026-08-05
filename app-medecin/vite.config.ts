import { defineConfig } from "vite";
import preact from "@preact/preset-vite";
import { VitePWA } from "vite-plugin-pwa";

// Security: the Service Worker caches ONLY the app shell (HTML, JS, CSS, fonts).
// It NEVER caches /blob/* or /media/* routes — those contain patient ciphertext
// and must always go to the network. Session keys never touch the SW cache.
export default defineConfig({
  plugins: [
    preact(),
    VitePWA({
      registerType: "autoUpdate",
      // Generate the SW at build time; in dev, a minimal SW is injected.
      devOptions: {
        enabled: true,
        type: "module",
      },
      manifest: {
        name: "HealthTech — Interface Médecin",
        short_name: "HealthTech",
        description: "Consultation et dossier patient sécurisé",
        theme_color: "#1565C0",
        background_color: "#FFFFFF",
        display: "standalone",
        orientation: "portrait",
        lang: "fr",
        icons: [
          {
            src: "/icons/icon-192.png",
            sizes: "192x192",
            type: "image/png",
          },
          {
            src: "/icons/icon-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "any maskable",
          },
        ],
      },
      workbox: {
        // Cache-first for app shell assets (JS bundles, CSS, fonts).
        globPatterns: ["**/*.{js,css,html,ico,woff2}"],
        // NEVER cache blob or media routes — these are patient ciphertext.
        // Network-only: any miss falls through to the backend.
        runtimeCaching: [
          {
            urlPattern: /\/blob\//,
            handler: "NetworkOnly",
            options: { cacheName: "blob-no-cache" },
          },
          {
            urlPattern: /\/media\//,
            handler: "NetworkOnly",
            options: { cacheName: "media-no-cache" },
          },
          {
            // Google Fonts — cache with stale-while-revalidate (non-sensitive).
            urlPattern: /^https:\/\/fonts\.(googleapis|gstatic)\.com\//,
            handler: "StaleWhileRevalidate",
            options: { cacheName: "google-fonts" },
          },
        ],
      },
    }),
  ],
  test: {
    globals: true,
    environment: "node",
  },
});
