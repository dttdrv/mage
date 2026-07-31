APP = .build/Mage.app
BIN = $(APP)/Contents/MacOS/Mage
SRC = $(wildcard Sources/*.swift)

.PHONY: all build icons run install clean

all: build

build: $(BIN) icons

# macOS 27 SDK turns @State into a macro whose plugin (SwiftUIMacros) ships
# only with Xcode; build against the 26 SDK so plain swiftc (CLT) works.
SDK = /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk

# actool requires Xcode (CLT's shim refuses); use the Xcode 27 beta toolchain.
DEVELOPER_DIR = $(CURDIR)/../../toolchains/Xcode-27-beta-3/Xcode-beta.app/Contents/Developer

$(BIN): $(SRC) Resources/Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	swiftc $(SRC) -sdk $(SDK) -target arm64-apple-macos26.0 -O -framework AppKit -framework SwiftUI -o $(BIN)

# Adaptive app icon: light (+ optional dark) 1024x1024 PNGs are the source of
# truth — drop in replacements and `make` picks them up. render-icons.swift
# generates placeholders only when the PNGs are missing.
ICONSET = Resources/Assets.xcassets/AppIcon.appiconset
ICONS = $(APP)/Contents/Resources/Assets.car

icons: $(ICONS)

$(ICONS): $(ICONSET)/icon-16@1x.png
	mkdir -p $(APP)/Contents/Resources
	DEVELOPER_DIR=$(DEVELOPER_DIR) actool --compile $(APP)/Contents/Resources \
		--platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
		--output-partial-info-plist .build/actool-partial.plist Resources/Assets.xcassets >/dev/null

# Regenerate all catalog sizes whenever the 1024px sources change.
$(ICONSET)/icon-16@1x.png: Resources/Icon/icon-light.png Resources/Icon/icon-dark.png
	for size in 16 32 128 256 512; do \
		for scale in 1 2; do \
			px=$$((size * scale)); \
			sips -z $$px $$px Resources/Icon/icon-light.png --out $(ICONSET)/icon-$${size}@$${scale}x.png >/dev/null; \
			sips -z $$px $$px Resources/Icon/icon-dark.png  --out $(ICONSET)/icon-$${size}@$${scale}x-dark.png >/dev/null; \
		done; \
	done

Resources/Icon/icon-light.png Resources/Icon/icon-dark.png:
	swift tools/render-icons.swift

run: build
	open $(APP)

install: build
	ditto $(APP) /Applications/Mage.app

clean:
	rm -rf .build
