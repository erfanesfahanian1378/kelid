"""Task 6.14: `reports/<lang>.md` — top 200 words, top-10 continuations for
probe contexts, coverage/OOV on the eval set, run time and output sizes."""

from __future__ import annotations

from pathlib import Path

DEFAULT_PROBE_CONTEXTS = {
    "fa": ["<s>", "من", "می‌خواهم", "در", "به"],
    "en": ["<s>", "the", "I"],
}


def top_continuations(bigrams: list[tuple[str, str, int]], context: str, limit: int = 10) -> list[tuple[str, int]]:
    """`bigrams` is `(w1, w2, count)` rows, already sorted by count
    descending (as `counting.count_ngrams` returns them) — filtering
    preserves that order, so no re-sort is needed here."""
    return [(w2, count) for w1, w2, count in bigrams if w1 == context][:limit]


def render_report(
    lang: str,
    top_words: list[tuple[str, int]],
    continuations_by_context: dict[str, list[tuple[str, int]]],
    coverage: float,
    oov_rate: float,
    run_time_seconds: float,
    output_sizes: dict[str, int],
) -> str:
    lines = [f"# {lang} language data report", ""]

    lines.append("## Top 200 words")
    lines.append("")
    lines.append("| Rank | Word | Count |")
    lines.append("|---|---|---|")
    for rank, (word, count) in enumerate(top_words[:200], start=1):
        lines.append(f"| {rank} | {word} | {count} |")
    lines.append("")

    lines.append("## Top continuations for probe contexts")
    lines.append("")
    for context, continuations in continuations_by_context.items():
        lines.append(f"**`{context}`** -> " + ", ".join(f"{w} ({c})" for w, c in continuations))
    lines.append("")

    lines.append("## Evaluation")
    lines.append("")
    lines.append(f"- Coverage: {coverage:.2%}")
    lines.append(f"- OOV rate: {oov_rate:.2%}")
    lines.append("")

    lines.append("## Run info")
    lines.append("")
    lines.append(f"- Run time: {run_time_seconds:.1f}s")
    for name, size_bytes in output_sizes.items():
        lines.append(f"- `{name}`: {size_bytes / 1024:.1f} KB")
    lines.append("")

    return "\n".join(lines)


def write_report(dest: Path, content: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding="utf-8")
