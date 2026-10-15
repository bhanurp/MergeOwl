#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PRPulseApp"
BUILD_CONFIG="release"
INSTALL_ROOT="${1:-"$HOME/Applications/${APP_NAME}.app"}"
INFO_PLIST_TEMPLATE='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>PR Pulse</string>
    <key>CFBundleExecutable</key>
    <string>PRPulseApp</string>
    <key>CFBundleIdentifier</key>
    <string>dev.prpulse.app</string>
    <key>CFBundleName</key>
    <string>PRPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>PRPulse does not require microphone access.</string>
</dict>
</plist>'

echo "› Building ${APP_NAME} (${BUILD_CONFIG})"
cd "$ROOT_DIR"
swift build -c "${BUILD_CONFIG}"
BIN_DIR="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)"
APP_BINARY="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "$APP_BINARY" ]]; then
    echo "error: built binary not found at $APP_BINARY" >&2
    exit 1
fi

APP_CONTENTS="${INSTALL_ROOT}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_RESOURCES="${APP_CONTENTS}/Resources"

echo "› Creating app bundle at ${INSTALL_ROOT}"
mkdir -p "${APP_MACOS}" "${APP_RESOURCES}"
echo "$INFO_PLIST_TEMPLATE" > "${APP_CONTENTS}/Info.plist"
cp "${APP_BINARY}" "${APP_MACOS}/${APP_NAME}"
chmod +x "${APP_MACOS}/${APP_NAME}"
find "${BIN_DIR}" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "${APP_RESOURCES}" \;
bash "$ROOT_DIR/scripts/package_sparkle.sh" "$INSTALL_ROOT" "$BIN_DIR/Sparkle.framework"

echo "› Installed ${APP_NAME}. Launch it via Finder or:\n  open \"${INSTALL_ROOT}\""
