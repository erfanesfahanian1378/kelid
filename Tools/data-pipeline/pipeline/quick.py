"""`make data-quick` (task 6.3): the fast path so Phase 7 can start before
the full Wikipedia-based pipeline (task 6.4+) finishes.

Downloads hermitdave's `fa_full.txt`/`en_full.txt` word-frequency lists,
normalizes every token with the shared `canonical()` (§6.6.2 — the same
function `PersianText` uses), keeps only structurally valid tokens for each
language, merges surface-form variants that share a canonical form (their
counts are summed), and writes `out/fa.unigrams.tsv`/`out/en.unigrams.tsv`
plus `out/quick.meta.json`.
"""

from __future__ import annotations

import argparse
import datetime
import json
import time
from pathlib import Path

import requests

from pipeline.normalize import canonical
from pipeline.vocab import valid_token_pattern

_ROOT = Path(__file__).resolve().parents[1]
_DATA_DIR = _ROOT / "data"
_OUT_DIR = _ROOT / "out"
_DOCS_DIR = _ROOT.parent.parent / "docs"

_HERMITDAVE_BASE = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018"
_SOURCES = {
    "fa": f"{_HERMITDAVE_BASE}/fa/fa_full.txt",
    "en": f"{_HERMITDAVE_BASE}/en/en_full.txt",
}
_LICENSE = "CC-BY-SA-4.0 (hermitdave/FrequencyWords content license; code is MIT)"


def _download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return  # already fetched — quick path re-runs should be idempotent
    dest.parent.mkdir(parents=True, exist_ok=True)
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    dest.write_bytes(response.content)


def build_unigrams_from_frequency_file(raw_path: Path, lang: str) -> tuple[dict[str, int], int, int]:
    """Parses a hermitdave-shaped `word count` frequency file into
    normalized-and-merged canonical-form counts. Returns
    `(counts, raw_line_count, kept_token_count)`. Also reused by
    `full.py`'s task 6.8 informal-merge step, not just this quick path."""
    pattern = valid_token_pattern(lang)
    counts: dict[str, int] = {}
    raw_lines = 0
    with raw_path.open(encoding="utf-8") as f:
        for line in f:
            raw_lines += 1
            parts = line.rstrip("\n").split(" ")
            if len(parts) != 2:
                continue
            word, count_str = parts
            try:
                count = int(count_str)
            except ValueError:
                continue
            normalized = canonical(word)
            if not pattern.match(normalized):
                continue
            counts[normalized] = counts.get(normalized, 0) + count
    return counts, raw_lines, len(counts)


def _write_tsv(counts: dict[str, int], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    ordered = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    with dest.open("w", encoding="utf-8") as f:
        for word, count in ordered:
            f.write(f"{word}\t{count}\n")


def _append_attribution() -> None:
    _DOCS_DIR.mkdir(parents=True, exist_ok=True)
    attributions_path = _DOCS_DIR / "ATTRIBUTIONS.md"
    marker = "## hermitdave/FrequencyWords (quick path, task 6.3)"
    if attributions_path.exists() and marker in attributions_path.read_text(encoding="utf-8"):
        return  # already recorded
    entry = (
        f"\n{marker}\n\n"
        f"- **Source:** {_HERMITDAVE_BASE}/{{fa,en}}/*_full.txt\n"
        f"- **License:** {_LICENSE}\n"
        f"- **Used for:** `out/fa.unigrams.tsv`, `out/en.unigrams.tsv` — the quick-path unigram "
        "frequency lists Phase 7's prediction lexicon starts from before the full Wikipedia-based "
        "pipeline (task 6.4+) replaces them with richer, deduplicated counts.\n"
    )
    with attributions_path.open("a", encoding="utf-8") as f:
        f.write(entry)


def run(data_dir: Path = _DATA_DIR, out_dir: Path = _OUT_DIR) -> dict:
    started = time.monotonic()
    fetched_at = datetime.datetime.now(datetime.UTC).isoformat()

    meta: dict = {"sources": {}, "license": _LICENSE, "fetchedAt": fetched_at, "languages": {}}
    for lang, url in _SOURCES.items():
        raw_path = data_dir / f"{lang}_full.txt"
        _download(url, raw_path)
        counts, raw_lines, kept = build_unigrams_from_frequency_file(raw_path, lang)
        _write_tsv(counts, out_dir / f"{lang}.unigrams.tsv")
        meta["sources"][lang] = url
        meta["languages"][lang] = {"rawLines": raw_lines, "keptTokens": kept}

    _append_attribution()

    meta["runTimeSeconds"] = round(time.monotonic() - started, 2)
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "quick.meta.json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return meta


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=_DATA_DIR)
    parser.add_argument("--out-dir", type=Path, default=_OUT_DIR)
    args = parser.parse_args()
    meta = run(data_dir=args.data_dir, out_dir=args.out_dir)
    print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
