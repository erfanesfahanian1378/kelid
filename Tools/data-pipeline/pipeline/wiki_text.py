"""Task 6.5: `wikiextractor` output (JSON Lines, one article per line, each
with a `text` field of mostly-clean plain text) -> plain paragraphs, with
the title line, reference/table leftovers, and short lists (< 3 words)
dropped.

`run_wikiextractor` shells out to the `wikiextractor` CLI (the
`wikiextractor` PyPI package) against a downloaded dump — not invoked in
Phase 6's own session (see `README.md`); `iter_paragraphs_from_directory`
and `extract_paragraphs_from_json_line` are what actually get tested, since
they only need wikiextractor's *output format*, not the tool itself or a
real multi-GB dump.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from collections.abc import Iterator
from pathlib import Path

_MIN_WORDS = 3


def is_held_out(article_id: str, modulus: int = 100) -> bool:
    """Task 6.6: "hold out every article whose ID hash mod 100 == 0 for
    evaluation (never counted)." A hash of the id (not the id itself) is
    used so held-out articles are evenly distributed regardless of how
    Wikipedia happens to have assigned ids — deterministic across runs
    since it only depends on the id string, not on run order or timing."""
    digest = hashlib.sha256(article_id.encode("utf-8")).hexdigest()
    return int(digest, 16) % modulus == 0


def extract_paragraphs_from_json_line(line: str) -> list[str]:
    """One wikiextractor JSONL line -> its plain-text paragraphs, dropping
    the repeated title line, blank lines, and anything under `_MIN_WORDS`
    words (residual reference markers, list bullets wikiextractor's own
    cleanup didn't fully strip, table fragments, etc.)."""
    article = json.loads(line)
    title = article.get("title", "")
    text = article.get("text", "")

    paragraphs: list[str] = []
    for raw_paragraph in text.split("\n"):
        paragraph = raw_paragraph.strip()
        if not paragraph or paragraph == title:
            continue
        if len(paragraph.split()) < _MIN_WORDS:
            continue
        paragraphs.append(paragraph)
    return paragraphs


def iter_articles_from_directory(directory: Path) -> Iterator[dict]:
    """Walks wikiextractor's output tree (`AA/wiki_00`, `AA/wiki_01`, `AB/wiki_00`, ...
    — each a JSONL file with no extension) and yields each article's parsed
    JSON object, so callers needing `id`/`title` (e.g. the held-out-article
    hash split, task 6.6) don't have to re-derive them from paragraphs alone."""
    for path in sorted(directory.rglob("wiki_*")):
        if not path.is_file():
            continue
        with path.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    yield json.loads(line)


def iter_paragraphs_from_directory(directory: Path) -> Iterator[tuple[str, list[str]]]:
    """Yields `(article_id, paragraphs)` for every article under a
    wikiextractor output directory."""
    for article in iter_articles_from_directory(directory):
        title = article.get("title", "")
        text = article.get("text", "")
        paragraphs = [
            p
            for raw in text.split("\n")
            if (p := raw.strip()) and p != title and len(p.split()) >= _MIN_WORDS
        ]
        yield str(article.get("id", "")), paragraphs


def run_wikiextractor(dump_path: Path, output_dir: Path, processes: int | None = None) -> None:
    """Shells out to `wikiextractor` (the PyPI package's CLI) with `--json`
    so its output matches what this module's readers expect. Not exercised
    in this session — see `README.md`."""
    output_dir.mkdir(parents=True, exist_ok=True)
    command = ["python3", "-m", "wikiextractor.WikiExtractor", str(dump_path), "-o", str(output_dir), "--json"]
    if processes:
        command += ["--processes", str(processes)]
    subprocess.run(command, check=True)  # noqa: S603 - fixed argv, no shell, no untrusted input
