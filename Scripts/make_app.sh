#!/bin/bash
#
# Assemble a proper macOS .app bundle from the SwiftPM release executable.
# Produces ./UsageMeter.app (menu-bar-only via LSUIElement).
#
# Usage: ./Scripts/make_app.sh [--run]
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="UsageMeter"
BUNDLE_ID="com.yasir.usagemeter"
VERSION="0.1.0"
BUILD="1"
CONFIG="release"

APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "▸ Building ${APP_NAME} (${CONFIG})…"
swift build -c "${CONFIG}" --product "${APP_NAME}"

BIN_PATH="$(swift build -c "${CONFIG}" --product "${APP_NAME}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "✗ Executable not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "▸ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"

# Editable pricing table lives in the app's Resources (read via Bundle.main).
cp "Sources/UsageMeterKit/Resources/pricing.json" "${RES_DIR}/pricing.json"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>  <string>15.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key><string>UsageMeter — local, privacy-first Claude usage meter.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so launchd/SMAppService and TCC treat it as a stable identity.
if command -v codesign >/dev/null 2>&1; then
  echo "▸ Ad-hoc codesigning…"
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || \
    echo "  (codesign skipped — not fatal for local runs)"
fi

echo "✓ Built ${APP_DIR}"

if [[ "${1:-}" == "--run" ]]; then
  echo "▸ Launching…"
  open "${APP_DIR}"
fi
