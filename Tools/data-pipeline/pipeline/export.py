"""Task 6.10: writes `out/<lang>.unigrams.tsv` (`word, count, flags`),
`<lang>.bigrams.tsv` (`w1, w2, count`), `<lang>.trigrams.tsv`
(`w1, w2, w3, count`) and `<lang>.meta.json`."""

from __future__ import annotations

import json
from pathlib import Path


def export_unigrams(vocab: dict[str, dict], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    ordered = sorted(vocab.items(), key=lambda kv: (-kv[1]["count"], kv[0]))
    with dest.open("w", encoding="utf-8") as f:
        for word, info in ordered:
            f.write(f"{word}\t{info['count']}\t{','.join(info['flags'])}\n")


def export_ngrams(rows: list[tuple], dest: Path) -> None:
    """`rows` are already-ordered `(w1, ..., wn, count)` tuples (the shape
    `counting.count_ngrams`/`vocab.filter_ngrams` produce)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write("\t".join(str(v) for v in row) + "\n")


def export_meta(dest: Path, meta: dict) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write("\n")
