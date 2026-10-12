#!/bin/bash
set -euo pipefail
echo "Removing SottoAudio.driver (requires your password)…"
sudo rm -rf "/Library/Audio/Plug-Ins/HAL/SottoAudio.driver"
sudo killall coreaudiod || true
echo "Removed."
