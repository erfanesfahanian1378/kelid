"""Task 6.4: resumable, checksum-verified downloads for the full pipeline —
`fawiki-latest-pages-articles.xml.bz2`, an English Wikipedia dump (or a
subset), Unicode `emoji-test.txt`, and CLDR annotations.

(`pipeline/emoji.py` fetches the Unicode/CLDR files itself rather than going
through this module — they're small, single-shot text downloads with
nothing to resume — so in practice this module's resumable path matters for
the multi-GB Wikipedia dumps specifically.)

Not run against the real multi-GB dumps in Phase 6's own session: see
`README.md` for why (disk headroom) and how to run it yourself.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import requests

_CHUNK_SIZE = 1 << 20  # 1 MiB


def verify_checksum(path: Path, expected_hex: str, algorithm: str = "sha1") -> bool:
    """Returns whether `path`'s contents hash to `expected_hex` under the
    given algorithm (`sha1` matches Wikimedia's published dump checksums;
    `sha256` is supported too for other sources)."""
    hasher = hashlib.new(algorithm)
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(_CHUNK_SIZE), b""):
            hasher.update(chunk)
    return hasher.hexdigest().lower() == expected_hex.lower()


def parse_wikimedia_checksums(text: str, filename: str) -> str | None:
    """Parses a Wikimedia `*-sha1sums.txt`-style file (lines of
    `<hex digest>  <filename>`, whitespace-separated) and returns the digest
    for `filename`, or `None` if it isn't listed."""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].endswith(filename):
            return parts[0]
    return None


def download_resumable(
    url: str,
    dest: Path,
    expected_sha1: str | None = None,
    session: requests.Session | None = None,
) -> None:
    """Downloads `url` to `dest`, resuming from `dest`'s current size via an
    HTTP `Range` request if a partial file is already there. If `dest`
    already exists, is non-empty, and matches `expected_sha1` (when given),
    the download is skipped entirely — safe to re-run after an interruption
    without re-fetching gigabytes already on disk.

    Verifies the checksum after a completed download when `expected_sha1`
    is given, and deletes the file rather than leaving corrupt data behind
    if it doesn't match.
    """
    http = session or requests.Session()
    dest.parent.mkdir(parents=True, exist_ok=True)

    if dest.exists() and dest.stat().st_size > 0 and expected_sha1 and verify_checksum(dest, expected_sha1):
        return  # already fully downloaded and verified

    resume_from = dest.stat().st_size if dest.exists() else 0
    headers = {"Range": f"bytes={resume_from}-"} if resume_from else {}
    mode = "ab" if resume_from else "wb"

    with http.get(url, headers=headers, stream=True, timeout=60) as response:
        if resume_from and response.status_code == 416:
            pass  # server says there's nothing left to send — already complete
        else:
            response.raise_for_status()
            with dest.open(mode) as f:
                for chunk in response.iter_content(chunk_size=_CHUNK_SIZE):
                    if chunk:
                        f.write(chunk)

    if expected_sha1 and not verify_checksum(dest, expected_sha1):
        dest.unlink(missing_ok=True)
        raise ValueError(f"checksum mismatch for {url} -> {dest}; deleted the corrupt download")
