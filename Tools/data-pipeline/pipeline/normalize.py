"""§6.6.2's canonical() and §6.6.4's matchKey()/searchKey() — the Python side
of the shared contract with `Packages/KelidKit/Sources/PersianText/PersianNormalization.swift`.

These three functions are implemented as a direct, scalar-by-scalar port of
the Swift implementation rather than delegated to `hazm.Normalizer` (task 6.2
says "on top of hazm", but hazm's own `normalize()` also does several things
outside §6.6.2's table — punctuation spacing, "می" verb-prefix separation,
repeated-character collapsing — that would silently diverge from the Swift
rules `canonical()` must match bit-for-bit). `hazm` is still used elsewhere
in this pipeline (tokenization, §6.6.3) where its behavior isn't part of the
shared cross-language contract.

`tests/test_normalize.py` reads the same
`Packages/KelidKit/Tests/PersianTextTests/vectors.json` fixture the Swift
side reads, so the two implementations can never silently drift apart.
"""

from __future__ import annotations

import re
import unicodedata

_ZWNJ = "‌"
_ZWJ = "‍"

_YEH_VARIANTS = {"ي", "ى"}  # ي، ى
_YEH = "ی"  # ی
_KAF_VARIANT = "ك"  # ك
_KAF = "ک"  # ک
_TATWEEL = "ـ"  # ـ

_ARABIC_INDIC_TO_PERSIAN_DIGIT = {chr(0x0660 + i): chr(0x06F0 + i) for i in range(10)}
_PERSIAN_DIGIT_TO_ASCII = {chr(0x06F0 + i): str(i) for i in range(10)}

_DIACRITIC_RANGE = range(0x064B, 0x0660)  # U+064B–U+065F inclusive (0x0660 is exclusive upper bound)
_DIACRITIC_EXTRA = {"ٰ"}

_HAMZA_ALEF_VARIANTS = {"آ", "أ", "إ", "ٱ"}  # آ أ إ ٱ
_HAMZA_MAP = {
    **{c: "ا" for c in _HAMZA_ALEF_VARIANTS},  # -> ا
    "ؤ": "و",  # ؤ -> و
    "ئ": _YEH,  # ئ -> ی
    "ۀ": "ه",  # ۀ -> ه
    "ة": "ه",  # ة -> ه
}

_CURLY_APOSTROPHE = "’"


def _is_space_separator(scalar: str) -> bool:
    return scalar == " " or unicodedata.category(scalar) == "Zs"


def _is_persian_letter(scalar: str) -> bool:
    return unicodedata.category(scalar) == "Lo" and 0x0600 <= ord(scalar) <= 0x06FF


def _collapse_zwnj_edge_cases(text: str) -> str:
    """Repeated ZWNJ, ZWNJ at word start/end, ZWNJ next to a space -> removed.

    Mirrors the Swift implementation exactly, including its asymmetry: a
    dropped ZWNJ's neighbors are checked against the *original* sequence for
    `next` but the *already-decided* `kept` list for `previous` — this is
    what makes two consecutive ZWNJs collapse to exactly one (the first is
    dropped because its neighbor *in the original text* is a ZWNJ; the
    second is then kept because, once the first was dropped, neither of
    *its* checks sees a ZWNJ any more).
    """
    kept: list[str] = []
    n = len(text)
    for i, ch in enumerate(text):
        if ch != _ZWNJ:
            kept.append(ch)
            continue
        previous_kept = kept[-1] if kept else None
        following = text[i + 1] if i + 1 < n else None
        at_start = previous_kept is None
        at_end = following is None
        adjacent_to_space = previous_kept == " " or following == " "
        adjacent_to_zwnj = previous_kept == _ZWNJ or following == _ZWNJ
        if at_start or at_end or adjacent_to_space or adjacent_to_zwnj:
            continue  # drop this ZWNJ
        kept.append(ch)
    return "".join(kept)


def _remove_zwj_between_persian_letters(text: str) -> str:
    kept: list[str] = []
    n = len(text)
    for i, ch in enumerate(text):
        if ch != _ZWJ:
            kept.append(ch)
            continue
        previous = text[i - 1] if i > 0 else None
        following = text[i + 1] if i + 1 < n else None
        if previous is not None and following is not None and _is_persian_letter(previous) and _is_persian_letter(following):
            continue  # drop this ZWJ
        kept.append(ch)
    return "".join(kept)


def canonical(text: str) -> str:
    """§6.6.2: used for storage, dedupe and the pipeline's own token keys.

    Never applied to silently rewrite raw corpus text — only to derived
    keys/hashes, exactly as the Swift docstring on the keyboard side
    describes for its own (different) callers.
    """
    mapped: list[str] = []
    for ch in text:
        if ch in _YEH_VARIANTS:
            mapped.append(_YEH)
        elif ch == _KAF_VARIANT:
            mapped.append(_KAF)
        elif ch == _TATWEEL:
            continue
        elif ch in _ARABIC_INDIC_TO_PERSIAN_DIGIT:
            mapped.append(_ARABIC_INDIC_TO_PERSIAN_DIGIT[ch])
        elif _is_space_separator(ch):
            mapped.append(" ")
        else:
            mapped.append(ch)
    spaces_normalized = "".join(mapped)
    zwnj_collapsed = _collapse_zwnj_edge_cases(spaces_normalized)
    return _remove_zwj_between_persian_letters(zwnj_collapsed)


def _is_diacritic(scalar: str) -> bool:
    code = ord(scalar)
    return code in _DIACRITIC_RANGE or scalar in _DIACRITIC_EXTRA


def match_key(text: str) -> str:
    """§6.6.4: lossy on purpose — for n-gram/vocabulary keys and matching,
    never for display or corpus storage."""
    result = canonical(text)
    result = "".join(ch for ch in result if not _is_diacritic(ch) and ch not in (_ZWNJ, _ZWJ))
    result = "".join(_HAMZA_MAP.get(ch, ch) for ch in result)
    result = result.lower().replace(_CURLY_APOSTROPHE, "'")
    result = "".join(_PERSIAN_DIGIT_TO_ASCII.get(ch, ch) for ch in result)
    return result


_WHITESPACE_RUN = re.compile(r"\s+")


def search_key(text: str) -> str:
    """`matchKey` + collapsed whitespace + Latin accent folding (used for
    clipboard/snippet/emoji search on the keyboard side; kept here purely so
    the pipeline's own fuzzy lookups, if any, use the identical rule)."""
    key = match_key(text)
    collapsed = _WHITESPACE_RUN.sub(" ", key).strip()
    decomposed = unicodedata.normalize("NFKD", collapsed)
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
