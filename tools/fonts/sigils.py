#!/usr/bin/env python3
"""Proves that every pigment sigil, and every other character the code writes, is drawn with a glyph Roblox
ships, and lists the codepoints that are.

    python3 tools/fonts/sigils.py
    python3 tools/fonts/sigils.py --fonts <content/fonts> --binary <RobloxStudio executable>

The combo chips, the touch discs and the loadout write PigmentConfig.Sigils in the interface's own face,
and that face (Merriweather) has neither the triangle nor the square: the engine draws those from its
fallback chain. A codepoint that no font of the chain has is drawn as an empty box, which is what the
Orpiment chip showed with its four-pointed star (U+2726).

The chain is not documented, so this reads it where the engine keeps it: the Studio executable registers
its fallback fonts in one block, right after the message it gives when the default face will not load.
That block reads Arimo first, then the two emoji fonts, then one Noto face per script, then CJK. Arimo is
bundled (content/fonts/families/Arimo.json, Regular and Bold on disk), so a codepoint present in both of
its bundled faces is drawn, whatever face the interface is set in. Those are the codepoints this proves,
and tests/Sigils.spec.luau holds PigmentConfig.Sigils, and every string in src, to the list and the ranges
this prints. The panels' close cross (U+2715) was the same empty box as the star.

Run it again when Studio updates or when a sigil changes: it fails on a sigil or a string the fallback
cannot draw, and prints the list and the ranges to paste into the test. Standard library only, like the
generators in tools/.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src"
PIGMENTS = SOURCE / "shared" / "Config" / "PigmentConfig.luau"
STUDIO = Path("/Applications/RobloxStudio.app/Contents")
FONTS = STUDIO / "Resources" / "content" / "fonts"
BINARY = STUDIO / "MacOS" / "RobloxStudio"

# The message the engine gives when its default face will not load; the fallback block follows it.
MARKER = b"Unable to load SourceSans font asset. Required by text rendering."
ASSET = b"rbxasset://fonts/"

# Shapes weighed for a sigil besides the five in use, kept in the proven list when the fallback has them,
# so the next choice is made from what is known to draw.
CANDIDATES = (0x25CA, 0x263C, 0x2021, 0x2042, 0x203B, 0x25CF, 0x2726)

# Whole blocks proven at once, every assigned codepoint of each, so a French string with a new accent does
# not wait on this script: Latin-1 Supplement with Latin Extended-A, and General Punctuation.
RANGES = ((0x00A0, 0x017F, "Latin-1 Supplement and Latin Extended-A"), (0x2010, 0x205E, "General Punctuation"))
COMMENTS = (re.compile(r"--\[(=*)\[.*?\]\1\]", re.S), re.compile(r"--[^\n]*"))


def cmap(path: Path) -> list[tuple[int, int]]:
    """The inclusive codepoint ranges an sfnt font (TrueType or OpenType) maps to a real glyph."""
    data = path.read_bytes()
    (count,) = struct.unpack_from(">H", data, 4)
    table = None
    for index in range(count):
        tag, _, offset, _ = struct.unpack_from(">4sIII", data, 12 + index * 16)
        if tag == b"cmap":
            table = offset
    if table is None:
        raise ValueError(f"{path.name} has no cmap table")
    (records,) = struct.unpack_from(">H", data, table + 2)
    subtables = {}
    for index in range(records):
        platform, encoding, offset = struct.unpack_from(">HHI", data, table + 4 + index * 8)
        subtables[(platform, encoding)] = table + offset
    for key in ((3, 10), (0, 4), (0, 6)):
        if key in subtables and struct.unpack_from(">H", data, subtables[key])[0] == 12:
            return format12(data, subtables[key])
    for key in ((3, 1), (0, 3), (0, 4), (0, 6)):
        if key in subtables and struct.unpack_from(">H", data, subtables[key])[0] == 4:
            return format4(data, subtables[key])
    raise ValueError(f"{path.name} has no Unicode cmap this reads (format 4 or 12)")


def format12(data: bytes, at: int) -> list[tuple[int, int]]:
    (groups,) = struct.unpack_from(">I", data, at + 12)
    ranges = []
    for index in range(groups):
        start, end, glyph = struct.unpack_from(">III", data, at + 16 + index * 12)
        ranges.append((start + (1 if glyph == 0 else 0), end))
    return ranges


def format4(data: bytes, at: int) -> list[tuple[int, int]]:
    (doubled,) = struct.unpack_from(">H", data, at + 6)
    segments = doubled // 2
    ends = at + 14
    starts = ends + doubled + 2
    deltas = starts + doubled
    offsets = deltas + doubled
    ranges = []
    for index in range(segments):
        (end,) = struct.unpack_from(">H", data, ends + index * 2)
        (start,) = struct.unpack_from(">H", data, starts + index * 2)
        (delta,) = struct.unpack_from(">h", data, deltas + index * 2)
        (offset,) = struct.unpack_from(">H", data, offsets + index * 2)
        for code in range(start, end + 1):
            if code == 0xFFFF:
                continue
            if offset == 0:
                glyph = (code + delta) & 0xFFFF
            else:
                address = offsets + index * 2 + offset + (code - start) * 2
                (glyph,) = struct.unpack_from(">H", data, address)
                glyph = (glyph + delta) & 0xFFFF if glyph != 0 else 0
            if glyph != 0:
                ranges.append((code, code))
    return ranges


def has(ranges: list[tuple[int, int]], code: int) -> bool:
    return any(start <= code <= end for start, end in ranges)


def chain(binary: Path) -> list[str]:
    """The fallback fonts the engine registers, in order, as rbxasset paths below fonts/."""
    data = binary.read_bytes()
    at = data.find(MARKER)
    if at < 0:
        raise ValueError(f"{binary} no longer carries the default-face message; read the chain by hand")
    block = data[at + len(MARKER) : at + len(MARKER) + 4096].split(b"\x00")
    return [text[len(ASSET) :].decode() for text in block if text.startswith(ASSET)]


def faces(fonts: Path, entry: str) -> list[Path]:
    """The files on disk behind one chain entry: a family's bundled faces, or the font file itself."""
    if entry.endswith(".json"):
        family = json.loads((fonts / entry).read_text())
        return [
            fonts / face["assetId"][len("rbxasset://fonts/") :]
            for face in family["faces"]
            if face["assetId"].startswith("rbxasset://fonts/")
        ]
    path = fonts / entry
    return [path] if path.exists() else []


