"""Task 6.8: boosts the Wikipedia-derived (formal) unigram counts with
hermitdave's frequency lists (colloquial subtitle/web text), so informal
forms like میخوام/اینجوری don't rank far too low purely because Wikipedia's
register is formal (the pitfall §8 Phase 6 explicitly calls out)."""

from __future__ import annotations

DEFAULT_INFORMAL_WEIGHT = 3.0


def informal_merge(
    corpus_unigrams: dict[str, int],
    hermitdave_unigrams: dict[str, int],
    weight: float = DEFAULT_INFORMAL_WEIGHT,
) -> dict[str, int]:
    """Adds `weight *` hermitdave's per-million-normalized frequency for
    each word to `corpus_unigrams`' raw count for that word (0 if the word
    doesn't appear in the corpus at all — a purely-colloquial word can still
    enter the vocabulary this way). Returns a new dict; neither input is
    mutated."""
    total = sum(hermitdave_unigrams.values())
    merged = dict(corpus_unigrams)
    if total == 0:
        return merged
    for word, count in hermitdave_unigrams.items():
        per_million = count / total * 1_000_000
        merged[word] = merged.get(word, 0) + round(per_million * weight)
    return merged
