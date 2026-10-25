APP_NAME := ScannerBooth
PROJECT := ScannerBooth.xcodeproj
SCHEME := ScannerBooth
CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS,name=My Mac
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

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
		'  run           Build and launch the app' \
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

run: app
	open -n "$(APP_BUNDLE)"

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
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	open -n "$(INSTALLED_APP)"

clean:
	rm -rf "$(BUILD_DIR)"
