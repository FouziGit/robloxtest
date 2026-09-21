"""Runs every audio generator and reports what landed on disk.

    python3 tools/audio/generate_all.py

The report's digests come from the written bytes, so two consecutive runs that disagree mean a
generator has picked up an unseeded source of randomness or a libm call on a per-sample path -- which
is the failure vellum_wav.py is built to make impossible, and the one scripts/check.sh proves absent
on every build by regenerating and diffing assets/audio.

Cheapest first: the kit is short files, the pigments are four times as many, the loops are the only
ones that take seconds.
"""

from __future__ import annotations

import kit
import music
import pigments
from vellum_wav import MAX_BYTES, report

MODULES = (kit, pigments, music)


def main() -> int:
    paths = []
    for module in MODULES:
        paths.extend(module.generate())
    over_budget = report(paths)
    if over_budget:
        print(f"\n{over_budget} file(s) above the {MAX_BYTES} byte ceiling -- shorten them, do not ship them.")
        return 1
    print(f"\n{len(paths)} sounds written, all within {MAX_BYTES} bytes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
