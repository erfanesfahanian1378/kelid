"""Task 6.12: compiles Unicode's `emoji-test.txt` + CLDR
`annotations/{fa,en}.xml`/`annotationsDerived/{fa,en}.xml` into
`Packages/KelidKit/Sources/EmojiData/emoji.json` (§6.9's schema) and
`out/emoji_suggest_{fa,en}.tsv` (keyword -> up to 3 emoji, most common
first).

Only **base** (skin-tone-neutral) emoji become their own catalog entries —
a skin-tone variant is a runtime-applied modifier (§6.9's long-press picker),
not a separate grid entry — but an entry is flagged `"st": true` whenever a
modified form of it exists in the source data, so the keyboard knows to
offer the picker at all.
"""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.request import urlopen

_ROOT = Path(__file__).resolve().parents[1]
_OUT_DIR = _ROOT / "out"
_EMOJI_DATA_DEST = _ROOT.parent.parent / "Packages" / "KelidKit" / "Sources" / "EmojiData" / "emoji.json"
_DOCS_DIR = _ROOT.parent.parent / "docs"

_EMOJI_TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
_CLDR_BASE = "https://raw.githubusercontent.com/unicode-org/cldr/main/common"
_ANNOTATION_LANGS = ("fa", "en")

# §6.9's category-bar order (excluding "Recents", which is synthesized at
# runtime from usage history, not part of this static dataset). Unicode's
# own file groups "Travel & Places" before "Activities"; the plan's UI order
# has them the other way around, so this table reorders rather than reusing
# file order directly.
_GROUP_INDEX = {
    "Smileys & Emotion": 0,
    "People & Body": 1,
    "Animals & Nature": 2,
    "Food & Drink": 3,
    "Activities": 4,
    "Travel & Places": 5,
    "Objects": 6,
    "Symbols": 7,
    "Flags": 8,
}
_SKIN_TONE_MODIFIERS = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}

_VERSION_RE = re.compile(r"E(\d+(?:\.\d+)?)")
_GROUP_RE = re.compile(r"^# group: (.+)$")


def _fetch_text(url: str) -> str:
    with urlopen(url, timeout=60) as response:  # noqa: S310 - fixed, hardcoded HTTPS URLs only
        return response.read().decode("utf-8")


class _EmojiTestEntry:
    __slots__ = ("codepoints", "group", "version", "name")

    def __init__(self, codepoints: tuple[int, ...], group: str, version: float, name: str) -> None:
        self.codepoints = codepoints
        self.group = group
        self.version = version
        self.name = name


def _parse_emoji_test(text: str) -> list[_EmojiTestEntry]:
    entries: list[_EmojiTestEntry] = []
    current_group = ""
    for line in text.splitlines():
        group_match = _GROUP_RE.match(line)
        if group_match:
            current_group = group_match.group(1)
            continue
        if not line or line.startswith("#"):
            continue
        if "; fully-qualified" not in line:
            continue
        if current_group not in _GROUP_INDEX:
            continue  # "Component" (skin-tone/hair modifiers alone) — not a selectable emoji
        codepoint_field, _, comment = line.partition("#")
        codepoints = tuple(int(h, 16) for h in codepoint_field.split(";")[0].split())
        version_match = _VERSION_RE.search(comment)
        version = float(version_match.group(1)) if version_match else 0.0
        name = comment.split(None, 2)[-1].strip() if version_match else comment.strip()
        entries.append(_EmojiTestEntry(codepoints, current_group, version, name))
    return entries


def _select_base_entries(entries: list[_EmojiTestEntry]) -> list[_EmojiTestEntry]:
    """Drops any entry that itself contains a skin-tone modifier — those are
    runtime variants of a base entry, not separate catalog rows."""
    return [e for e in entries if not any(cp in _SKIN_TONE_MODIFIERS for cp in e.codepoints)]


def _supports_skin_tone(base: _EmojiTestEntry, all_codepoint_sets: set[tuple[int, ...]]) -> bool:
    """A simple, single-attachment-point check: does `base`'s codepoint
    sequence with a skin-tone modifier appended exist as its own entry?
    Multi-person sequences with per-person tone modifiers (e.g. couples)
    aren't detected by this — an acceptable v1 simplification, since those
    are a small minority of the catalog and the picker degrading to "not
    offered" for them is not a functional break."""
    return any((*base.codepoints, modifier) in all_codepoint_sets for modifier in _SKIN_TONE_MODIFIERS)


def _parse_cldr_annotations(xml_text: str) -> dict[str, list[str]]:
    root = ET.fromstring(xml_text)  # noqa: S314 - fixed, hardcoded HTTPS URLs only
    keywords: dict[str, list[str]] = {}
    for annotation in root.iter("annotation"):
        if annotation.get("type") == "tts":
            continue
        cp = annotation.get("cp")
        text = annotation.text or ""
        if cp is None or not text:
            continue
        keywords[cp] = [kw.strip() for kw in text.split("|") if kw.strip()]
    return keywords


def _load_keywords_for_lang(lang: str, cache: dict[str, str]) -> dict[str, list[str]]:
    """Merges `annotations/<lang>.xml` (priority) with
    `annotationsDerived/<lang>.xml` (fallback, for algorithmically-derived
    sequences the main file doesn't hand-annotate)."""
    derived = _parse_cldr_annotations(cache[f"annotationsDerived/{lang}"])
    primary = _parse_cldr_annotations(cache[f"annotations/{lang}"])
    merged = dict(derived)
    merged.update(primary)
    return merged


