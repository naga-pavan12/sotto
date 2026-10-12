#!/bin/bash
# Install the Sotto audio driver system-wide. Requires admin rights and briefly
# restarts Core Audio (all audio drops for 1-2 seconds). Don't run mid-call.
set -euo pipefail
SRC="driver/build/SottoAudio.driver"
DEST="/Library/Audio/Plug-Ins/HAL"
if [ ! -d "$SRC" ]; then
  echo "error: $SRC not found. Run 'make driver' first." >&2
  exit 1
fi
echo "Installing SottoAudio.driver to $DEST (requires your password)…"
sudo rm -rf "$DEST/SottoAudio.driver"
sudo cp -R "$SRC" "$DEST/SottoAudio.driver"
sudo chown -R root:wheel "$DEST/SottoAudio.driver"
echo "Restarting coreaudiod…"
sudo killall coreaudiod || true
echo "Done. 'Sotto Microphone' should appear in Audio settings in a moment."
