class_name BodyDoll
extends Control
## HUD 上的小人體剪影：每個部位依目前狀態上色，讓玩家一眼看出自己哪裡傷了、斷了。
##   完整＝骨瓷白、受損＝灰粉、重傷＝乾涸紅、失效＝煤黑＋裂痕、斷離＝只剩虛線輪廓、異化＝舊金
##   出血中的部位外框閃紅；包紮過的部位有米黃繃帶條；縫回的斷肢在關節有一排縫線。
## 正面視角：角色的左手畫在畫面右側。只畫 LAYOUT 裡有的部位（人形玩家）。

const W := 64
const H := 122

## 部位 → 矩形（在 W×H 的格子裡）。eye/heart 是畫在其他部位上面的小記號。
const LAYOUT := {
	&"head": Rect2(24, 0, 16, 16),
	&"jaw": Rect2(27, 14, 10, 5),
	&"neck": Rect2(28, 19, 8, 5),
	&"chest": Rect2(18, 24, 28, 26),
	&"abdomen": Rect2(20, 50, 24, 16),
	&"arm_l": Rect2(47, 25, 8, 40),
	&"arm_r": Rect2(9, 25, 8, 40),
	&"leg_l": Rect2(33, 67, 10, 54),
	&"leg_r": Rect2(21, 67, 10, 54),
	&"eye_l": Rect2(34, 6, 3, 3),
	&"eye_r": Rect2(27, 6, 3, 3),
	&"heart": Rect2(34, 31, 6, 6),
}
## 縫線疤畫在哪一邊（部位與父部位相接的那一端）。
const JOINT_EDGE := {
	&"arm_l": "top", &"arm_r": "top", &"leg_l": "top", &"leg_r": "top", &"head": "bottom",
	&"jaw": "top", &"eye_l": "none", &"eye_r": "none",
}

const COLORS := {
	AnatomyTypes.PartStatus.INTACT: Color("e8e2d6"),
	AnatomyTypes.PartStatus.DAMAGED: Color("b9a3a0"),
	AnatomyTypes.PartStatus.SEVERELY_DAMAGED: Color("8b2a20"),
	AnatomyTypes.PartStatus.DISABLED: Color("2a2725"),
	AnatomyTypes.PartStatus.MUTATED: Color("a8863f"),
}
const BLEED_EDGE := Color("d0301f")
const BANDAGE := Color("efe2b0")
const STITCH := Color("1a0f0c")

var anatomy: AnatomyState
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## 一個部位在剪影上要畫成什麼樣子（測試與繪製共用）。
static func part_look(p: BodyPartState) -> Dictionary:
	var s := p.status()
	return {
		"status": s,
		"color": COLORS.get(s, Color.WHITE),
		"outline_only": s == AnatomyTypes.PartStatus.SEVERED,
		"bleeding": not p.severed and p.bleed_rate > 0.0,
		"bandaged": not p.severed and p.bandaged,
		"sutured": not p.severed and p.sutured,
		"cracked": s == AnatomyTypes.PartStatus.DISABLED,
	}

func _draw() -> void:
	draw_rect(Rect2(-4, -4, W + 8, H + 8), Color(0.08, 0.06, 0.06, 0.7))
	if anatomy == null:
		return
	var blink := fmod(_t, 0.7) < 0.35
	# 先畫大部位，再畫眼睛、心臟等小記號
	for pass_small in [false, true]:
		for pid in LAYOUT:
			var p := anatomy.get_part(pid)
			if p == null:
				continue
			var small: bool = pid in [&"eye_l", &"eye_r", &"heart"]
			if small != pass_small:
				continue
			_draw_part(pid, p, LAYOUT[pid], blink)

func _draw_part(pid: StringName, p: BodyPartState, r: Rect2, blink: bool) -> void:
	var look := part_look(p)
	if look["outline_only"]:
		_dashed(r, Color(0.55, 0.15, 0.12))
		return
	draw_rect(r, look["color"])
	if look["cracked"]:
		# 裂痕：一道斜的亮線
		draw_line(r.position + Vector2(1, r.size.y * 0.2), r.end - Vector2(1, r.size.y * 0.3), Color("6e1f19"), 1.0)
	if look["bandaged"]:
		var y := r.position.y + r.size.y * 0.45
		draw_rect(Rect2(r.position.x - 1, y, r.size.x + 2, maxf(2.0, r.size.y * 0.12)), BANDAGE)
	if look["sutured"]:
		var edge: String = JOINT_EDGE.get(pid, "top")
		if edge != "none":
			var y := r.position.y + (1.0 if edge == "top" else r.size.y - 2.0)
			var x := r.position.x
			while x < r.end.x - 1:
				draw_line(Vector2(x, y - 1), Vector2(x + 2, y + 1), STITCH, 1.0)
				x += 3
	if look["bleeding"]:
		draw_rect(r.grow(1), BLEED_EDGE if blink else Color(BLEED_EDGE, 0.4), false, 1.0)

func _dashed(r: Rect2, c: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / 3.0)
		for k in range(0, n, 2):
			draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), c, 1.0)
