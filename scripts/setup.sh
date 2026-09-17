#!/usr/bin/env bash
# One-time developer setup: toolchain, packages, Roblox type definitions.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

if ! command -v rokit >/dev/null 2>&1; then
	echo "rokit is missing. Install it with:"
	echo "  curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash"
	exit 1
fi

echo "▶ rokit install"
rokit install --no-trust-check

echo "▶ wally install"
wally install

echo "▶ Roblox type definitions for luau-lsp"
curl -fsSL "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" -o globalTypes.d.luau

echo "✔ setup complete — run scripts/check.sh"
