APP_NAME   := OpenRest
VERSION    := $(shell grep -E '^version:' pubspec.yaml | sed -E 's/version: *([^+ ]+).*/\1/')
BUILD_DIR  := build
APP_PATH   := $(BUILD_DIR)/macos/Build/Products/Release/$(APP_NAME).app
DMG_STAGE  := $(BUILD_DIR)/dmg
DMG_PATH   := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

.PHONY: help deps analyze test run build-macos dmg open-dmg clean version

help:
	@echo "Targets:"
	@echo "  deps         flutter pub get"
	@echo "  analyze      flutter analyze"
	@echo "  test         flutter test"
	@echo "  run          run the app on macOS"
	@echo "  build-macos  release build of $(APP_NAME).app"
	@echo "  dmg          build app and package $(DMG_PATH)"
	@echo "  open-dmg     open the built DMG"
	@echo "  version      print version from pubspec.yaml"
	@echo "  clean        flutter clean and remove DMG artifacts"

version:
	@echo $(VERSION)

deps:
	flutter pub get

analyze:
	flutter analyze

test:
	flutter test

run:
	flutter run -d macos

build-macos:
	flutter build macos --release

dmg: build-macos
	rm -rf $(DMG_STAGE) $(DMG_PATH)
	mkdir -p $(DMG_STAGE)
	cp -R $(APP_PATH) $(DMG_STAGE)/
	ln -s /Applications $(DMG_STAGE)/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(DMG_STAGE) -ov -format UDZO $(DMG_PATH)
	rm -rf $(DMG_STAGE)
	@echo "Created $(DMG_PATH)"

open-dmg:
	open $(DMG_PATH)

clean:
	flutter clean
	rm -rf $(DMG_STAGE) $(BUILD_DIR)/*.dmg
