.PHONY: gen build test verify run placeholder-pet clean

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
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build | tail -20

verify: test build

run: build
	open $(DERIVED)/Build/Products/Debug/squai.app

clean:
	rm -rf build Packages/SquaiCore/.build
