class_name AnimationSet
extends RefCounted
## 依能力彙整決定要用哪一組動作。避免「每種缺損組合一套動畫」的組合爆炸：
## 手臂分 雙手／單手／無手，腿分 雙腿／單腿／爬行，共 9 種組合，對應少數動作組。
## 注意：目前專案還沒有 AnimationTree 與動畫素材（M3 之後），這裡只決定「該用哪一組」。

const ARMS_TWO := &"arms_two"
const ARMS_ONE := &"arms_one"
const ARMS_NONE := &"arms_none"
const LEGS_TWO := &"legs_two"
const LEGS_ONE := &"legs_one"
const LEGS_CRAWL := &"legs_crawl"

static func from_capabilities(caps: CapabilitySet) -> Dictionary:
	var grip := caps.count("grip")
	var loco := caps.count("locomotion")
	return {
		"arms": ARMS_TWO if grip >= 2 else (ARMS_ONE if grip == 1 else ARMS_NONE),
		"legs": LEGS_TWO if loco >= 2 else (LEGS_ONE if loco == 1 else LEGS_CRAWL),
	}
