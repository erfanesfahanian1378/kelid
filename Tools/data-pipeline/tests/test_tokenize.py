"""§6.6.3 / task 6.6: tokenization keeps ZWNJ words whole, `<s>` insertion,
number/URL/email replacement."""

from __future__ import annotations

from pipeline.tokenize import classify_token, split_sentences, tokenize_paragraph, word_tokenize


def test_split_sentences_on_persian_and_latin_boundaries() -> None:
    text = "سلام دنیا. حالت چطوره؟ خوبم!"
    assert split_sentences(text) == ["سلام دنیا", "حالت چطوره", "خوبم"]


def test_split_sentences_on_ellipsis_and_newline() -> None:
    text = "یک لحظه…\nبله"
    assert split_sentences(text) == ["یک لحظه", "بله"]


def test_word_tokenize_keeps_zwnj_words_whole() -> None:
    # "می‌خواهم" (with an internal ZWNJ) must come back as ONE token, not
    # split at the ZWNJ — ZWNJ is a word character (§6.6.3).
    tokens = word_tokenize("من می‌خواهم بروم")
    assert tokens == ["من", "می‌خواهم", "بروم"]


def test_word_tokenize_keeps_contraction_apostrophe_attached() -> None:
    assert word_tokenize("don't") == ["don't"]
    assert word_tokenize("it's") == ["it's"]


def test_word_tokenize_splits_leading_or_trailing_apostrophe() -> None:
    # A quote mark, not a contraction — nothing word-like follows/precedes.
    assert word_tokenize("'hello'") == ["'", "hello", "'"]


def test_word_tokenize_separates_punctuation() -> None:
    assert word_tokenize("سلام، خوبی؟") == ["سلام", "،", "خوبی", "؟"]


def test_classify_token_replaces_numbers() -> None:
    assert classify_token("123") == "<num>"
    assert classify_token("۱۲۳") == "<num>"
    assert classify_token("3.14") == "<num>"
    assert classify_token("hello") == "hello"


def test_classify_token_replaces_urls_and_emails() -> None:
    assert classify_token("https://example.com") == "<url>"
    assert classify_token("www.example.com") == "<url>"
    assert classify_token("user@example.com") == "<url>"


def test_tokenize_paragraph_inserts_sentence_start_token() -> None:
    sentences = tokenize_paragraph("سلام دنیا. من می‌خواهم بروم.")
    assert sentences[0][0] == "<s>"
    assert sentences[1][0] == "<s>"
    assert sentences == [
        ["<s>", "سلام", "دنیا"],
        ["<s>", "من", "می‌خواهم", "بروم"],
    ]


def test_tokenize_paragraph_replaces_numbers_and_urls_in_context() -> None:
    sentences = tokenize_paragraph("قیمت آن 100 دلار است. سایت https://example.com را ببین.")
    assert sentences[0] == ["<s>", "قیمت", "آن", "<num>", "دلار", "است"]
    assert sentences[1] == ["<s>", "سایت", "<url>", "را", "ببین"]
