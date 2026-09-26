# Kelid language data pipeline (PLAN.md Phase 6)

Produces the Persian/English unigram/bigram/trigram counts, emoji data, and
evaluation sets Phase 7+'s prediction engine reads. Two paths:

- **Quick** (`make data-quick`, tasks 6.1–6.3): hermitdave word-frequency
  lists → normalized, filtered, merged unigrams. Finishes in seconds,
  needs no more than ~30 MB of disk, and is what Phase 7 actually starts
  from.
- **Full** (`make data-full`, tasks 6.4–6.14): the real Wikipedia-based
  pipeline — dump download, extraction, tokenization, DuckDB n-gram
  counting, an informal-text merge, vocabulary selection, export, emoji
  data, held-out evaluation sets, and per-language reports.

## Setup

```
uv sync --group dev
```

(`uv` manages a `.venv` here; plain `venv`/`pip install -e .[dev]` works too
if you don't have `uv`.) Requires Python ≥ 3.11.

`hazm` 0.10's sequence-tagger import chain pulls in a `scipy` build that
segfaults on import on at least one arm64 macOS setup this was developed on
(a broken `_propack` symbol in scipy 1.15.x's wheel) — `pyproject.toml` pins
`scipy==1.13.1` to route around it. Nothing here actually needs hazm's
tagger; only `hazm.normalizer`/`hazm.word_tokenize`/`hazm.sent_tokenize`
would be used if this pipeline called them (it currently implements
`canonical()`/`matchKey()`/`searchKey()` itself instead — see
`pipeline/normalize.py`'s own docstring for why).

## Commands

```
make data-quick   # from the repo root — tasks 6.1-6.3
make data-full    # tasks 6.4-6.14 — see "Disk and time" below first
make data-test    # runs this project's pytest suite
```

or, from this directory: `uv run python -m pipeline.quick`,
`uv run python -m pipeline.full`, `uv run pytest`.

## Disk and time

- **Quick path:** a few tens of MB, seconds to run.
- **Full path:** PLAN.md budgets **~30 GB free disk** and says to expect it
  to run for **hours** — Wikipedia dumps (fa + en) plus their extracted
  text, parquet shards, and DuckDB's temp files during counting all add up.
  Check `df -h` before running it. If you're tight on space, run one
  language at a time (`uv run python -m pipeline.full --lang fa`) and
  delete `data/<lang>_extracted/` once `out/<lang>.*.tsv` exist.

**This session's own environment had only ~26 GB free** (the plan's own
~30 GB minimum), so `pipeline/full.py` was written and every module it
calls (`download`, `wiki_text`, `tokenize`, `counting`, `informal_merge`,
`vocab`, `export`, `eval`, `report`) is unit-tested against small
fixtures — but the *real* multi-hour, multi-GB run against actual Wikipedia
dumps was deliberately not attempted here, to avoid filling your disk.
`make data-full` is a real, complete command whenever you have the room
and time for it — not a placeholder.

## Known gaps in the full path (as of Phase 6)

- **Wikimedia checksum fetching isn't wired into `full.py` yet.**
  `pipeline/download.py`'s `parse_wikimedia_checksums` is implemented and
  tested, but `run_language()` doesn't yet fetch the actual
  `<lang>wiki-latest-sha1sums.txt` index file before downloading the dump
  (task 6.4 asks for the download to be "verified against Wikimedia's
  published checksums"). Check the dump's index page
  (`https://dumps.wikimedia.org/<lang>wiki/latest/`) for the current
  checksum filename and pass its parsed digest as `expected_sha1` before a
  real run, or extend `run_language()` to fetch it automatically.
- **Lilak whitelist isn't sourced yet.** `pipeline/vocab.py`'s
  `select_vocabulary(..., lilak_words=...)` parameter and its "boost
  survives the cap" behavior are implemented and tested, but no
  `lilak_words` set is actually built from the real Lilak project
  (`github.com/b00f/lilak`) — that project ships a hunspell-format
  lexicon (`.dic`/`.aff` + build tooling), not a flat word list, so turning
  it into a plain Persian word set needs either running its own build or
  writing a hunspell dictionary "unmunch" step — neither attempted here.
  `select_vocabulary` works fine with `lilak_words=None` (no boost) in the
  meantime.
- **Offensive-word lists** (`offensive_fa.txt`/`offensive_en.txt`, task 6.9)
  don't exist yet either — `select_vocabulary(..., offensive_words=...)`
  is implemented and tested, but needs a curated list to actually flag
  anything. Source one before a real full run if word-flagging matters to
  you before Phase 8's autocorrect/Phase 9's blocklist work.
- **OPUS OpenSubtitles informal text** (task 6.8's optional
  `--with-opensubtitles-text` flag, "personal builds only") isn't
  implemented — `pipeline/informal_merge.py` only does the mandatory
  hermitdave-frequency merge.

None of these block `make data-quick` (which Phase 7 needs) or the emoji
pipeline (`make data-quick` doesn't run it; see below) — they're specifically
full-path refinements.

## Emoji data (task 6.12)

`uv run python -m pipeline.emoji` downloads Unicode's `emoji-test.txt` and
CLDR's fa/en annotation files (a few MB total, not part of the ~30 GB
Wikipedia budget) and writes
`Packages/KelidKit/Sources/EmojiData/emoji.json` (§6.9's schema) plus
`out/emoji_suggest_{fa,en}.tsv`. This **was** run for real in Phase 6 (1923
base emoji, ~344 KB, well under the ≤600 KB target) — it's not part of
`make data-quick`/`make data-full` since Phase 6's own acceptance criteria
don't ask for it there, but re-run it whenever Unicode/CLDR publish a new
emoji version.

## Shared normalization contract with Swift

`pipeline/normalize.py`'s `canonical()`/`match_key()`/`search_key()` are a
direct, scalar-by-scalar port of
`Packages/KelidKit/Sources/PersianText/PersianNormalization.swift` — both
sides are tested against the same
`Packages/KelidKit/Tests/PersianTextTests/vectors.json` fixture
(§6.6.7's minimum vector set) so they can't silently drift apart. If you
change one implementation, update the other and re-run both test suites.

## License / attribution

Every external data source this pipeline touches gets an entry appended to
`../../docs/ATTRIBUTIONS.md` automatically the first time it runs.
