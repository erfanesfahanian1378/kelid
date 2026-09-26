"""Task 6.4: resumable downloads and checksum verification, against a tiny
local HTTP server (not the real multi-GB Wikimedia dumps)."""

from __future__ import annotations

import hashlib
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from pipeline.download import download_resumable, parse_wikimedia_checksums, verify_checksum

_CONTENT = b"the quick brown fox jumps over the lazy dog " * 1000  # a few KB, plenty to test Range with


class _RangeAwareHandler(BaseHTTPRequestHandler):
    def log_message(self, *args: object) -> None:  # silence test output
        pass

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler's naming convention
        range_header = self.headers.get("Range")
        if range_header:
            start = int(range_header.removeprefix("bytes=").split("-")[0])
            if start >= len(_CONTENT):
                self.send_response(416)
                self.end_headers()
                return
            body = _CONTENT[start:]
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{len(_CONTENT) - 1}/{len(_CONTENT)}")
        else:
            body = _CONTENT
            self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@pytest.fixture
def server_url():
    server = ThreadingHTTPServer(("127.0.0.1", 0), _RangeAwareHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/file.bin"
    finally:
        server.shutdown()
        thread.join()


def test_verify_checksum_matches_and_mismatches(tmp_path: Path) -> None:
    path = tmp_path / "f.bin"
    path.write_bytes(_CONTENT)
    correct = hashlib.sha1(_CONTENT).hexdigest()
    assert verify_checksum(path, correct)
    assert not verify_checksum(path, "0" * 40)


def test_parse_wikimedia_checksums_finds_the_named_file() -> None:
    text = "abc123  fawiki-latest-pages-articles.xml.bz2\ndef456  fawiki-latest-abstract.xml.gz\n"
    assert parse_wikimedia_checksums(text, "fawiki-latest-pages-articles.xml.bz2") == "abc123"
    assert parse_wikimedia_checksums(text, "nonexistent.bz2") is None


def test_download_resumable_fetches_full_file(tmp_path: Path, server_url: str) -> None:
    dest = tmp_path / "out.bin"
    download_resumable(server_url, dest)
    assert dest.read_bytes() == _CONTENT


def test_download_resumable_resumes_a_partial_file(tmp_path: Path, server_url: str) -> None:
    dest = tmp_path / "out.bin"
    dest.write_bytes(_CONTENT[:100])  # simulate a previous, interrupted download
    download_resumable(server_url, dest)
    assert dest.read_bytes() == _CONTENT


def test_download_resumable_skips_an_already_complete_verified_file(tmp_path: Path, server_url: str) -> None:
    dest = tmp_path / "out.bin"
    dest.write_bytes(_CONTENT)
    correct = hashlib.sha1(_CONTENT).hexdigest()
    # If it re-downloaded, a bug in resume logic could corrupt the file — it
    # shouldn't touch the network at all once the checksum already matches.
    download_resumable(server_url, dest, expected_sha1=correct)
    assert dest.read_bytes() == _CONTENT


def test_download_resumable_raises_and_deletes_on_checksum_mismatch(tmp_path: Path, server_url: str) -> None:
    dest = tmp_path / "out.bin"
    with pytest.raises(ValueError, match="checksum mismatch"):
        download_resumable(server_url, dest, expected_sha1="0" * 40)
    assert not dest.exists()
