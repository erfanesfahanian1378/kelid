# Kelid — developer commands. See PLAN.md §5.2 and README.md.

SIM ?= platform=iOS Simulator,name=iPhone 17

.PHONY: gen build test test-mac test-ios lint format klm data-quick data-full clean

gen:
	xcodegen generate

build: gen
	xcodebuild -scheme Kelid -destination 'generic/platform=iOS Simulator' build

test: test-mac test-ios

test-mac:
	swift test --package-path Packages/KelidKit

test-ios: gen
	cd Packages/KelidKit && xcodebuild test -scheme KelidKit-Package -destination "$(SIM)"

lint:
	swiftformat --lint .
	swiftlint
	./Tools/scripts/lint-no-network.sh

format:
	swiftformat .

# Placeholder until Phase 6+ builds the real klm tool and data pipeline.
klm:
	cd Tools/klm && swift build

data-quick:
	@echo "data-quick: language data pipeline arrives in Phase 6 (PLAN.md §8)."

data-full:
	@echo "data-full: language data pipeline arrives in Phase 6 (PLAN.md §8)."

clean:
	rm -rf Kelid.xcodeproj
	rm -rf Packages/KelidKit/.build
	rm -rf Tools/klm/.build
	rm -rf ~/Library/Developer/Xcode/DerivedData/Kelid-*
