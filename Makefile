.PHONY: build test app run clean release-app icon xcodeproj demo install

# Build the SwiftPM package (debug).
build:
	swift build

# Run the headless engine test suite (Sources B/C + cost/block math).
test:
	swift test

# Regenerate the app icon from code (pure CoreGraphics → .icns + Assets.xcassets).
icon:
	./Scripts/make_icons.sh

# Assemble UsageMeter.app (release) with a proper Info.plist (LSUIElement) + icon.
app:
	./Scripts/make_app.sh

# Assemble and launch the menu-bar app.
run:
	./Scripts/make_app.sh --run

# Build a Developer-ID-signed, notarized, stapled UsageMeter-macOS.zip for the
# GitHub download (no Gatekeeper warning). Needs a "Developer ID Application"
# cert in the keychain + notarytool credentials — see Scripts/make_app.sh.
release-app:
	./Scripts/make_app.sh --release

# Generate the Xcode app target (for Mac App Store archiving). Needs XcodeGen
# (brew install xcodegen). The SwiftPM build stays the source of truth for tests.
xcodeproj:
	xcodegen generate
	@echo "✓ UsageMeter.xcodeproj generated — open in Xcode, set your Team, then Product ▸ Archive."

# Launch with synthetic, PII-free data for screenshots.
demo: app
	@pkill -f "UsageMeter.app/Contents/MacOS/UsageMeter" 2>/dev/null || true
	@USAGEMETER_DEMO=1 "$(CURDIR)/UsageMeter.app/Contents/MacOS/UsageMeter" >/dev/null 2>&1 &
	@echo "✓ Demo launched — click the gauge in the menu bar, then 'Dashboard'. (Fake data.)"

# Build and install into /Applications (so it lives like a normal app).
install: app
	rm -rf /Applications/UsageMeter.app
	cp -R UsageMeter.app /Applications/UsageMeter.app
	@echo "✓ Installed to /Applications/UsageMeter.app — launch from Spotlight or Finder."

clean:
	rm -rf .build UsageMeter.app
