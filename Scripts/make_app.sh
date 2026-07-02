#!/bin/bash
#
# Assemble a proper macOS .app bundle from the SwiftPM release executable.
# Produces ./UsageMeter.app (menu-bar-only via LSUIElement).
#
# Usage:
#   ./Scripts/make_app.sh              # build + ad-hoc sign (local / quick runs)
#   ./Scripts/make_app.sh --run        # …and launch it
#   ./Scripts/make_app.sh --release    # Developer ID sign + hardened runtime,
#                                      #   notarize (notarytool), staple, and zip
#
# --release needs a "Developer ID Application" identity in the keychain and a
# notarytool credential source (a stored keychain profile named "usagemeter-notary",
# or the App Store Connect API key at ~/.appstoreconnect). Without those it errors
# with instructions instead of silently shipping an unsigned build.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="UsageMeter"
BUNDLE_ID="com.omeryasir.usagemeter"   # unified with the App Store target (project.yml)

# Single source of truth for version/build — the VERSION file (line 1 = marketing
# version, line 2 = build number). Keeps the GitHub zip and the App Store archive
# from drifting (they used to be hand-edited in two places).
VERSION="$(sed -n '1p' VERSION 2>/dev/null || echo '0.0.0')"
BUILD="$(sed -n '2p' VERSION 2>/dev/null || echo '1')"
CONFIG="release"

MODE="adhoc"
LAUNCH="no"
for arg in "$@"; do
  case "$arg" in
    --release) MODE="release" ;;
    --run)     LAUNCH="yes" ;;
  esac
done

APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "▸ Building ${APP_NAME} ${VERSION} (build ${BUILD}, ${CONFIG})…"
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

# App icon (.icns). Regenerate from code with: make icon
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
else
  echo "  (Resources/AppIcon.icns missing — run 'make icon'; building without an icon)"
fi

# Apple privacy manifest ("Data Not Collected"). Harmless in the ad-hoc build; the
# App Store target bundles it via project.yml.
[[ -f "Resources/PrivacyInfo.xcprivacy" ]] && cp "Resources/PrivacyInfo.xcprivacy" "${RES_DIR}/PrivacyInfo.xcprivacy"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
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

if [[ "${MODE}" == "release" ]]; then
  # -------- Developer ID signing + notarization --------
  DEVID_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"$/\1/')"
  if [[ -z "${DEVID_IDENTITY}" ]]; then
    echo "✗ No 'Developer ID Application' identity in the keychain." >&2
    echo "  Create one at https://developer.apple.com/account/resources/certificates/add" >&2
    echo "  (Account Holder only), download the .cer, and double-click to install." >&2
    exit 1
  fi
  echo "▸ Developer ID signing with: ${DEVID_IDENTITY}"
  # Hardened runtime + secure timestamp are required for notarization. No --deep
  # (deprecated); this bundle has a single executable and no nested code.
  codesign --force --options runtime --timestamp \
    --sign "${DEVID_IDENTITY}" "${MACOS_DIR}/${APP_NAME}"
  codesign --force --options runtime --timestamp \
    --sign "${DEVID_IDENTITY}" "${APP_DIR}"
  codesign --verify --strict --verbose=2 "${APP_DIR}"

  ZIP_PATH="${APP_NAME}-macOS.zip"
  echo "▸ Zipping for notarization → ${ZIP_PATH}"
  ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"

  # Credential source for notarytool: prefer a stored keychain profile; else the
  # App Store Connect API key on disk.
  NOTARY_ARGS=()
  if xcrun notarytool history --keychain-profile usagemeter-notary >/dev/null 2>&1; then
    NOTARY_ARGS=(--keychain-profile usagemeter-notary)
  elif [[ -f "${HOME}/.appstoreconnect/api_key.json" ]]; then
    KID="$(python3 -c "import json;print(json.load(open('${HOME}/.appstoreconnect/api_key.json'))['key_id'])")"
    ISS="$(python3 -c "import json;print(json.load(open('${HOME}/.appstoreconnect/api_key.json'))['issuer_id'])")"
    P8="${HOME}/.appstoreconnect/private_keys/AuthKey_${KID}.p8"
    NOTARY_ARGS=(--key "${P8}" --key-id "${KID}" --issuer "${ISS}")
  else
    echo "✗ No notarytool credentials. Store a profile with:" >&2
    echo "  xcrun notarytool store-credentials usagemeter-notary --key <p8> --key-id <id> --issuer <uuid>" >&2
    exit 1
  fi

  echo "▸ Submitting to Apple notary service (this can take a few minutes)…"
  xcrun notarytool submit "${ZIP_PATH}" "${NOTARY_ARGS[@]}" --wait

  echo "▸ Stapling the ticket…"
  xcrun stapler staple "${APP_DIR}"
  xcrun stapler validate "${APP_DIR}"
  spctl --assess --type execute --verbose=4 "${APP_DIR}" || true

  # Re-zip the STAPLED app so the download works fully offline.
  rm -f "${ZIP_PATH}"
  ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
  echo "✓ Notarized, stapled, and zipped → ${ZIP_PATH}"
else
  # -------- Ad-hoc (local/quick) --------
  if command -v codesign >/dev/null 2>&1; then
    echo "▸ Ad-hoc codesigning…"
    codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || \
      echo "  (codesign skipped — not fatal for local runs)"
  fi
fi

echo "✓ Built ${APP_DIR}"

if [[ "${LAUNCH}" == "yes" ]]; then
  echo "▸ Launching…"
  open "${APP_DIR}"
fi
