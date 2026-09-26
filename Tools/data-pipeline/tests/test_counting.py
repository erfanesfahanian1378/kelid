"""Task 6.7's required test: "the DuckDB counting SQL on a 20-sentence
fixture gives exact expected counts." The fixture below has 20 sentences
built from 4 repeated patterns, chosen so every expected count can be
verified by hand (see the comment above each pattern) and so at least one
bigram/trigram falls below the `min_ngram_count=3` threshold and must be
dropped.
"""

from __future__ import annotations

from pipeline.counting import count_ngrams, sentences_to_tokens

# Pattern A x9: "<s> من کتاب را دوست دارم"
# Pattern B x5: "<s> من کتاب خواندم"
# Pattern C x4: "<s> او کتاب را خواند"
# Pattern D x2: "<s> کتاب جالب است"   (every n>=2 gram from this pattern has
#                                       count 2 and must be dropped)
_PATTERN_A = ["<s>", "من", "کتاب", "را", "دوست", "دارم"]
_PATTERN_B = ["<s>", "من", "کتاب", "خواندم"]
_PATTERN_C = ["<s>", "او", "کتاب", "را", "خواند"]
_PATTERN_D = ["<s>", "کتاب", "جالب", "است"]

_SENTENCES = [_PATTERN_A] * 9 + [_PATTERN_B] * 5 + [_PATTERN_C] * 4 + [_PATTERN_D] * 2
assert len(_SENTENCES) == 20


def _as_dict(rows: list[tuple], key_len: int) -> dict[tuple, int]:
    return {row[:key_len]: row[-1] for row in rows}


def test_unigram_counts_are_exact() -> None:
    counts = count_ngrams(sentences_to_tokens(_SENTENCES))
    unigrams = _as_dict(counts["unigrams"], 1)
    assert unigrams[("<s>",)] == 20
    assert unigrams[("من",)] == 14  # 9 (A) + 5 (B)
    assert unigrams[("کتاب",)] == 20  # 9 + 5 + 4 + 2
    assert unigrams[("را",)] == 13  # 9 (A) + 4 (C)
    assert unigrams[("دوست",)] == 9
    assert unigrams[("دارم",)] == 9
    assert unigrams[("خواندم",)] == 5
    assert unigrams[("او",)] == 4
    assert unigrams[("خواند",)] == 4
    assert unigrams[("جالب",)] == 2
    assert unigrams[("است",)] == 2


def test_bigram_counts_are_exact_and_below_threshold_dropped() -> None:
    counts = count_ngrams(sentences_to_tokens(_SENTENCES), min_ngram_count=3)
    bigrams = _as_dict(counts["bigrams"], 2)

    assert bigrams[("<s>", "من")] == 14  # A + B
    assert bigrams[("من", "کتاب")] == 14  # A + B
    assert bigrams[("کتاب", "را")] == 13  # A + C
    assert bigrams[("را", "دوست")] == 9  # A only
    assert bigrams[("دوست", "دارم")] == 9  # A only
    assert bigrams[("کتاب", "خواندم")] == 5  # B only
    assert bigrams[("<s>", "او")] == 4  # C only
    assert bigrams[("او", "کتاب")] == 4  # C only
    assert bigrams[("را", "خواند")] == 4  # C only

    # Pattern D's bigrams all occur exactly twice — below min_ngram_count=3 — and must not appear at all.
    assert ("<s>", "کتاب") not in bigrams
    assert ("کتاب", "جالب") not in bigrams
    assert ("جالب", "است") not in bigrams

    assert len(bigrams) == 9


def test_trigram_counts_are_exact_and_below_threshold_dropped() -> None:
    counts = count_ngrams(sentences_to_tokens(_SENTENCES), min_ngram_count=3)
    trigrams = _as_dict(counts["trigrams"], 3)

    assert trigrams[("<s>", "من", "کتاب")] == 14  # A + B
    assert trigrams[("من", "کتاب", "را")] == 9  # A only
    assert trigrams[("کتاب", "را", "دوست")] == 9  # A only
    assert trigrams[("را", "دوست", "دارم")] == 9  # A only
    assert trigrams[("من", "کتاب", "خواندم")] == 5  # B only
    assert trigrams[("<s>", "او", "کتاب")] == 4  # C only
    assert trigrams[("او", "کتاب", "را")] == 4  # C only
    assert trigrams[("کتاب", "را", "خواند")] == 4  # C only

    assert ("<s>", "کتاب", "جالب") not in trigrams
    assert ("کتاب", "جالب", "است") not in trigrams

    assert len(trigrams) == 8


def test_min_ngram_count_threshold_is_configurable() -> None:
    # Lowering the threshold to 2 must bring pattern D's bigrams back.
    counts = count_ngrams(sentences_to_tokens(_SENTENCES), min_ngram_count=2)
    bigrams = _as_dict(counts["bigrams"], 2)
    assert bigrams[("<s>", "کتاب")] == 2
    assert bigrams[("کتاب", "جالب")] == 2
    assert bigrams[("جالب", "است")] == 2