def sigils() -> dict[str, str]:
    source = PIGMENTS.read_text()
    block = re.search(r"PigmentConfig\.Sigils = \{\n(.*?)\n\}", source, re.S)
    if block is None:
        raise ValueError(f"{PIGMENTS} has no Sigils block this reads")
    return dict(re.findall(r'^\t(\w+) = "([^"]+)",', block.group(1), re.M))


def written() -> dict[int, str]:
    """Every codepoint past ASCII the code writes, with the first file that writes it. An identifier is ASCII,
    so once the comments are out what is left of it is the contents of strings (Vendor is not ours)."""
    found: dict[int, str] = {}
    for path in sorted(SOURCE.rglob("*.luau")):
        if "Vendor" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        for comment in COMMENTS:
            text = comment.sub("", text)
        for char in text:
            if ord(char) > 0x7F:
                found.setdefault(ord(char), str(path.relative_to(ROOT)))
    return found


def describe(code: int) -> str:
    return f"U+{code:04X} {chr(code)} {unicodedata.name(chr(code), '?')}"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fonts", type=Path, default=FONTS, help="Studio's content/fonts directory")
    parser.add_argument("--binary", type=Path, default=BINARY, help="the Studio executable")
    options = parser.parse_args(argv)

    entries = chain(options.binary)
    print("fallback chain, in the order the engine registers it:")
    loaded = []
    for entry in entries:
        files = faces(options.fonts, entry)
        loaded.append((entry, [(path.name, cmap(path)) for path in files]))
        print(f"  {entry}: {', '.join(path.name for path in files) or 'not bundled'}")
    first, first_faces = loaded[0]
    if not first_faces:
        print(f"the first fallback ({first}) has no bundled face: nothing here can be proven")
        return 1

    def drawn(code: int) -> bool:
        return all(has(ranges, code) for _, ranges in first_faces)

    def drawer(code: int) -> str:
        for entry, files in loaded:
            for name, ranges in files:
                if has(ranges, code):
                    return name
        return "nothing: an empty box"

    failures = 0
    print(f"\nsigils, against every bundled face of {first}:")
    used = []
    for pigment, text in sigils().items():
        for code in map(ord, text):
            used.append(code)
            verdict = "drawn" if drawn(code) else f"NOT in every face; first drawn by {drawer(code)}"
            print(f"  {pigment:<10} {describe(code)}: {verdict}")
            failures += 0 if drawn(code) else 1

    def ranged(code: int) -> bool:
        return any(low <= code <= high for low, high, _ in RANGES)

    for low, high, name in RANGES:
        missing = [code for code in range(low, high + 1) if unicodedata.name(chr(code), "") and not drawn(code)]
        for code in missing:
            print(f"  range {name}: {describe(code)} is NOT in every face")
        failures += len(missing)

    strings = written()
    print(f"\n{len(strings)} characters past ASCII written in src:")
    for code, path in sorted(strings.items()):
        if not drawn(code):
            print(f"  {path}: {describe(code)}: NOT in every face; first drawn by {drawer(code)}")
            failures += 1
    outside = [code for code in strings if not ranged(code)]

    proven = sorted({code for code in (*used, *CANDIDATES, *outside) if drawn(code)})
    print("\nproven codepoints, for tests/Sigils.spec.luau:")
    for code in proven:
        print(f"\t0x{code:04X}, -- {chr(code)} {unicodedata.name(chr(code), '?')}")
    print("\nproven ranges:")
    for low, high, name in RANGES:
        print(f"\t{{ 0x{low:04X}, 0x{high:04X} }}, -- {name}")
    for code in CANDIDATES:
        if not drawn(code):
            print(f"  (not proven: {describe(code)}, first drawn by {drawer(code)})")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
