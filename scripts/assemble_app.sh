#!/bin/bash
# Assemble Sotto.app from the built executable.
set -euo pipefail
APP="app/build/Sotto.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp app/.build/release/Sotto "$APP/Contents/MacOS/Sotto"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Sotto</string>
  <key>CFBundleIdentifier</key><string>io.github.sotto-audio.Sotto</string>
  <key>CFBundleName</key><string>Sotto</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><false/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSMicrophoneUsageDescription</key><string>Sotto captures your microphone to remove background noise.</string>
</dict></plist>
PLIST
echo "Assembled $APP"
