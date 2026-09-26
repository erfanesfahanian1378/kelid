"""Reads the same `vectors.json` §6.6.7 fixture that
`Packages/KelidKit/Tests/PersianTextTests/PersianNormalizationVectorsTests.swift`
reads, so the Swift and Python implementations of canonical()/matchKey()
can never silently drift apart (PLAN.md §6.6, task 6.2)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from pipeline.normalize import canonical, match_key, search_key

_VECTORS_PATH = (
    Path(__file__).resolve().parents[3] / "Packages" / "KelidKit" / "Tests" / "PersianTextTests" / "vectors.json"
)


def _load_vectors() -> list[dict]:
    with _VECTORS_PATH.open(encoding="utf-8") as f:
        return json.load(f)["vectors"]


_VECTORS = _load_vectors()


@pytest.mark.parametrize("vector", _VECTORS, ids=[v["note"] for v in _VECTORS])
def test_canonical_matches_vector(vector: dict) -> None:
    assert canonical(vector["input"]) == vector["canonical"], vector["note"]


@pytest.mark.parametrize("vector", _VECTORS, ids=[v["note"] for v in _VECTORS])
def test_match_key_matches_vector(vector: dict) -> None:
    assert match_key(vector["input"]) == vector["matchKey"], vector["note"]


def test_search_key_removes_latin_accents() -> None:
    assert search_key("café") == "cafe"


def test_search_key_collapses_whitespace() -> None:
    assert search_key("سلام   دنیا") == search_key("سلام دنیا")


def test_search_key_is_zwnj_insensitive() -> None:
    assert search_key("کتاب‌ها") == search_key("کتابها")


def test_search_key_finds_yeh_variant() -> None:
    assert search_key("علی") == search_key("علي")
