class_name AnatomyTypes
extends RefCounted
## 部位狀態。注意「功能失效」與「斷離」是兩個不同事件。

enum PartStatus {
	INTACT,            ## 完整
	DAMAGED,           ## 受損（HP < 75%）
	SEVERELY_DAMAGED,  ## 嚴重受損（HP < 35%）
	DISABLED,          ## 功能失效（HP 歸零、骨折、或依賴部位失效）
	SEVERED,           ## 斷離
	MUTATED,           ## 異化（仍可運作，功能可能被改寫）
}

const DAMAGED_RATIO := 0.75
const SEVERELY_DAMAGED_RATIO := 0.35

const STATUS_LABELS := ["完整", "受損", "重傷", "失效", "斷離", "異化"]

## 介面顯示用的中文狀態名稱。
static func status_name(s: int) -> String:
	return STATUS_LABELS[s] if s >= 0 and s < STATUS_LABELS.size() else str(s)

## 列舉鍵名（除錯用）。
static func status_key(s: int) -> String:
	return PartStatus.keys()[s]

## 連體生物的部位 id 以 _a／_b 標示屬於哪一半（例如 head_a、arm_l_b）。
## 回傳去掉字尾的基本 id，讓模型、動畫用同一套規則處理（其他生物的 id 原樣回傳）。
static func base_part_id(id: StringName) -> String:
	var s := String(id)
	if s.length() > 2 and (s.ends_with("_a") or s.ends_with("_b")):
		return s.substr(0, s.length() - 2)
	return s
