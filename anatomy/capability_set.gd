class_name CapabilitySet
extends RefCounted
## 從所有「仍可運作」的部位彙整出的能力標籤與數量。
## 戰鬥、移動、動畫與 AI 只讀這個物件，不直接檢查部位，
## 因此同一套邏輯可以套用在人形、多手人或任何自訂身體上。

var _counts := {}  # String -> int

func add(tag: String, n: int = 1) -> void:
	_counts[tag] = int(_counts.get(tag, 0)) + n

func count(tag: String) -> int:
	return int(_counts.get(tag, 0))

func has(tag: String) -> bool:
	return count(tag) > 0

## requirements: { "grip": 2, "bite": 1 } 代表至少兩個 grip 且至少一個 bite。
func satisfies(requirements: Dictionary) -> bool:
	for tag in requirements:
		if count(String(tag)) < int(requirements[tag]):
			return false
	return true

func tags() -> PackedStringArray:
	var out := PackedStringArray(_counts.keys())
	out.sort()
	return out

func equals(other: CapabilitySet) -> bool:
	return other != null and _counts == other._counts

func _to_string() -> String:
	var parts := PackedStringArray()
	for t in tags():
		parts.append("%s×%d" % [t, count(t)])
	return "Caps[%s]" % ", ".join(parts)
