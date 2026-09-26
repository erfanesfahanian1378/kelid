from __future__ import annotations

from pathlib import Path

from pipeline.eval import build_eval_set, coverage_and_oov, read_eval_set, write_eval_set
from pipeline.tokenize import word_tokenize


def test_build_eval_set_caps_at_limit_and_skips_blank_lines() -> None:
    sentences = ["a", "", "b", "  ", "c", "d"]
    assert build_eval_set(sentences, limit=2) == ["a", "b"]


def test_write_and_read_eval_set_round_trips(tmp_path: Path) -> None:
    dest = tmp_path / "eval.txt"
    write_eval_set(["سلام دنیا", "خوبم"], dest)
    assert read_eval_set(dest) == ["سلام دنیا", "خوبم"]


def test_coverage_and_oov_counts_tokens_correctly() -> None:
    vocab = {"سلام", "دنیا"}
    sentences = ["سلام دنیا", "سلام ناشناخته"]
    coverage, oov = coverage_and_oov(sentences, vocab, word_tokenize)
    # tokens: سلام, دنیا, سلام, ناشناخته -> 4 total, 1 OOV ("ناشناخته")
    assert oov == 0.25
    assert coverage == 0.75


def test_coverage_and_oov_handles_empty_input() -> None:
    assert coverage_and_oov([], {"a"}, word_tokenize) == (0.0, 0.0)
