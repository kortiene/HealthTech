# syntax=docker/dockerfile:1
#
# HealthTech backend image — zero-knowledge blob proxy (ADR 0004).
#
# Build from the REPO ROOT so the cargo workspace (crypto-core) is in context:
#   docker build -f backend/Dockerfile -t healthtech-backend .
#
# Produces a single, statically-linked (musl) binary on a distroless, non-root
# runtime: no shell, no package manager, minimal attack surface for a
# residency-hosted, secrets-adjacent service. The backend stores only opaque
# ciphertext — it holds no key material and has no decrypt path (ADR 0004).
# TLS is terminated by the in-country reverse proxy, not here (ADR 0005, #8).

ARG RUST_VERSION=1.96
ARG TARGET=x86_64-unknown-linux-musl

# ---- build stage ----------------------------------------------------------
FROM rust:${RUST_VERSION}-bookworm AS build
ARG TARGET
# musl-tools provides the `musl-gcc` linker for the fully-static target.
RUN rustup target add "${TARGET}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends musl-tools \
 && rm -rf /var/lib/apt/lists/*
# All workspace crypto deps are pure-Rust (RustCrypto, tokio, axum), so the musl
# static link needs no C crypto. Point the target linker at musl-gcc explicitly.
ENV CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    CC_x86_64_unknown_linux_musl=musl-gcc
WORKDIR /src
# Copy ONLY the cargo workspace (not the Flutter/PWA/infra trees) for fast,
# cache-friendly builds. `--locked` forbids any Cargo.lock drift.
COPY Cargo.toml Cargo.lock ./
COPY crypto-core ./crypto-core
COPY backend ./backend
RUN cargo build --release --locked --target "${TARGET}" --package backend \
 && cp "target/${TARGET}/release/backend" /backend

# ---- runtime stage --------------------------------------------------------
# distroless static + nonroot: no shell/pkg-mgr, runs as uid 65532.
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
LABEL org.opencontainers.image.title="healthtech-backend" \
      org.opencontainers.image.description="HealthTech zero-knowledge blob proxy (ADR 0004) — stores opaque ciphertext only, no keys, no decrypt path." \
      org.opencontainers.image.source="https://github.com/kortiene/HealthTech" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"
COPY --from=build /backend /usr/local/bin/backend
# Matches the listen address in backend/src/main.rs (0.0.0.0:8080).
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/backend"]
