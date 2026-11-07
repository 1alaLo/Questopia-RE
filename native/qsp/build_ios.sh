#!/usr/bin/env bash
# Builds the QSP engine as a static archive for one iOS slice.
# Usage: build_ios.sh [iphoneos|iphonesimulator] [arm64|x86_64]
set -euo pipefail

SLICE="${1:-iphoneos}"
ARCH="${2:-arm64}"
DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/ios/${SLICE}-${ARCH}"
OUT_LIB="$BUILD_DIR/libqsp_all.a"

if [ ! -f "$OUT_LIB" ] || [ "${QSP_FORCE_REBUILD:-0}" = "1" ]; then
  cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SLICE" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

  cmake --build "$BUILD_DIR" --target qsp --parallel
fi

test -f "$OUT_LIB"
echo "QSP archive ready: $OUT_LIB"
