#!/usr/bin/env bash
# Opens the Creator Workshop (import / draw / manage portraits).
#   tools/art/workshop.sh                  open the workshop
#   tools/art/workshop.sh draw [ids...]    redraw Portrait Maker images for all (or the given) characters that have a maker.json
# Set GODOT=/path/to/godot if godot is not on PATH. Needs a display (not headless).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$HERE/../../godot"
GODOT="${GODOT:-godot}"
if [ "${1:-}" = "draw" ]; then
  shift
  exec "$GODOT" --path "$PROJECT" -s res://scripts/art/tools/maker_export.gd -- "$@"
fi
exec "$GODOT" --path "$PROJECT" res://scripts/art/workshop/creator_workshop.tscn -- "$@"