def build_emoji_catalog(
    emoji_test_text: str,
    annotation_texts: dict[str, str],
) -> list[dict]:
    """`annotation_texts` keys are `"annotations/fa"`, `"annotationsDerived/fa"`,
    `"annotations/en"`, `"annotationsDerived/en"`. Returns the §6.9 schema's
    list of `{"e", "g", "v", "st", "fa", "en"}` dicts, ordered exactly as
    `emoji-test.txt` orders them (CLDR order — already curated for keyboard
    palettes, per that file's own header comment)."""
    all_entries = _parse_emoji_test(emoji_test_text)
    all_codepoint_sets = {e.codepoints for e in all_entries}
    base_entries = _select_base_entries(all_entries)

    keywords_by_lang = {lang: _load_keywords_for_lang(lang, annotation_texts) for lang in _ANNOTATION_LANGS}

    catalog: list[dict] = []
    for entry in base_entries:
        glyph = "".join(chr(cp) for cp in entry.codepoints)
        # CLDR's own `cp` values have U+FE0F stripped (its annotations files
        # say so in their header comment), but `emoji-test.txt`'s
        # "fully-qualified" glyphs — the form we store and display — often
        # include it. Look keywords up by the FE0F-stripped form; keep the
        # fully-qualified `glyph` itself in the catalog entry.
        lookup_key = glyph.replace("️", "")
        catalog.append(
            {
                "e": glyph,
                "g": _GROUP_INDEX[entry.group],
                "v": entry.version,
                "st": _supports_skin_tone(entry, all_codepoint_sets),
                "fa": keywords_by_lang["fa"].get(lookup_key, keywords_by_lang["fa"].get(glyph, [])),
                "en": keywords_by_lang["en"].get(lookup_key, keywords_by_lang["en"].get(glyph, [])),
            }
        )
    return catalog


def build_suggest_tables(catalog: list[dict]) -> dict[str, dict[str, list[str]]]:
    """keyword -> up to 3 emoji, most common first. "Most common" has no
    real usage-frequency source at pipeline time, so this uses
    `emoji-test.txt`'s own CLDR ordering as the proxy (that file is
    curated in a sensible, roughly-by-importance order within each group
    already — see its own header comment about being suited to keyboard
    palettes) — i.e. simply the catalog's own order, first-seen-first-kept.
    """
    tables: dict[str, dict[str, list[str]]] = {lang: {} for lang in _ANNOTATION_LANGS}
    for entry in catalog:
        for lang in _ANNOTATION_LANGS:
            for keyword in entry[lang]:
                bucket = tables[lang].setdefault(keyword, [])
                if len(bucket) < 3 and entry["e"] not in bucket:
                    bucket.append(entry["e"])
    return tables


def run(dest: Path = _EMOJI_DATA_DEST, out_dir: Path = _OUT_DIR) -> list[dict]:
    emoji_test_text = _fetch_text(_EMOJI_TEST_URL)
    annotation_texts = {}
    for lang in _ANNOTATION_LANGS:
        annotation_texts[f"annotations/{lang}"] = _fetch_text(f"{_CLDR_BASE}/annotations/{lang}.xml")
        annotation_texts[f"annotationsDerived/{lang}"] = _fetch_text(f"{_CLDR_BASE}/annotationsDerived/{lang}.xml")

    catalog = build_emoji_catalog(emoji_test_text, annotation_texts)

    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, separators=(",", ":"))

    suggest_tables = build_suggest_tables(catalog)
    out_dir.mkdir(parents=True, exist_ok=True)
    for lang, table in suggest_tables.items():
        with (out_dir / f"emoji_suggest_{lang}.tsv").open("w", encoding="utf-8") as f:
            for keyword, emojis in sorted(table.items()):
                f.write(f"{keyword}\t{' '.join(emojis)}\n")

    _append_attribution()
    return catalog


def _append_attribution() -> None:
    _DOCS_DIR.mkdir(parents=True, exist_ok=True)
    attributions_path = _DOCS_DIR / "ATTRIBUTIONS.md"
    marker = "## Unicode emoji-test.txt + CLDR annotations (task 6.12)"
    if attributions_path.exists() and marker in attributions_path.read_text(encoding="utf-8"):
        return
    entry = (
        f"\n{marker}\n\n"
        f"- **Source:** {_EMOJI_TEST_URL}, {_CLDR_BASE}/annotations/{{fa,en}}.xml, "
        f"{_CLDR_BASE}/annotationsDerived/{{fa,en}}.xml\n"
        "- **License:** Unicode-3.0 (Unicode, Inc. — see each file's own header)\n"
        "- **Used for:** `Packages/KelidKit/Sources/EmojiData/emoji.json` (the emoji panel's catalog) and "
        "`out/emoji_suggest_{fa,en}.tsv` (keyword -> emoji suggestions).\n"
    )
    with attributions_path.open("a", encoding="utf-8") as f:
        f.write(entry)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=_EMOJI_DATA_DEST)
    parser.add_argument("--out-dir", type=Path, default=_OUT_DIR)
    args = parser.parse_args()
    catalog = run(dest=args.dest, out_dir=args.out_dir)
    size_kb = args.dest.stat().st_size / 1024
    print(f"Wrote {len(catalog)} emoji to {args.dest} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
