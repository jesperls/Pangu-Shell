#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../shell" && pwd)"

command -v qsb >/dev/null 2>&1 || {
    echo "qsb not found on PATH — try: nix shell nixpkgs#qt6.qtshadertools" >&2
    exit 1
}

while IFS= read -r -d '' src; do
    qsb --qt6 "$src" -o "${src}.qsb"
done < <(find "$root" \( -name '*.frag' -o -name '*.vert' \) -print0)
