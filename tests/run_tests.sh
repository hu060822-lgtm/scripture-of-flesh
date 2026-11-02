#!/usr/bin/env bash
# 執行所有測試。GDScript 的執行期錯誤不會中止測試執行器，只會讓該測試函式提早結束，
# 可能讓剩下的斷言沒有執行而「假通過」。因此這裡額外檢查輸出中是否有 SCRIPT ERROR。
# 用法：GODOT=/path/to/godot tests/run_tests.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
out="$(mktemp)"
# 匯入專案；任何腳本的解析錯誤（包括測試沒有載入的腳本）也算失敗。
"$GODOT" --headless --path . --editor --quit > "$out" 2>&1 || true
if grep -q "SCRIPT ERROR" "$out"; then
  grep -A2 "SCRIPT ERROR" "$out"
  echo "FAILED: script errors while importing the project."
  exit 1
fi
"$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | tee "$out"
code=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$out"; then
  echo ""
  echo "FAILED: script errors occurred during tests (see SCRIPT ERROR lines above)."
  exit 1
fi
exit "$code"
