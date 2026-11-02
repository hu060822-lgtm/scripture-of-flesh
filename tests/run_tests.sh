#!/usr/bin/env bash
# 執行所有測試。GDScript 的執行期錯誤不會中止測試執行器，只會讓該測試函式提早結束，
# 可能讓剩下的斷言沒有執行而「假通過」。因此這裡額外檢查輸出中是否有 SCRIPT ERROR。
# 用法：GODOT=/path/to/godot tests/run_tests.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --editor --quit >/dev/null 2>&1 || true
out="$(mktemp)"
"$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | tee "$out"
code=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$out"; then
  echo ""
  echo "FAILED: script errors occurred during tests (see SCRIPT ERROR lines above)."
  exit 1
fi
exit "$code"
