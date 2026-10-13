#!/bin/bash
# Build a double-click installer that places the driver and app, then restarts
# Core Audio. Unsigned by default; pass a Developer ID to --sign for distribution.
set -euo pipefail
VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app/build/Sotto.app"
DRIVER="$ROOT/driver/build/SottoAudio.driver"
[ -d "$APP" ] || { echo "missing $APP — run 'make app'"; exit 1; }
[ -d "$DRIVER" ] || { echo "missing $DRIVER — run 'make driver'"; exit 1; }

STAGE="$(mktemp -d)"; SCRIPTS="$(mktemp -d)"
mkdir -p "$STAGE/Applications" "$STAGE/Library/Audio/Plug-Ins/HAL"
cp -R "$APP" "$STAGE/Applications/"
cp -R "$DRIVER" "$STAGE/Library/Audio/Plug-Ins/HAL/"

cat > "$SCRIPTS/postinstall" <<'SH'
#!/bin/bash
/usr/bin/killall coreaudiod 2>/dev/null || true
exit 0
SH
chmod +x "$SCRIPTS/postinstall"

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/Sotto-$VERSION.pkg"
pkgbuild --root "$STAGE" --scripts "$SCRIPTS" --install-location / \
  --identifier io.github.sotto-audio.installer --version "$VERSION" \
  --ownership recommended "$OUT"
rm -rf "$STAGE" "$SCRIPTS"
echo "built $OUT"
