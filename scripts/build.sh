#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/vendor-dylibs.sh
xcodegen generate
xcodebuild -project AFT.xcodeproj -scheme AFT -configuration Debug build CODE_SIGNING_ALLOWED=NO "$@"
APP="$(xcodebuild -project AFT.xcodeproj -scheme AFT -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/AFT.app"
echo "Built: $APP"
otool -L "$APP/Contents/Frameworks/libmtp.dylib" | sed -n '1,4p'
