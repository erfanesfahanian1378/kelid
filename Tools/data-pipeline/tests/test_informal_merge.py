from __future__ import annotations

from pipeline.informal_merge import informal_merge


def test_informal_merge_boosts_existing_words() -> None:
    corpus = {"سلام": 1000}
    hermitdave = {"سلام": 500_000, "خداحافظ": 500_000}  # each is 50% of the 1M total
    merged = informal_merge(corpus, hermitdave, weight=3.0)
    # per_million for "سلام" = 500_000. boost = 500_000 * 3.0 = 1_500_000.
    assert merged["سلام"] == 1000 + 1_500_000


def test_informal_merge_can_introduce_words_missing_from_the_corpus() -> None:
    corpus = {"سلام": 1000}
    hermitdave = {"اینجوری": 1_000_000}  # 100% of a 1M total -> per_million = 1_000_000
    merged = informal_merge(corpus, hermitdave, weight=3.0)
    assert merged["اینجوری"] == 3_000_000


def test_informal_merge_does_not_mutate_inputs() -> None:
    corpus = {"سلام": 1000}
    hermitdave = {"سلام": 100}
    informal_merge(corpus, hermitdave)
    assert corpus == {"سلام": 1000}
