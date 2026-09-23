#!/usr/bin/env python3
"""Download the third-party packs listed in sources.json, check their licence, and pin their bytes.

    python3 tools/thirdparty/fetch.py            # download what is missing into .cache/thirdparty/
    python3 tools/thirdparty/fetch.py --verify   # re-check every cached archive against its pinned hash

For each source it re-reads the listing page and refuses to continue if the licence line recorded in
sources.json is no longer on it -- a licence that changed since it was vetted must be vetted again, not
inherited. The first download pins the archive's SHA-256 and the date into sources.json; every later
download must produce the same bytes. The archives themselves are never committed (they are large, and
what the game uses is the processed subset under assets/, whose provenance docs/ASSETS.md records).

Standard library only, like the generators in tools/.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = pathlib.Path(__file__).with_name("sources.json")
CACHE = ROOT / ".cache" / "thirdparty"
USER_AGENT = "vellum-thirdparty-fetch/1.0"


def get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(line_buffering=True)
    verify_only = "--verify" in argv
    manifest = json.loads(SOURCES.read_text())
    CACHE.mkdir(parents=True, exist_ok=True)
    changed = False
    failures = 0
    for source in manifest["sources"]:
        name = source["name"]
        folder = CACHE / name
        archive = folder / pathlib.PurePosixPath(source["url"]).name
        if not verify_only:
            listing = get(source["listing"]).decode("utf-8", errors="replace")
            evidence = source["licenseEvidence"]
            if evidence.replace("License(s): ", "") not in listing or (
                evidence.startswith("License(s):") and "License(s)" not in listing
            ):
                print(f"  REFUSED {name}: the listing no longer shows '{evidence}' -- vet it again")
                failures += 1
                continue
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "listing.html").write_text(listing)
            if not archive.exists():
                print(f"  downloading {name}")
                archive.write_bytes(get(source["url"]))
        if not archive.exists():
            print(f"  MISSING {name}")
            failures += 1
            continue
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        pinned = source.get("sha256")
        if pinned is None and not verify_only:
            source["sha256"] = digest
            source["downloaded"] = datetime.date.today().isoformat()
            changed = True
            print(f"  pinned  {name} {digest[:16]}... ({archive.stat().st_size / 1048576:.1f} MB)")
        elif pinned != digest:
            print(f"  CHANGED {name}: {digest[:16]}... is not the pinned {str(pinned)[:16]}...")
            failures += 1
        else:
            print(f"  ok      {name}")
    if changed:
        SOURCES.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
