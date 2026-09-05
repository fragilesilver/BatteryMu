#!/bin/sh
# build.sh - assemble the BatteryMu .muxapp release archive.
#   ./build.sh [version]        (version defaults to VERSION file, else "dev")
# Output: dist/BatteryMu-<version>.muxapp

set -e
APP="BatteryMu"
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION" 2>/dev/null || echo dev)}"
DIST="$ROOT/dist"
STAGE="$DIST/build/mnt/mmc/MUOS/application/$APP"

echo "==> Building $APP $VERSION"
rm -rf "$DIST"
mkdir -p "$STAGE"

# Everything except repo meta / build output / runtime data.
tar -C "$ROOT" \
    --exclude='./.git' --exclude='./dist' --exclude='./save' --exclude='./data' \
    --exclude='./.github' --exclude='*.log' --exclude='./build.sh' \
    --exclude='./README.md' --exclude='./CHANGELOG.md' --exclude='./LICENSE' \
    --exclude='./VERSION' --exclude='./.gitignore' \
    -cf - . | tar -C "$STAGE" -xf -

chmod +x "$STAGE/mux_launch.sh" "$STAGE/bin/love" 2>/dev/null || true

cd "$DIST/build"
zip -qr "../$APP-$VERSION.muxapp" . -x '*.DS_Store'
echo "==> dist/$APP-$VERSION.muxapp"
ls -lh "$DIST/$APP-$VERSION.muxapp"
