#!/usr/bin/env bash
# Deploy the repo's wezterm.lua to the live WezTerm config location.
# Backs up the current live config first, then copies the repo copy over.
# WezTerm auto-reloads config on save, so no restart is needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="$REPO/wezterm.lua"
DEST="$HOME/.wezterm.lua"
BACKUP_DIR="$REPO/backups"

if [ ! -f "$SRC" ]; then
  echo "ERROR: source config not found: $SRC" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

if [ -f "$DEST" ]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="$BACKUP_DIR/wezterm.lua.$STAMP.bak"
  cp "$DEST" "$BACKUP"
  echo "backup: $DEST -> $BACKUP"
else
  echo "note: no existing live config at $DEST (first deploy)"
fi

cp "$SRC" "$DEST"
echo "deploy: $SRC -> $DEST"
echo "done. WezTerm should auto-reload; if not, press the reload key or restart it."
