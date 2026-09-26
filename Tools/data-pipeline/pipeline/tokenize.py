"""§6.6.3 word characters/tokenization and task 6.6's normalize-and-tokenize
step: paragraph -> sentences -> `(sentence_id, pos, token)` triples, with
`<s>` inserted at every sentence start and numbers/URLs/emails replaced by
`<num>`/`<url>`.

Word-character classification matches `PersianText.WordCharacters` (Swift)
exactly: Unicode letters (L*), marks (M*), decimal digits (Nd), ZWNJ, ZWJ,
plus an apostrophe when it sits between two letters (English contractions).
"""

from __future__ import annotations

import re
import unicodedata

from pipeline.normalize import canonical

_ZWNJ = "‌"
_ZWJ = "‍"
_APOSTROPHES = {"'", "’"}

_SENTENCE_BOUNDARY_RE = re.compile(r"[.!?؟…\n]")

# Simple, deliberately conservative URL/email matchers — good enough for
# "replace it with <url> before counting," not a general-purpose validator.
# Matched as whole spans *before* generic tokenization runs (a URL's `://`,
# `/`, `.` would otherwise be shredded into separate punctuation tokens by
# `word_tokenize`, same as any other non-word character).
_URL_OR_EMAIL_SCAN_RE = re.compile(
    r"(?:https?://\S+|www\.\S+|[^\s@]+@[^\s@]+\.[^\s@]+)", re.IGNORECASE
)
_NUMBER_RE = re.compile(r"^[0-9۰-۹٠-٩]+([.,][0-9۰-۹٠-٩]+)*$")

# A "word" run: word characters, with an apostrophe allowed only when both
# neighbors are word characters (handled by the tokenizer loop below, not by
# this pattern alone — regex alternation can't see "the next character").
_TOKEN_SPLIT_RE = re.compile(r"(\s+)")


def _is_word_char(ch: str) -> bool:
    category = unicodedata.category(ch)
    return category[0] in ("L", "M") or category == "Nd" or ch in (_ZWNJ, _ZWJ)


def split_sentences(text: str) -> list[str]:
    """§6.6.3's sentence boundary: `. ! ? ؟ … \\n`. Boundary characters are
    dropped (they're punctuation tokens, not part of either sentence) and
    empty/whitespace-only sentences are discarded."""
    sentences: list[str] = []
    start = 0
    for match in _SENTENCE_BOUNDARY_RE.finditer(text):
        piece = text[start : match.start()].strip()
        if piece:
            sentences.append(piece)
        start = match.end()
    tail = text[start:].strip()
    if tail:
        sentences.append(tail)
    return sentences


def _split_word_run(run: str) -> list[str]:
    """Splits a maximal run of word-characters-and-apostrophes into tokens,
    keeping an apostrophe attached only when both its neighbors are word
    characters (contractions), otherwise treating it as a separate token."""
    tokens: list[str] = []
    current = ""
    for i, ch in enumerate(run):
        if ch in _APOSTROPHES:
            prev_is_word = bool(current) and _is_word_char(current[-1])
            next_is_word = i + 1 < len(run) and _is_word_char(run[i + 1])
            if prev_is_word and next_is_word:
                current += ch
                continue
            if current:
                tokens.append(current)
                current = ""
            tokens.append(ch)
            continue
        current += ch
    if current:
        tokens.append(current)
    return tokens


def _word_tokenize_plain(text: str) -> list[str]:
    """`word_tokenize`'s original per-character scan, for a span already
    known to contain no URL/email (see `word_tokenize`)."""
    tokens: list[str] = []
    for piece in _TOKEN_SPLIT_RE.split(text):
        if not piece or piece.isspace():
            continue
        run = ""
        for ch in piece:
            is_word_or_apostrophe = _is_word_char(ch) or ch in _APOSTROPHES
            if is_word_or_apostrophe:
                run += ch
                continue
            if run:
                tokens.extend(_split_word_run(run))
                run = ""
            tokens.append(ch)  # punctuation/emoji/other, one token each
        if run:
            tokens.extend(_split_word_run(run))
    return tokens


def word_tokenize(sentence: str) -> list[str]:
    """Splits a sentence into word/number/URL-or-email/punctuation/emoji
    tokens (§6.6.3's token classes), without the `<num>`/`<url>` replacement
    itself (that's `classify_token`'s job for numbers — kept separate so
    callers that just want raw tokens, e.g. for a word list, aren't forced
    through it). A URL/email is matched as one whole token up front, since
    its `://`/`/`/`.`/`@` would otherwise be shredded into separate
    punctuation tokens by the generic word/punctuation scan below."""
    tokens: list[str] = []
    pos = 0
    for match in _URL_OR_EMAIL_SCAN_RE.finditer(sentence):
        tokens.extend(_word_tokenize_plain(sentence[pos : match.start()]))
        tokens.append(match.group())
        pos = match.end()
    tokens.extend(_word_tokenize_plain(sentence[pos:]))
    return tokens


def classify_token(token: str) -> str:
    """Returns `<num>` / `<url>` for tokens the counting step replaces, or
    the `canonical()`-normalized token otherwise — task 6.6 calls this whole
    step "normalize and tokenize," and counting must see canonical forms
    (e.g. "كتاب" and "کتاب" merged into one token) or the resulting n-grams
    fragment across surface variants of the same word for no good reason.
    `canonical()` is a no-op for punctuation/Latin tokens, so applying it
    unconditionally (rather than only to "real words") is safe."""
    if _URL_OR_EMAIL_SCAN_RE.fullmatch(token):
        return "<url>"
    if _NUMBER_RE.match(token):
        return "<num>"
    return canonical(token)


_PLACEHOLDER_RE = re.compile("(\\d+)")


def tokenize_paragraph(text: str) -> list[list[str]]:
    """Paragraph -> list of sentences, each already prefixed with `<s>` and
    with numbers/URLs/emails replaced — exactly the token stream task 6.6's
    counting step (§6.7) partitions by `sentence_id` and orders by `pos`.

    URL/email spans are masked out before sentence-boundary splitting and
    restored afterward: `split_sentences` follows §6.6.3's boundary rule
    literally (any `.`/`!`/`?`/`؟`/`…`/newline ends a sentence), which would
    otherwise misread a URL's own internal `.` as a sentence end.
    """
    placeholders: list[str] = []

    def _mask(match: re.Match[str]) -> str:
        placeholders.append(match.group())
        return f"{len(placeholders) - 1}"

    masked = _URL_OR_EMAIL_SCAN_RE.sub(_mask, text)

    sentences: list[list[str]] = []
    for raw_sentence in split_sentences(masked):
        restored = _PLACEHOLDER_RE.sub(lambda m: placeholders[int(m.group(1))], raw_sentence)
        tokens = ["<s>"] + [classify_token(t) for t in word_tokenize(restored)]
        sentences.append(tokens)
    return sentences
