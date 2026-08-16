# app-medecin — multi-stage build: Node.js → Caddy static server.
# Build depuis la racine du repo :
#   docker build -f app-medecin/Dockerfile -t healthtech-pwa app-medecin/

FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY . .
# .env.production est commité : VITE_CRYPTO_MODE=prod (WebCrypto réel, pas de stub).
RUN npm run build

FROM caddy:2-alpine
COPY --from=build /app/dist /srv
# Fallback SPA : toute route inconnue renvoie index.html (routing côté client).
COPY <<'EOF' /etc/caddy/Caddyfile
:80 {
    root * /srv
    try_files {path} /index.html
    file_server
}
EOF
