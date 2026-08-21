#!/bin/bash
# Compiles crypto-core as a static library for the active iOS target.
# Called from the Xcode "Build Rust (crypto-core)" Run Script phase.
#
# Supports:
#   - Physical device  : aarch64-apple-ios
#   - Apple Silicon sim: aarch64-apple-ios-sim
#   - Intel sim        : x86_64-apple-ios  (legacy)

set -euo pipefail

WORKSPACE_ROOT="$SRCROOT/../../.."
[[ "$CONFIGURATION" == "Debug" ]] && CARGO_PROFILE="dev" || CARGO_PROFILE="release"
CARGO_DIR="$([[ $CARGO_PROFILE == "dev" ]] && echo debug || echo release)"

# Resolve the Rust target from Xcode env vars.
if [[ "$PLATFORM_NAME" == "iphonesimulator" ]]; then
  if [[ "$ARCHS" == *"arm64"* ]]; then
    TARGET="aarch64-apple-ios-sim"
  else
    TARGET="x86_64-apple-ios"
  fi
else
  TARGET="aarch64-apple-ios"
fi

echo "▶ cargo build --profile $CARGO_PROFILE --target $TARGET -p crypto-core"
cd "$WORKSPACE_ROOT"
cargo build --profile "$CARGO_PROFILE" --target "$TARGET" -p crypto-core

# Output to SRCROOT/RustLib/ — picked up by LIBRARY_SEARCH_PATHS in pbxproj.
mkdir -p "$SRCROOT/RustLib"
cp "target/$TARGET/$CARGO_DIR/libcrypto_core.a" "$SRCROOT/RustLib/"
echo "✓ libcrypto_core.a → $SRCROOT/RustLib/"
