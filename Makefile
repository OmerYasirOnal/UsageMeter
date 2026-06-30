.PHONY: build test app run clean release-app

# Build the SwiftPM package (debug).
build:
	swift build

# Run the headless engine test suite (Sources B/C + cost/block math).
test:
	swift test

# Assemble UsageMeter.app (release) with a proper Info.plist (LSUIElement).
app:
	./Scripts/make_app.sh

# Assemble and launch the menu-bar app.
run:
	./Scripts/make_app.sh --run

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
