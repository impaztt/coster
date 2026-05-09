#!/usr/bin/env bash
# Cloudflare Pages build script.
# Cloudflare's build image doesn't ship Flutter, so we fetch a shallow clone
# of the stable channel, put it on PATH, then build the web bundle.

set -euo pipefail

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="${FLUTTER_DIR:-_flutter}"

if [ ! -d "$FLUTTER_DIR" ]; then
  git clone --depth 1 -b "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$PATH:$PWD/$FLUTTER_DIR/bin"

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get
flutter build web --release
