#!/usr/bin/env bash
# Art pipeline CLI wrapper.  Usage: tools/art/art.sh <command> [options]
#   tools/art/art.sh validate            檢查所有美術素材
#   tools/art/art.sh sync                把 bible 需要的素材補進 manifest
#   tools/art/art.sh status              產生 docs/art/ASSET_STATUS.md
#   tools/art/art.sh prompt <asset-id>   產生 AI 生成提示詞
#   tools/art/art.sh new-character <id> <S|A|B> <名字>
#   tools/art/art.sh lock <id>           鎖定已確認的角色外觀
#   tools/art/art.sh test                執行美術系統自動測試
# Set GODOT=/path/to/godot if "godot" is not on PATH (Godot 4.3).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$HERE/../../godot"
GODOT="${GODOT:-godot}"
if [ "${1:-}" = "test" ]; then
  exec "$GODOT" --headless --path "$PROJECT" -s res://scripts/art/tests/run_art_tests.gd
fi
exec "$GODOT" --headless --path "$PROJECT" -s res://scripts/art/tools/art_cli.gd -- "$@"
