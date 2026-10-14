.PHONY: gen build test verify run placeholder-pet clean

# `build` pipes xcodebuild into tail; `set -o pipefail` keeps a failed build from exiting 0.
# (.SHELLFLAGS needs GNU make >= 3.82; macOS ships 3.81, so pipefail is set inline.)
SHELL := /bin/bash

XCODEPROJ = Squai.xcodeproj
SCHEME = Squai
DERIVED = build/DerivedData

gen:
	xcodegen generate

placeholder-pet:
	swift Scripts/make-placeholder-pet.swift App/Squai/Resources/Pets/squai-default/spritesheet.png

test:
	swift test --package-path Packages/SquaiCore

build: gen
	set -o pipefail; xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build | tail -20

verify: test build

run: build
	open $(DERIVED)/Build/Products/Debug/squai.app

clean:
	rm -rf build Packages/SquaiCore/.build
