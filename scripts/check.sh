#!/usr/bin/env bash
# Quality gates. All must pass before any commit (see CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

if [ ! -f globalTypes.d.luau ] || [ ! -d Packages ]; then
	echo "Missing setup artefacts — running scripts/setup.sh"
	./scripts/setup.sh
fi

echo "▶ stylua --check"
stylua --check src tests

echo "▶ selene"
selene src tests

echo "▶ rojo sourcemap"
rojo sourcemap default.project.json -o sourcemap.json

# All of src, not just src/shared. The narrow gate was a real hole: every client controller, every UI
# component and every server service was unchecked, which is three quarters of the code and all of the
# code that touches the engine. Vendor/ is excluded because vendored ProfileStore is not ours to fix.
echo "▶ luau-lsp analyze (strict gate on all of src)"
luau-lsp analyze \
	--definitions=globalTypes.d.luau \
	--sourcemap=sourcemap.json \
	--settings=.luau-lsp.json \
	--ignore="Packages/**" \
	--ignore="**/Vendor/**" \
	src

echo "▶ lune tests"
lune run tests/run

echo "▶ hard-coded strings"
lune run scripts/check-strings

echo "▶ localization.csv"
lune run scripts/export-strings -- --check

# The generators and the PNGs they wrote are two artefacts that have to agree, and nothing else in this
# repository notices when they stop agreeing. An edit to a generator with no regeneration, or a PNG
# edited by hand, both pass every other gate here and only show up as art that does not match its own
# source. Eight seconds to close that.
#
# This is the one gate that needs Python. The PNGs stay committed, so a contributor without Python can
# still build and run the game; they just cannot prove the art is reproducible.
echo "▶ textures reproduce from their generators"
python3 tools/textures/generate_all.py >/dev/null
if ! git diff --quiet -- assets/textures; then
	echo "✖ assets/textures does not match what tools/textures/ generates:"
	git --no-pager diff --stat -- assets/textures
	echo "  Run python3 tools/textures/generate_all.py and commit the result."
	exit 1
fi

# The other half of the same proof: AssetIds says how far each texture's ink reaches, and the boss
# telegraph test trusts it. Measured off the files here, because Lune cannot decode a PNG.
echo "▶ ink reach matches AssetIds"
python3 tools/textures/check_ink.py

# The same proof for the sound: every WAV is written by tools/audio and the bytes on disk are the
# bytes the generators write. A generator that picked up a libm call on a per-sample path shows up
# here as a diff on the machine whose libm disagrees.
echo "▶ audio reproduces from its generators"
python3 tools/audio/generate_all.py >/dev/null
if ! git diff --quiet -- assets/audio; then
	echo "✖ assets/audio does not match what tools/audio/ generates:"
	git --no-pager diff --stat -- assets/audio
	echo "  Run python3 tools/audio/generate_all.py and commit the result."
	exit 1
fi

echo "▶ rojo build"
mkdir -p build
rojo build default.project.json -o build/Vellum.rbxl

echo "✔ all quality gates green"
