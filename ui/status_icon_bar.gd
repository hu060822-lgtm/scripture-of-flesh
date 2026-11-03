class_name StatusIconBar
extends Control
## 異常狀態圖標列：每個狀態一個 9×9 像素圖示（×3 放大、不濾波，PS1 風），
## 下方是名稱與數值，再下方 1–3 個小點表示強度。資料來自 StatusEffects.collect。

const PX := 3
const CELL := 9
const SLOT_W := 52
const S := preload("res://art/ps1/ps1_style.gd")

const PALETTE := {
	"r": Color("a3261c"), "d": Color("5a1a14"), "w": Color("e8e2d6"), "k": Color("2a2725"),
	"g": Color("a8863f"), "y": Color("efe2b0"), "p": Color("b9a3a0"), "G": Color("7d8a62"),
	"o": Color("c8642a"),
}

## 像素圖：'.' 透明，其餘字母對應 PALETTE。
const ICONS := {
	&"bleeding": [
		"....r....", "...rr....", "...rrr...", "..rrrrr..", "..rrwrr..",
		".rrrwrrr.", ".rrrrrrr.", "..rrrrr..", "...ddd...",
	],
	&"bleed_floor": [
		"....r....", "...rrr...", "..rrrrr..", "..rrrrr..", "...rrr...",
		".........", "wwwwwwwww", ".........", "w.w.w.w.w",
	],
	&"fracture": [
		"ww.......", "www......", ".www.....", "..www....", "...w.....",
		".....w...", "....www..", ".....www.", "......ww.",
	],
	&"burn": [
		"....o....", "...oo....", "..ooyo...", "..oyyo.o.", ".ooyyyoo.",
		".oyyyyyo.", ".oyykyyo.", "..ookoo..", "...kkk...",
	],
	&"necrosis": [
		"..GGGGG..", ".GGGGGGG.", "GGkGGGkGG", "GGkGGGkGG", "GGGGGGGGG",
		".GGG.GGG.", "..G.G.G..", "..G...G..", "......G..",
	],
	&"suffocating": [
		"....w....", ".pp.w.pp.", "pppkwkppp", "pppk.kppp", "ppp...ppp",
		"ppp...ppp", "ppp...ppp", ".pp...pp.", ".........",
	],
	&"staggered": [
		"..y...y..", "...y.y...", "....y....", ".yy.w.yy.", "....y....",
		"...y.y...", "..y...y..", ".........", "kkkkkkkkk",
	],
	&"blind": [
		".........", "..wwwwwr.", ".wwkkkrw.", "wwkkdrkww", ".wwkrkww.",
		"..wrwww..", ".r.......", "r........", ".........",
	],
	&"limping": [
		"...ww....", "...ww....", "...ww....", "....ww...", ".....ww..",
		"....ww...", "...ww....", "..wwww...", "kkkkkkkkk",
	],
	&"crawling": [
		".........", ".........", ".........", "ww.......", "wwwwwwwww",
		"wwwwwwww.", ".w..w..w.", ".........", "kkkkkkkkk",
	],
	&"armless": [
		"...ww....", "..wwww...", "..wwww...", ".wwwwww..", "rwwwwwwr.",
		"rwwwwwwr.", ".wwwwww..", ".wwwwww..", ".ww..ww..",
	],
	&"one_armed": [
		"...ww....", "..wwww...", "..wwww...", ".wwwwwww.", "rwwwwwww.",
		"rwwwwwwww", ".wwwwww.w", ".wwwwww..", ".ww..ww..",
	],
	&"bandaging": [
		".........", ".yyyyyyy.", "yyyyyyyyy", "yyyryyyyy", "yyrrryyyy",
		"yyyryyyyy", "yyyyyyyyy", ".yyyyyyy.", ".........",
	],
	&"suturing": [
		"........w", ".......w.", "......w..", ".....w...", "..r.w....",
		".r.rw....", "r...r....", ".........", ".........",
	],
	&"mutation": [
		".........", "..ggggg..", ".gyyyyyg.", "gyykkkyyg", "gyykdkyyg",
		"gyykkkyyg", ".gyyyyyg.", "..ggggg..", ".........",
	],
}

var effects: Array[Dictionary] = []
var _blink := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOT_W * 6, CELL * PX + 30)

func set_effects(list: Array[Dictionary]) -> void:
	effects = list
	custom_minimum_size.x = maxf(SLOT_W, SLOT_W * effects.size())
	queue_redraw()

func _process(delta: float) -> void:
	_blink += delta
	if not effects.is_empty():
		queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	for i in effects.size():
		var e: Dictionary = effects[i]
		var x0 := i * SLOT_W + (SLOT_W - CELL * PX) / 2
		# 底框：深色方塊，危險的狀態閃紅邊
		var frame := Rect2(x0 - 3, -3, CELL * PX + 6, CELL * PX + 6)
		draw_rect(frame, Color(0.08, 0.06, 0.06, 0.8))
		var danger: bool = int(e["level"]) >= 3 and e["id"] in [&"bleeding", &"suffocating", &"bleed_floor"]
		var edge := PALETTE["r"] if danger and fmod(_blink, 0.6) < 0.3 else Color(0.35, 0.3, 0.28)
		draw_rect(frame, edge, false, 1.0)
		draw_icon(self, e["id"], Vector2(x0, 0), PX)
		var label: String = e["label"]
		if String(e.get("text", "")) != "":
			label += " " + String(e["text"])
		draw_string(font, Vector2(i * SLOT_W, CELL * PX + 16), label, HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 11, Color("e8e2d6"))
		for k in int(e["level"]):
			draw_rect(Rect2(i * SLOT_W + SLOT_W / 2 - 7 + k * 6, CELL * PX + 21, 4, 3), PALETTE["r"] if danger else PALETTE["g"])

## 在任意 CanvasItem 上畫一個像素圖示。
static func draw_icon(ci: CanvasItem, id: StringName, at: Vector2, px: int) -> void:
	var rows: Array = ICONS.get(id, [])
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var c := row[x]
			if c == ".":
				continue
			ci.draw_rect(Rect2(at + Vector2(x * px, y * px), Vector2(px, px)), PALETTE.get(c, Color.MAGENTA))
