#!/bin/zsh
set -e
SCRATCH="/private/tmp/claude-501/-Users-omeryasironal-Projects-usage-meter/86cdfb92-717b-4f50-98c8-82f6be0c8c56/scratchpad"
REPO="/Users/omeryasironal/Projects/usage-meter"
cd "$REPO"

echo "### [1/5] xcodegen generate (local-only: APPSTORE flag, v1.0.0 build 7)"
xcodegen generate

echo "### [2/5] archive UsageMeterApp"
rm -rf "$SCRATCH/UsageMeter_v1.xcarchive"
xcodebuild archive -project UsageMeter.xcodeproj -scheme UsageMeterApp \
  -destination 'generic/platform=macOS' \
  -archivePath "$SCRATCH/UsageMeter_v1.xcarchive" \
  -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic

APP="$SCRATCH/UsageMeter_v1.xcarchive/Products/Applications/UsageMeter.app"
BIN="$APP/Contents/MacOS/UsageMeter"

echo "### [3/5] VERIFY local-only strip + versions"
if otool -L "$BIN" | grep -qi webkit; then echo "!!! ABORT: WebKit still linked — NOT the local-only build"; exit 2; fi
echo "   [OK] no WebKit linked"
strings "$BIN" | grep -i "unofficial usage endpoint" && { echo "!!! ABORT: ToS string present"; exit 2; } || echo "   [OK] no ToS/account string"
V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
B=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "   version=$V build=$B"
[[ "$V" == "1.0.0" && "$B" == "7" ]] || { echo "!!! ABORT: wrong version/build"; exit 2; }
plutil -p "$APP/Contents/Info.plist" | grep -i ITSApp || echo "   [WARN] no ITSApp key"

echo "### [4/5] export (app-store-connect .pkg)"
rm -rf "$SCRATCH/export_v1"
xcodebuild -exportArchive -archivePath "$SCRATCH/UsageMeter_v1.xcarchive" \
  -exportOptionsPlist "$SCRATCH/ExportOptions.plist" -exportPath "$SCRATCH/export_v1" \
  -allowProvisioningUpdates

echo "### [5/5] upload via altool"
PKG=$(ls "$SCRATCH/export_v1"/*.pkg 2>/dev/null | head -1)
echo "PKG=$PKG"
xcrun altool --upload-app -f "$PKG" -t macos \
  --apiKey 93HFBMV3MA --apiIssuer 3894e346-c886-4ca5-91b7-773aaa6e85bd

echo "### V1 UPLOAD DONE"
