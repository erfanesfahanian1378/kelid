"""Task 6.9's required test: "vocabulary filter rules" — the valid-token
regex, the cap, the Lilak whitelist boost, offensive-word flagging, and
n-gram filtering against the selected vocabulary."""

from __future__ import annotations

from pipeline.vocab import filter_ngrams, select_vocabulary


def test_select_vocabulary_drops_invalid_tokens() -> None:
    counts = [("کتاب", 100), ("،", 50), ("hello", 30), ("123", 20)]
    vocab = select_vocabulary(counts, lang="fa")
    assert "کتاب" in vocab
    assert "،" not in vocab  # punctuation, not a Persian-letter token
    assert "hello" not in vocab  # Latin letters, not valid for fa
    assert "123" not in vocab  # digits


_TEN_ENGLISH_WORDS = ["the", "and", "you", "are", "for", "not", "but", "all", "can", "her"]


def test_select_vocabulary_respects_the_cap() -> None:
    counts = [(word, 1000 - i) for i, word in enumerate(_TEN_ENGLISH_WORDS)]
    vocab = select_vocabulary(counts, lang="en", cap=3)
    # +1 for "<s>" (task 8.1: always present, doesn't count against the cap).
    assert len(vocab) == 4
    assert {"the", "and", "you"} <= set(vocab)  # the 3 highest-count real words


def test_select_vocabulary_lilak_boost_survives_the_cap() -> None:
    counts = [(word, 1000 - i) for i, word in enumerate(_TEN_ENGLISH_WORDS)] + [("raretreasure", 1)]
    vocab = select_vocabulary(counts, lang="en", cap=3, lilak_words={"raretreasure"})
    assert "raretreasure" in vocab  # would be excluded by the cap alone
    assert vocab["raretreasure"]["flags"] == ["lilak_boost"]
    # the top-3 by frequency are still present too — the boost extends the
    # vocabulary rather than displacing higher-frequency words.
    assert {"the", "and", "you"} <= set(vocab)


def test_select_vocabulary_always_includes_sentence_start_as_hidden() -> None:
    """Task 8.1: "<s> is a hidden vocabulary entry" — needed so bigram/trigram
    rows starting a sentence can still resolve a real word id for it, even
    though it always fails the letters-only valid-token regex."""
    counts = [("کتاب", 100), ("<s>", 500)]
    vocab = select_vocabulary(counts, lang="fa")
    assert vocab["<s>"] == {"count": 500, "flags": ["hidden"]}


def test_select_vocabulary_sentence_start_present_even_with_no_real_count() -> None:
    vocab = select_vocabulary([("کتاب", 100)], lang="fa")
    assert vocab["<s>"] == {"count": 0, "flags": ["hidden"]}


def test_select_vocabulary_flags_offensive_words_without_dropping_them() -> None:
    counts_en = [("hello", 100), ("badword", 50)]
    vocab_en = select_vocabulary(counts_en, lang="en", offensive_words={"badword"})
    assert "badword" in vocab_en
    assert vocab_en["badword"]["flags"] == ["offensive"]
    assert vocab_en["hello"]["flags"] == []


def test_filter_ngrams_drops_rows_with_out_of_vocabulary_words() -> None:
    vocab = {"من": {"count": 10, "flags": []}, "کتاب": {"count": 10, "flags": []}}
    rows = [
        ("<s>", "من", 5),
        ("من", "کتاب", 5),
        ("کتاب", "ناشناخته", 5),  # "ناشناخته" not in vocab -> dropped
    ]
    filtered = filter_ngrams(rows, vocab)
    assert filtered == [("<s>", "من", 5), ("من", "کتاب", 5)]


def test_filter_ngrams_drops_rows_containing_num_or_url_placeholders() -> None:
    vocab = {"من": {"count": 10, "flags": []}}
    rows = [("من", "<num>", 5), ("<s>", "من", 5)]
    filtered = filter_ngrams(rows, vocab)
    assert filtered == [("<s>", "من", 5)]


def test_filter_ngrams_keeps_sentence_start_token_as_context_only() -> None:
    vocab = {"من": {"count": 10, "flags": []}}
    rows = [("<s>", "من", "کتاب", 5)]
    # "کتاب" isn't in vocab -> the trigram is dropped even though "<s>" is allowed.
    assert filter_ngrams(rows, vocab) == []
    vocab["کتاب"] = {"count": 10, "flags": []}
    assert filter_ngrams(rows, vocab) == [("<s>", "من", "کتاب", 5)]
