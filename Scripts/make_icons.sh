#!/bin/bash
#
# Generate the UsageMeter app icon — fully reproducible from code.
#
# Renders the "gaugefill" concept (a coral squircle + bright filled gauge arc
# showing the consumption level) at every macOS size via a pure CoreGraphics
# renderer (Scripts/icon/render.swift — headless, no display needed). Each size
# is rendered NATIVELY so the small-size-optimized variants (track/needle dropped
# when tiny) are baked into the iconset rather than naively downscaled.
#
# Outputs (committed):
#   Resources/AppIcon.icns                                  (for make_app.sh)
#   Resources/Assets.xcassets/AppIcon.appiconset/*.png      (for the Xcode/App Store target)
#
# Usage: ./Scripts/make_icons.sh [concept]      (default: gaugefill)
#
set -euo pipefail
cd "$(dirname "$0")/.."

CONCEPT="${1:-gaugefill}"
RENDER="Scripts/icon/render.swift"
ICONSET="$(mktemp -d)/AppIcon.iconset"
APPICONSET="Resources/Assets.xcassets/AppIcon.appiconset"

mkdir -p "${ICONSET}" "${APPICONSET}"

echo "▸ Rendering '${CONCEPT}' at all sizes (native per-size)…"

# Render one size to a file (native render → size-adaptive glyph).
render() { swift "${RENDER}" single "${CONCEPT}" "$1" "$2" >/dev/null; }

# macOS iconset entries: name -> pixel size
#   16@1x=16  16@2x=32  32@1x=32  32@2x=64  128@1x=128  128@2x=256
#   256@1x=256  256@2x=512  512@1x=512  512@2x=1024
declare -a ENTRIES=(
  "icon_16x16.png:16"     "icon_16x16@2x.png:32"
  "icon_32x32.png:32"     "icon_32x32@2x.png:64"
  "icon_128x128.png:128"  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"  "icon_512x512@2x.png:1024"
)

for e in "${ENTRIES[@]}"; do
  name="${e%%:*}"; px="${e##*:}"
  render "${ICONSET}/${name}" "${px}"
  cp "${ICONSET}/${name}" "${APPICONSET}/${name}"
done

# Asset-catalog manifest (macOS AppIcon set).
cat > "${APPICONSET}/Contents.json" <<'JSON'
{
  "images" : [
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16x16.png",      "scale" : "1x" },
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16x16@2x.png",   "scale" : "2x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32x32.png",      "scale" : "1x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32x32@2x.png",   "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png",    "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png",    "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png",    "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
JSON

echo "▸ Building Resources/AppIcon.icns…"
iconutil -c icns "${ICONSET}" -o Resources/AppIcon.icns

# Keep a 1024 master around for the README / App Store listing.
cp "${APPICONSET}/icon_512x512@2x.png" Resources/AppIcon-1024.png

rm -rf "$(dirname "${ICONSET}")"
echo "✓ Icon generated:"
echo "    Resources/AppIcon.icns"
echo "    ${APPICONSET}/ (10 PNGs + Contents.json)"
echo "    Resources/AppIcon-1024.png (master)"
