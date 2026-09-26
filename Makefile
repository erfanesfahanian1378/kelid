# Kelid — developer commands. See PLAN.md §5.2 and README.md.

SIM ?= platform=iOS Simulator,name=iPhone 17

.PHONY: gen build test test-mac test-ios lint format klm data-quick data-full data-test clean

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

# Task 7.4: builds both languages' .klm files from the quick/full pipeline's
# unigram TSVs (run `make data-quick` or `make data-full` first) into
# Keyboard/Resources/LM/, where the keyboard extension target bundles them
# (task 7.5 — not in the KelidKit package, since only the extension ships
# them).
klm:
	mkdir -p Keyboard/Resources/LM
	cd Tools/klm && swift run klm build --lang fa --unigrams ../data-pipeline/out/fa.unigrams.tsv --out ../../Keyboard/Resources/LM/fa.klm
	cd Tools/klm && swift run klm build --lang en --unigrams ../data-pipeline/out/en.unigrams.tsv --out ../../Keyboard/Resources/LM/en.klm

# Task 6.3: hermitdave word-frequency lists -> out/{fa,en}.unigrams.tsv.
# Finishes in seconds, not the "under 5 minutes" acceptance criterion's
# worst case — good enough to unblock Phase 7 without the full pipeline.
data-quick:
	cd Tools/data-pipeline && uv sync --group dev && uv run python -m pipeline.quick

# Task 6.4-6.14: the full Wikipedia-based pipeline (downloads, extraction,
# DuckDB counting, vocabulary selection, export, emoji data, eval sets,
# reports). Runs for hours and needs ~30 GB free disk — see
# Tools/data-pipeline/README.md before running it.
data-full:
	cd Tools/data-pipeline && uv sync --group dev && uv run python -m pipeline.full

data-test:
	cd Tools/data-pipeline && uv sync --group dev && uv run pytest

clean:
	rm -rf Kelid.xcodeproj
	rm -rf Packages/KelidKit/.build
	rm -rf Tools/klm/.build
	rm -rf ~/Library/Developer/Xcode/DerivedData/Kelid-*
