APP_NAME := ScannerBooth
PROJECT := ScannerBooth.xcodeproj
SCHEME := ScannerBooth
CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS,name=My Mac
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_BUNDLE := $(abspath $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app)
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

XCODE_DEVELOPER_DIR := $(shell xcode-select -p)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path)
HOST_ARCH := $(shell uname -m)
TEST_SWIFT_MODULE_DIR := $(XCODE_DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/usr/lib
TEST_FRAMEWORK_DIR := $(XCODE_DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/Library/Frameworks
APP_PRODUCTS := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)

# Keep the app sandbox enabled while allowing Apple's SwiftUI compiler macros
# to run in restricted build environments.
XCODEBUILD_SETTINGS := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- OTHER_SWIFT_FLAGS=-disable-sandbox

.DEFAULT_GOAL := help
.PHONY: help build run test test-typecheck open app open-app install-app clean

help:
	@printf '%s\n' \
		'Usage: make [target]' \
		'' \
		'Targets:' \
		'  help          Show this help (default)' \
		'  build         Build the macOS app with Xcode' \
		'  app           Alias for build; app bundle is placed in .build/' \
		'  run           Build, install, launch, and verify the running executable' \
		'  open          Open the Xcode project' \
		'  open-app      Build and launch the app bundle' \
		'  test          Type-check the XCTest sources' \
		'  test-typecheck Type-check the XCTest sources' \
		'  install-app   Build, copy to ~/Applications, and launch the app' \
		'  clean         Remove Xcode build products in .build/'

build:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(XCODEBUILD_SETTINGS) \
		build

app: build

run: install-app

open:
	open "$(PROJECT)"

open-app: run

# The project currently has no shared test scheme, so this target verifies
# that the XCTest source compiles but does not execute the test methods.
test: test-typecheck

test-typecheck: build
	swiftc -typecheck -disable-sandbox \
		-target "$(HOST_ARCH)-apple-macos14.0" \
		-sdk "$(MACOS_SDK)" \
		-module-cache-path "$(BUILD_DIR)/ModuleCache.noindex" \
		-I "$(TEST_SWIFT_MODULE_DIR)" \
		-F "$(TEST_FRAMEWORK_DIR)" \
		-I "$(APP_PRODUCTS)" \
		-F "$(APP_PRODUCTS)" \
		ScannerBoothTests/ScannerBoothTests.swift

install-app: app
	@killall -TERM "$(APP_NAME)" >/dev/null 2>&1 || true
	@attempt=0; while pgrep -x "$(APP_NAME)" >/dev/null 2>&1; do \
		if [ "$$attempt" -ge 10 ]; then echo 'Erreur : l’ancienne instance ne s’est pas arrêtée.' >&2; exit 1; fi; \
		sleep 1; attempt=$$((attempt + 1)); \
	done
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	cmp -s "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" "$(INSTALLED_APP)/Contents/MacOS/$(APP_NAME)"
	@printf '%s\n' 'Build et installation vérifiées : les exécutables sont identiques.'
	@printf 'SHA-256 build :      '
	@shasum -a 256 "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@printf 'SHA-256 installée :  '
	@shasum -a 256 "$(INSTALLED_APP)/Contents/MacOS/$(APP_NAME)"
	"$(LSREGISTER)" -f -R "$(INSTALLED_APP)"
	open -n "$(INSTALLED_APP)"
	@set -eu; executable="$(INSTALLED_APP)/Contents/MacOS/$(APP_NAME)"; attempt=0; \
	while [ "$$attempt" -lt 10 ]; do \
		for pid in $$(pgrep -x "$(APP_NAME)" || true); do \
			if lsof -a -p "$$pid" -d txt -Fn 2>/dev/null | grep -Fqx "n$$executable"; then \
				printf 'Processus vérifié : PID %s utilise %s\n' "$$pid" "$$executable"; exit 0; \
			fi; \
		done; \
		sleep 1; attempt=$$((attempt + 1)); \
	done; \
	echo "Erreur : ScannerBooth ne tourne pas depuis $$executable." >&2; exit 1

clean:
	rm -rf "$(BUILD_DIR)"
