"""Task 6.12: emoji-test.txt + CLDR annotation parsing, on small synthetic
fixtures (not the real multi-MB Unicode/CLDR downloads)."""

from __future__ import annotations

from pipeline.emoji import build_emoji_catalog, build_suggest_tables

_FIXTURE_EMOJI_TEST = """\
# group: Smileys & Emotion

# subgroup: face-smiling
1F600                                                  ; fully-qualified     # \U0001F600 E1.0 grinning face

# subgroup: face-affection
2764 FE0F                                              ; fully-qualified     # ❤️ E0.6 red heart

# group: People & Body

# subgroup: hand-fingers-closed
1F44D                                                  ; fully-qualified     # \U0001F44D E0.6 thumbs up
1F44D 1F3FB                                            ; fully-qualified     # \U0001F44D\U0001F3FB E1.0 thumbs up: light skin tone

# group: Component

# subgroup: hand-fingers-closed
1F3FB                                                  ; fully-qualified     # \U0001F3FB E1.0 light skin tone
"""


def _annotation_xml(entries: dict[str, str]) -> str:
    body = "\n".join(f'<annotation cp="{cp}">{kw}</annotation>' for cp, kw in entries.items())
    return f'<?xml version="1.0" encoding="UTF-8" ?><ldml><annotations>{body}</annotations></ldml>'


_FIXTURE_ANNOTATIONS = {
    "annotations/fa": _annotation_xml({"\U0001F600": "خنده | صورت", "\U0001F44D": "شست"}),
    "annotations/en": _annotation_xml({"\U0001F600": "grinning | face", "\U0001F44D": "thumb | up"}),
    # CLDR strips FE0F from cp values — the fixture's ❤ (no FE0F) must still
    # match the fully-qualified ❤️ (with FE0F) glyph from emoji-test.txt.
    "annotationsDerived/fa": _annotation_xml({"❤": "قلب"}),
    "annotationsDerived/en": _annotation_xml({"❤": "heart | love"}),
}


def test_build_emoji_catalog_excludes_component_group() -> None:
    catalog = build_emoji_catalog(_FIXTURE_EMOJI_TEST, _FIXTURE_ANNOTATIONS)
    # The lone "Component" entry (bare skin-tone modifier) must not appear.
    assert all(e["e"] != "\U0001F3FB" for e in catalog)


def test_build_emoji_catalog_excludes_skin_tone_variants_as_separate_entries() -> None:
    catalog = build_emoji_catalog(_FIXTURE_EMOJI_TEST, _FIXTURE_ANNOTATIONS)
    glyphs = [e["e"] for e in catalog]
    assert "\U0001F44D" in glyphs  # base thumbs up
    assert "\U0001F44D\U0001F3FB" not in glyphs  # light-skin-tone variant is not its own entry


def test_build_emoji_catalog_flags_skin_tone_support() -> None:
    catalog = build_emoji_catalog(_FIXTURE_EMOJI_TEST, _FIXTURE_ANNOTATIONS)
    thumbs_up = next(e for e in catalog if e["e"] == "\U0001F44D")
    grinning = next(e for e in catalog if e["e"] == "\U0001F600")
    assert thumbs_up["st"] is True
    assert grinning["st"] is False


def test_build_emoji_catalog_maps_group_and_version() -> None:
    catalog = build_emoji_catalog(_FIXTURE_EMOJI_TEST, _FIXTURE_ANNOTATIONS)
    grinning = next(e for e in catalog if e["e"] == "\U0001F600")
    thumbs_up = next(e for e in catalog if e["e"] == "\U0001F44D")
    assert grinning["g"] == 0  # Smileys & Emotion
    assert grinning["v"] == 1.0
    assert thumbs_up["g"] == 1  # People & Body
    assert thumbs_up["v"] == 0.6


def test_build_emoji_catalog_looks_up_keywords_ignoring_fe0f() -> None:
    catalog = build_emoji_catalog(_FIXTURE_EMOJI_TEST, _FIXTURE_ANNOTATIONS)
    heart = next(e for e in catalog if e["e"] == "❤️")
    assert heart["fa"] == ["قلب"]
    assert heart["en"] == ["heart", "love"]


def test_build_suggest_tables_caps_at_three_and_dedupes() -> None:
    catalog = [
        {"e": "🙂", "fa": ["خنده"], "en": ["smile"]},
        {"e": "😀", "fa": ["خنده"], "en": ["smile"]},
        {"e": "😄", "fa": ["خنده"], "en": ["smile"]},
        {"e": "😁", "fa": ["خنده"], "en": ["smile"]},  # 4th match for "خنده"/"smile" -> dropped
    ]
    tables = build_suggest_tables(catalog)
    assert tables["fa"]["خنده"] == ["🙂", "😀", "😄"]
    assert tables["en"]["smile"] == ["🙂", "😀", "😄"]
