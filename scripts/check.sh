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

echo "▶ luau-lsp analyze (strict gate on src/shared)"
luau-lsp analyze \
	--definitions=globalTypes.d.luau \
	--sourcemap=sourcemap.json \
	--settings=.luau-lsp.json \
	--ignore="Packages/**" \
	src/shared

echo "▶ lune tests"
lune run tests/run

echo "▶ hard-coded strings"
lune run scripts/check-strings

echo "▶ localization.csv"
lune run scripts/export-strings -- --check

echo "▶ rojo build"
mkdir -p build
rojo build default.project.json -o build/Vellum.rbxl

echo "✔ all quality gates green"
