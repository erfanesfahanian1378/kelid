"""Task 6.5: wikiextractor JSONL -> plain paragraphs, on synthetic fixtures
shaped like wikiextractor's real `--json` output (not a real dump)."""

from __future__ import annotations

import json
from pathlib import Path

from pipeline.wiki_text import (
    extract_paragraphs_from_json_line,
    is_held_out,
    iter_articles_from_directory,
    iter_paragraphs_from_directory,
)


def _article_line(article_id: str, title: str, text: str) -> str:
    return json.dumps({"id": article_id, "title": title, "text": text}, ensure_ascii=False)


def test_extract_paragraphs_drops_title_line() -> None:
    text = "تهران\n\nتهران پایتخت ایران است.\nاین یک جمله دیگر است."
    paragraphs = extract_paragraphs_from_json_line(_article_line("1", "تهران", text))
    assert "تهران" not in paragraphs
    assert "تهران پایتخت ایران است." in paragraphs


def test_extract_paragraphs_drops_short_lines() -> None:
    text = "عنوان\n\nیک پاراگراف طولانی با چند کلمه است.\nکم\nدو کلمه"
    paragraphs = extract_paragraphs_from_json_line(_article_line("1", "عنوان", text))
    assert "کم" not in paragraphs  # 1 word
    assert "دو کلمه" not in paragraphs  # 2 words, still under the 3-word minimum
    assert "یک پاراگراف طولانی با چند کلمه است." in paragraphs


def test_extract_paragraphs_drops_blank_lines() -> None:
    text = "عنوان\n\n\nیک پاراگراف با چند کلمه اینجا.\n\n"
    paragraphs = extract_paragraphs_from_json_line(_article_line("1", "عنوان", text))
    assert paragraphs == ["یک پاراگراف با چند کلمه اینجا."]


def test_iter_articles_from_directory_walks_nested_wiki_files(tmp_path: Path) -> None:
    (tmp_path / "AA").mkdir()
    (tmp_path / "AB").mkdir()
    (tmp_path / "AA" / "wiki_00").write_text(
        _article_line("1", "یک", "یک\n\nمتن اول با چند کلمه اینجا.") + "\n",
        encoding="utf-8",
    )
    (tmp_path / "AB" / "wiki_00").write_text(
        _article_line("2", "دو", "دو\n\nمتن دوم با چند کلمه اینجا.") + "\n",
        encoding="utf-8",
    )
    articles = list(iter_articles_from_directory(tmp_path))
    assert {a["id"] for a in articles} == {"1", "2"}


def test_is_held_out_is_deterministic_and_roughly_one_percent() -> None:
    ids = [str(i) for i in range(1, 5001)]
    held = [i for i in ids if is_held_out(i)]
    # Not exactly 1% (hash-based, not a literal `int(id) % 100`), but should
    # be in a sane neighborhood of it for a large enough sample.
    assert 20 <= len(held) <= 100
    # Determinism: re-running against the same ids gives the exact same set.
    assert held == [i for i in ids if is_held_out(i)]


def test_iter_paragraphs_from_directory_pairs_article_id_with_paragraphs(tmp_path: Path) -> None:
    (tmp_path / "AA").mkdir()
    (tmp_path / "AA" / "wiki_00").write_text(
        _article_line("42", "عنوان", "عنوان\n\nیک پاراگراف با چند کلمه اینجا.") + "\n",
        encoding="utf-8",
    )
    results = list(iter_paragraphs_from_directory(tmp_path))
    assert results == [("42", ["یک پاراگراف با چند کلمه اینجا."])]
