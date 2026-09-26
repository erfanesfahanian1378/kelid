"""Task 6.13: held-out evaluation sets — `eval/fa_formal.txt` (held-out
Wikipedia sentences), `eval/fa_informal.txt` (subtitle-style sentences, if
available), `eval/en.txt` — 5 000 sentences each, never used for counting."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

DEFAULT_EVAL_SIZE = 5000


def build_eval_set(sentences: Iterable[str], limit: int = DEFAULT_EVAL_SIZE) -> list[str]:
    result: list[str] = []
    for sentence in sentences:
        if not sentence.strip():
            continue
        result.append(sentence.strip())
        if len(result) >= limit:
            break
    return result


def write_eval_set(sentences: list[str], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as f:
        for sentence in sentences:
            f.write(sentence + "\n")


def read_eval_set(path: Path) -> list[str]:
    with path.open(encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def coverage_and_oov(eval_sentences: Iterable[str], vocab: set[str], word_tokenize) -> tuple[float, float]:  # noqa: ANN001
    """Fraction of eval-set word tokens that ARE in `vocab` (coverage) and
    that are NOT (`oov` rate); `word_tokenize` is injected (rather than
    imported directly) so this stays usable for either language's
    tokenizer without a hard import-time dependency between modules."""
    total = 0
    out_of_vocab = 0
    for sentence in eval_sentences:
        for token in word_tokenize(sentence):
            total += 1
            if token not in vocab:
                out_of_vocab += 1
    if total == 0:
        return (0.0, 0.0)
    oov_rate = out_of_vocab / total
    return (1.0 - oov_rate, oov_rate)
