#!/usr/bin/env bash
# Build libusb + libmtp from source as UNIVERSAL (arm64 + x86_64) dylibs with a
# macOS 13 deployment target, so the app runs on Intel and Apple Silicon down to
# Ventura. Output lands in build-deps/prefix; run scripts/vendor-dylibs.sh after
# to copy + @rpath-fixup them into AFT/Frameworks.
#
# Requires: Xcode CLT (clang/make/lipo/libtool), pkg-config (brew install pkg-config).
set -euo pipefail

LIBUSB_VER="1.0.27"
LIBMTP_VER="1.1.23"
DEPLOY="13.0"
ARCHFLAGS="-arch arm64 -arch x86_64 -mmacosx-version-min=${DEPLOY}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build-deps"
PREFIX="$BUILD/prefix"
mkdir -p "$BUILD" "$PREFIX"
cd "$BUILD"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOY"

# --- libusb ---
if [ ! -d "libusb-${LIBUSB_VER}" ]; then
  curl -sL -o libusb.tar.bz2 \
    "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VER}/libusb-${LIBUSB_VER}.tar.bz2"
  tar xf libusb.tar.bz2
fi
( cd "libusb-${LIBUSB_VER}"
  ./configure --prefix="$PREFIX" --disable-dependency-tracking \
    --enable-shared --disable-static --disable-udev \
    CFLAGS="$ARCHFLAGS" LDFLAGS="$ARCHFLAGS"
  make -j4 && make install )

# --- libmtp (against the libusb we just built) ---
if [ ! -d "libmtp-${LIBMTP_VER}" ]; then
  curl -sL -o libmtp.tar.gz \
    "https://github.com/libmtp/libmtp/releases/download/v${LIBMTP_VER}/libmtp-${LIBMTP_VER}.tar.gz"
  tar xf libmtp.tar.gz
fi
( cd "libmtp-${LIBMTP_VER}"
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure --prefix="$PREFIX" \
    --disable-dependency-tracking --enable-shared --disable-static \
    --disable-mtpz --without-doxygen \
    CFLAGS="$ARCHFLAGS" LDFLAGS="$ARCHFLAGS -L$PREFIX/lib"
  make -j4 -C src && make -C src install )

echo "Done. Universal libs in $PREFIX/lib:"
lipo -info "$PREFIX"/lib/libmtp.*.dylib "$PREFIX"/lib/libusb-1.0.0.dylib
echo "Next: ./scripts/vendor-dylibs.sh"
