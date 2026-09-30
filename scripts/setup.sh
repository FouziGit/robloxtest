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

# The definitions of the luau-lsp release rokit.toml pins, the very file CI downloads: the gate judges the same
# code the same way on every machine and on every day (tests/ToolchainPin.spec.luau keeps the three in step).
echo "▶ Roblox type definitions for luau-lsp 1.69.0"
curl -fsSL "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.69.0/scripts/globalTypes.d.luau" -o globalTypes.d.luau

echo "✔ setup complete — run scripts/check.sh"
