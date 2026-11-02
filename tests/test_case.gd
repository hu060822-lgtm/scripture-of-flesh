class_name TestCase
extends RefCounted
## 極簡測試基底類別。方法名稱以 test_ 開頭者會被 tests/run_tests.gd 執行。

var failures: Array[String] = []
## 測試執行器的 SceneTree。測試結束後，加入 tree.root 的節點會被自動清除。
var tree: SceneTree
var _current := ""

func before_each() -> void:
	pass

func fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])

func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)

func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)

func assert_eq(actual, expected, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("%s expected %s (%s) got %s (%s)" % [msg, expected, type_string(typeof(expected)), actual, type_string(typeof(actual))])
	elif actual != expected:
		fail("%s expected %s got %s" % [msg, expected, actual])

func assert_near(actual: float, expected: float, eps: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s expected ≈%s got %s" % [msg, expected, actual])

func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
