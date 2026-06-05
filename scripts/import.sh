#!/usr/bin/env bash
# Pull the live WezTerm config back into the repo.
# Use this if the live ~/.wezterm.lua was edited directly and you want the
# repo copy to catch up before making further changes here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="$HOME/.wezterm.lua"
DEST="$REPO/wezterm.lua"

if [ ! -f "$SRC" ]; then
  echo "ERROR: live config not found: $SRC" >&2
  exit 1
fi

cp "$SRC" "$DEST"
echo "import: $SRC -> $DEST"
echo "done. Review the diff before committing."
