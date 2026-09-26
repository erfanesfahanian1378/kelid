"""Task 6.9: vocabulary selection — valid-token regex, Lilak whitelist
boost, a per-language cap (200k fa / 120k en), offensive-word flagging, and
dropping n-grams that reference an out-of-vocabulary word or `<num>`/`<url>`
(`<s>` stays, as a context-only token)."""

from __future__ import annotations

import re

# §6.6.1's character inventory: the 32 Persian letters + variants + ZWNJ.
# Shared with `quick.py`'s own valid-token check (task 6.3) so the "quick"
# and "full" paths agree on what counts as a well-formed fa token.
FA_LETTERS = "ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی" "آأإٱءؤئۀةيىكھ" "‌"
FA_TOKEN_RE = re.compile(f"^[{re.escape(FA_LETTERS)}]+$")
EN_TOKEN_RE = re.compile(r"^[A-Za-z']+$")

DEFAULT_CAPS = {"fa": 200_000, "en": 120_000}

_PLACEHOLDER_TOKENS = {"<num>", "<url>"}
_SENTENCE_START = "<s>"


def valid_token_pattern(lang: str) -> re.Pattern[str]:
    return FA_TOKEN_RE if lang == "fa" else EN_TOKEN_RE


def select_vocabulary(
    unigram_counts: list[tuple[str, int]],
    lang: str,
    cap: int | None = None,
    lilak_words: set[str] | None = None,
    offensive_words: set[str] | None = None,
) -> dict[str, dict]:
    """Returns `{word: {"count": int, "flags": [...]}}` for the selected
    vocabulary. `lilak_words` are guaranteed a place even if the frequency
    cap would otherwise exclude them (a "boost", not just a tie-breaker) —
    the final vocabulary can be slightly larger than `cap` as a result,
    which is the whole point of a whitelist override.
    """
    cap = cap if cap is not None else DEFAULT_CAPS[lang]
    lilak_words = lilak_words or set()
    offensive_words = offensive_words or set()
    pattern = valid_token_pattern(lang)

    valid = [(word, count) for word, count in unigram_counts if pattern.match(word)]
    valid.sort(key=lambda wc: (-wc[1], wc[0]))

    selected: dict[str, dict] = {}
    for word, count in valid[:cap]:
        selected[word] = {"count": count, "flags": []}

    # Whitelist boost: add back any valid Lilak word the cap left out.
    valid_by_word = dict(valid)
    for word in lilak_words:
        if word in valid_by_word and word not in selected:
            selected[word] = {"count": valid_by_word[word], "flags": ["lilak_boost"]}

    for word in offensive_words:
        if word in selected:
            selected[word]["flags"].append("offensive")

    # Task 8.1: "<s> is a hidden vocabulary entry (never suggested)" — it
    # fails `valid_token_pattern` (it's punctuation-shaped, not a real word)
    # so the filter above always drops it, but bigram/trigram rows need it
    # to have a real word id once `klm build` assigns ids from this table.
    # Kept out of the frequency cap entirely (`count` from the real corpus
    # count if present, else 0) since it isn't a "word" competing for
    # vocabulary space in the first place.
    sentence_start_count = dict(unigram_counts).get(_SENTENCE_START, 0)
    selected[_SENTENCE_START] = {"count": sentence_start_count, "flags": ["hidden"]}

    return selected


def filter_ngrams(rows: list[tuple], vocab: dict[str, dict]) -> list[tuple]:
    """Drops any bigram/trigram row containing a word that isn't in `vocab`
    or is a `<num>`/`<url>` placeholder — `<s>` is always allowed through.
    `rows` are `(w1, w2, count)` or `(w1, w2, w3, count)` tuples (the shape
    `counting.count_ngrams` returns)."""

    def word_ok(word: str) -> bool:
        if word == _SENTENCE_START:
            return True
        if word in _PLACEHOLDER_TOKENS:
            return False
        return word in vocab

    return [row for row in rows if all(word_ok(w) for w in row[:-1])]
