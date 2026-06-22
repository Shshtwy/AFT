#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="$ROOT/build-deps/prefix"
DEST="$ROOT/AFT/Frameworks"

# Universal (arm64 + x86_64), macOS-13 builds of libmtp/libusb produced by
# scripts/build-universal-deps.sh live under build-deps/prefix. Falls back to
# Homebrew only if that prefix is missing.
if [ -d "$PREFIX/lib" ] && ls "$PREFIX"/lib/libmtp.*.dylib >/dev/null 2>&1; then
  SRC="$PREFIX/lib"
else
  SRC="$(brew --prefix)/lib"
fi

mkdir -p "$DEST"
MTP="$(readlink -f "$SRC"/libmtp.*.dylib | head -1)"
USB="$(readlink -f "$SRC"/libusb-1.0.*.dylib | head -1)"

cp "$MTP" "$DEST/libmtp.dylib"
cp "$USB" "$DEST/libusb-1.0.0.dylib"
chmod u+w "$DEST/libmtp.dylib" "$DEST/libusb-1.0.0.dylib"

# Our own install names -> @rpath
install_name_tool -id @rpath/libmtp.dylib "$DEST/libmtp.dylib"
install_name_tool -id @rpath/libusb-1.0.0.dylib "$DEST/libusb-1.0.0.dylib"

# Repoint libmtp's reference to libusb -> @rpath
OLD_USB="$(otool -L "$DEST/libmtp.dylib" | awk '/libusb-1.0/{print $1; exit}')"
if [ -n "${OLD_USB:-}" ]; then
  install_name_tool -change "$OLD_USB" @rpath/libusb-1.0.0.dylib "$DEST/libmtp.dylib"
fi

# Ad-hoc re-sign after rewriting load commands
codesign -f -s - "$DEST/libusb-1.0.0.dylib"
codesign -f -s - "$DEST/libmtp.dylib"

echo "Vendored from: $SRC"
echo "Architectures:"; lipo -info "$DEST/libmtp.dylib" "$DEST/libusb-1.0.0.dylib"
echo "libmtp deps:"; otool -L "$DEST/libmtp.dylib" | sed -n '1,6p'
