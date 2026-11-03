extends SceneTree
## 一次性產生序章灰盒關卡 scenes/prologue/prologue_level.tscn（之後以 Godot 編輯器直接編輯 .tscn 為準）。
## 執行：godot --headless --path . -s tools/generate_prologue_level.gd
## 注意：重新執行會覆蓋同名檔案（在編輯器中做的修改會遺失）。
##
## 線性探索式配置（序章提案 D，由 LevelKit 組成）：
##   白色產房 → 縫合迴廊（轉角、往上的坡道）→ 庭院南側的高台迴廊（祭壇、伊格納、阿格妮絲留下的手臂）
##   → 走坡道或從欄杆缺口跳下 → 反足者庭院
##     ├─ 西：觀察者藏書室（書架走道；觀察者之眼看得見的經文 → 隱藏書庫）
##     │      ├─ 南牆的坡道往下：冷藏室（冰櫃之間的蛇行走道、裝死的屍體、靜默區）→ 伊蓮的冰櫃
##     │      │    （伊格納要的「最初的縫線」、瑪德蓮的生日信、祭壇、冰封的縫屍者）
##     │      └─ 北側走道的坡道往下：水室（選配強敵「長子」）
##     ├─ 東：狹長通道 → 多手人聖器室（掌紋鎖、臍帶鑰匙 → 母親從東牆後破牆追出來）
##     │      逃回庭院後，從庭院側拉開高台東側坡道的捷徑門 → 直通祭壇
##     └─ 北：禮拜堂大門（需臍帶鑰匙）→ 前廳 → 母親的禮拜堂
## 所有幾何皆為【暫代】灰盒。

const OUT := "res://scenes/prologue/prologue_level.tscn"
const WALL_H := 4.0
const WALL_T := 0.5
const E := "res://content/enemies/%s.tres"
const W := "res://content/weapons/%s.tres"

var level: Node3D
var geo: Node3D
## 不直接引用 class_name：-s 模式下 autoload 在第一個 frame 才存在，相依腳本須延後編譯。
var Greybox: GDScript
var StitchingAltar: GDScript
var EnemySpawn: GDScript
var DialogueInteractable: GDScript
var WeaponPedestal: GDScript
var ItemPickup: GDScript
var AreaTrigger: GDScript
var BossGate: GDScript
var Kit: GDScript
var ShortcutGate: GDScript
var PalmLock: GDScript
var HiddenScripture: GDScript
var SecretWall: GDScript
var ScareTrigger: GDScript
var SilenceZone: GDScript
var ScripturePage: GDScript
var ConjoinedSpawn: GDScript
var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false

func _run() -> void:
	Greybox = load("res://game/greybox.gd")
	StitchingAltar = load("res://world/stitching_altar.gd")
	EnemySpawn = load("res://world/enemy_spawn.gd")
	DialogueInteractable = load("res://world/dialogue_interactable.gd")
	WeaponPedestal = load("res://world/weapon_pedestal.gd")
	ItemPickup = load("res://world/item_pickup.gd")
	AreaTrigger = load("res://world/area_trigger.gd")
	BossGate = load("res://world/boss_gate.gd")
	Kit = load("res://game/level_kit.gd")
	ShortcutGate = load("res://world/shortcut_gate.gd")
	PalmLock = load("res://world/palm_lock.gd")
	HiddenScripture = load("res://world/hidden_scripture.gd")
	SecretWall = load("res://world/secret_wall.gd")
	ScareTrigger = load("res://world/scare_trigger.gd")
	SilenceZone = load("res://world/silence_zone.gd")
	ScripturePage = load("res://world/scripture_page.gd")
	ConjoinedSpawn = load("res://world/conjoined_spawn.gd")
	level = Node3D.new()
	level.name = "PrologueLevel"
	geo = _group("Geometry")
	for n in ["Markers", "Altars", "Interactables", "Spawns", "Triggers", "Lights", "Secrets"]:
		_group(n)
	_environment()
	_build()
	_own(level, level)
	var packed := PackedScene.new()
	var err := packed.pack(level)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("saved prologue level -> %s [%s]" % [OUT, error_string(err)])
	level.free()
	quit()

func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	level.add_child(g)
	return g

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)

func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0d0b0a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("6b6055")
	env.environment.ambient_light_energy = 0.35
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color("2a2220")
	env.environment.fog_density = 0.015
	level.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Moon"
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.35
	sun.light_color = Color("b8c0d0")
	sun.shadow_enabled = true
	level.add_child(sun)

# ---------- 幾何 ----------

## 一個房間：地板 + 四面牆。doors: {"n"/"s"/"e"/"w": [開口中心偏移, 開口寬度]}
func _room(name: String, center: Vector3, size: Vector2, doors: Dictionary, wall_color: Color = Color("cfc8b8")) -> void:
	var g := Node3D.new()
	g.name = name
	geo.add_child(g)
	var f: Node3D = Greybox.floor_plane(g, center, size)
	f.name = "Floor"
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_wall(g, "WallN", center + Vector3(0, 0, -hz), size.x, true, doors.get("n", []), wall_color)
	_wall(g, "WallS", center + Vector3(0, 0, hz), size.x, true, doors.get("s", []), wall_color)
	_wall(g, "WallE", center + Vector3(hx, 0, 0), size.y, false, doors.get("e", []), wall_color)
	_wall(g, "WallW", center + Vector3(-hx, 0, 0), size.y, false, doors.get("w", []), wall_color)

## 沿 X（along_x）或 Z 方向的一面牆，可以有一個開口。
func _wall(parent: Node, name: String, mid: Vector3, length: float, along_x: bool, door: Array, color: Color) -> void:
	var segments := []  # [start, end]（沿牆的區段座標，-length/2..length/2）
	if door.is_empty():
		segments.append([-length * 0.5, length * 0.5])
	else:
		var off: float = door[0]
		var width: float = door[1]
		segments.append([-length * 0.5, off - width * 0.5])
		segments.append([off + width * 0.5, length * 0.5])
	var i := 0
	for s in segments:
		var a: float = s[0]
		var b: float = s[1]
		if b - a < 0.05:
			continue
		var c := (a + b) * 0.5
		var pos := mid + (Vector3(c, WALL_H * 0.5, 0) if along_x else Vector3(0, WALL_H * 0.5, c))
		var sz := Vector3(b - a, WALL_H, WALL_T) if along_x else Vector3(WALL_T, WALL_H, b - a)
		var w: Node3D = Greybox.box(parent, pos, sz, color)
		w.name = "%s_%d" % [name, i]
		i += 1

func _prop(name: String, pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	var b: Node3D = Greybox.box(geo, pos + Vector3(0, size.y * 0.5, 0), size, color, collide)
	b.name = name

func _light(name: String, pos: Vector3, color: Color, energy: float = 1.2, range: float = 10.0) -> void:
	var l := OmniLight3D.new()
	l.name = name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range
	l.shadow_enabled = false
	level.get_node("Lights").add_child(l)

# ---------- 物件 ----------

func _marker(name: String, pos: Vector3, yaw: float = 0.0) -> void:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	m.rotation_degrees.y = yaw
	level.get_node("Markers").add_child(m)

func _altar(id: StringName, pos: Vector3) -> void:
	var a = StitchingAltar.new()
	a.name = "Altar_%s" % id
	a.altar_id = id
	a.position = pos
	level.get_node("Altars").add_child(a)

func _spawn(id: StringName, enemy: String, pos: Vector3, facing: float = 0.0, mode: String = "alive") -> void:
	var s = EnemySpawn.new()
	s.mode = mode
	s.name = "Spawn_%s" % id
	s.spawn_id = id
	s.enemy_path = E % enemy
	s.position = pos
	s.facing_degrees = facing
	level.get_node("Spawns").add_child(s)

func _inscription(id: String, pos: Vector3, yaw: float = 0.0) -> void:
	var d = DialogueInteractable.new()
	d.name = "Inscription_%s" % id
	d.object_id = StringName(id)
	d.dialogue_id = id
	d.kind = "inscription"
	d.prompt_text = "E：閱讀"
	d.position = pos
	d.rotation_degrees.y = yaw
	level.get_node("Interactables").add_child(d)

## 劇情筆記（散落的紙頁）：可重複閱讀，第一次閱讀時設定劇情旗標。
func _note(id: String, pos: Vector3) -> void:
	var d = DialogueInteractable.new()
	d.name = "Note_%s" % id
	d.object_id = StringName(id)
	d.dialogue_id = id
	d.kind = "note"
	d.prompt_text = "E：閱讀紙頁"
	d.position = pos
	level.get_node("Interactables").add_child(d)

func _pedestal(weapon: String, pos: Vector3) -> void:
	var p = WeaponPedestal.new()
	p.name = "Pedestal_%s" % weapon
	p.object_id = StringName("pedestal_" + weapon)
	p.weapon_path = W % weapon
	p.position = pos
	level.get_node("Interactables").add_child(p)

func _item(id: String, item: String, count: int, pos: Vector3, hint: String = "") -> void:
	var it = ItemPickup.new()
	it.hint_text = hint
	it.name = "Item_%s" % id
	it.object_id = StringName(id)
	it.item_id = item
	it.count = count
	it.position = pos
	level.get_node("Interactables").add_child(it)

func _trigger(id: StringName, pos: Vector3, radius: float, area_name: String = "", dialogue: String = "", flag: StringName = &"", require: StringName = &"") -> void:
	var t = AreaTrigger.new()
	t.name = "Trigger_%s" % id
	t.trigger_id = id
	t.position = pos
	t.radius = radius
	t.area_name = area_name
	t.dialogue_id = dialogue
	t.set_flag = flag
	t.require_flag = require
	level.get_node("Triggers").add_child(t)

# ---------- 關卡 ----------

const SHELF := Color("4a3a2c")

## 區域群組（Geometry 底下；測試以名稱檢查區域存在）。
func _area(name: String) -> Node3D:
	return Kit.group(geo, name)

## 四面牆的房間（_room 的 LevelKit 版本，可指定地板高度與多個開口）。
## gaps: {"n"/"s"/"e"/"w": [[距西／北端的開口中心, 寬度], ...]}；skip 列出不要建的牆（與鄰區共用）。
func _box_room(g: Node3D, x0: float, x1: float, z0: float, z1: float, y: float, height: float, gaps: Dictionary, color: Color, skip: Array = []) -> void:
	# z0 為南（較大的 z），z1 為北
	Kit.floor_rect(g, "Floor", x0, x1, z0, z1, y)
	var top := y + height
	if not "s" in skip:
		Kit.wall(g, "WallS", Vector2(x0, z0), Vector2(x1, z0), y, top, gaps.get("s", []), color)
	if not "n" in skip:
		Kit.wall(g, "WallN", Vector2(x0, z1), Vector2(x1, z1), y, top, gaps.get("n", []), color)
	if not "w" in skip:
		Kit.wall(g, "WallW", Vector2(x0, z0), Vector2(x0, z1), y, top, gaps.get("w", []), color)
	if not "e" in skip:
		Kit.wall(g, "WallE", Vector2(x1, z0), Vector2(x1, z1), y, top, gaps.get("e", []), color)

func _gprop(g: Node3D, name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var b: Node3D = Greybox.box(g, pos + Vector3(0, size.y * 0.5, 0), size, color)
	b.name = name

func _build() -> void:
	_build_delivery()
	_build_corridor()
	_build_courtyard()
	_build_archive()
	_build_cistern()
	_build_sacristy()
	_build_chapel()
	_build_cold_storage()
	_build_horror()

# 1. 白色產房（起點）：x -6..6，z 6..-6
func _build_delivery() -> void:
	var g := _area("DeliveryRoom")
	_box_room(g, -6, 6, 6, -6, 0.0, 4.0, {"n": [[6.0, 3.0]]}, Color("efece6"))
	_prop("DeliveryTable", Vector3(0, 0, 2.2), Vector3(1.0, 0.9, 2.2), Color("f4f2ee"))
	_prop("Cradle_1", Vector3(-4.5, 0, 4), Vector3(0.8, 0.6, 1.2), Color("d8d0c0"))
	_prop("Cradle_2", Vector3(-4.5, 0, 2), Vector3(0.8, 0.6, 1.2), Color("d8d0c0"))
	_prop("Cradle_3", Vector3(-4.5, 0, 0), Vector3(0.8, 0.6, 1.2), Color("d8d0c0"))
	_marker("PlayerStart", Vector3(1.2, 0, 2.2), 0.0)
	var agnes = DialogueInteractable.new()
	agnes.name = "NPC_Agnes"
	agnes.object_id = &"npc_agnes"
	agnes.kind = "npc"
	agnes.dialogue_id = "agnes_intro"
	agnes.repeat_dialogue_id = "agnes_return"
	agnes.first_done_flag = &"met_agnes"
	agnes.prompt_text = "E：與助產修女阿格妮絲交談"
	agnes.position = Vector3(-2.2, 0, 0.5)
	agnes.rotation_degrees.y = -60
	level.get_node("Interactables").add_child(agnes)
	_inscription("inscription_delivery", Vector3(4.5, 0, -4.5), 0.0)
	_altar(&"altar_delivery", Vector3(3.5, 0, 3.5))
	_note("note_register", Vector3(-4.5, 0, -1.6))
	_item("item_delivery_suture", "suture_kit", 1, Vector3(4.5, 0, 0))
	_trigger(&"enter_delivery", Vector3(0, 0, 2), 3.0, "白色產房")
	_light("Light_Delivery", Vector3(0, 3.5, 0), Color("fff4e0"), 1.6, 12.0)

# 2. 縫合迴廊：往北的走廊 → 向東轉角 → 往北上升的坡道（高 2m）→ 接上庭院的高台迴廊
func _build_corridor() -> void:
	var g := _area("SutureCorridor")
	var c := Color("b8b0a0")
	Kit.floor_rect(g, "Floor_North", -1.5, 1.5, -6, -14)
	Kit.floor_rect(g, "Floor_Turn", -1.5, 9.5, -14, -17.5)
	Kit.wall(g, "WallW", Vector2(-1.5, -6), Vector2(-1.5, -17.5), 0, 4, [], c)
	Kit.wall(g, "WallE", Vector2(1.5, -6), Vector2(1.5, -14), 0, 4, [], c)
	Kit.wall(g, "WallTurnS", Vector2(1.5, -14), Vector2(9.5, -14), 0, 4, [], c)
	Kit.wall(g, "WallTurnN", Vector2(-1.5, -17.5), Vector2(6, -17.5), 0, 4, [], c)
	Kit.ramp(g, "Ramp", Vector3(7.75, 0, -17.5), Vector3(7.75, 2, -23.5), 3.5)
	Kit.floor_rect(g, "Landing", 6, 9.5, -23.5, -26, 2.0)
	Kit.wall(g, "WallRampW", Vector2(6, -17.5), Vector2(6, -26), 0, 4.5, [], c)
	Kit.wall(g, "WallRampE", Vector2(9.5, -14), Vector2(9.5, -26), 0, 4.5, [], c)
	_prop("Gurney_1", Vector3(-0.7, 0, -10), Vector3(0.8, 0.8, 1.8), Color("6b625a"))
	_prop("Gurney_2", Vector3(3.5, 0, -16.6), Vector3(1.8, 0.8, 0.8), Color("6b625a"))
	_spawn(&"corridor_stitcher_1", "stitcher", Vector3(0.4, 0, -12), 180.0)
	_spawn(&"corridor_stitcher_2", "stitcher", Vector3(5.5, 0, -15.7), 90.0)
	_inscription("inscription_corridor", Vector3(-1.15, 0, -9), 90.0)
	_note("note_stitcher", Vector3(-0.9, 0, -13.2))
	_trigger(&"enter_corridor", Vector3(0, 0, -8), 2.5, "縫合迴廊", "corridor_thought")
	_light("Light_Corridor_1", Vector3(0, 3.2, -10), Color("d0a070"), 0.9, 7.0)
	_light("Light_Corridor_2", Vector3(5, 3.2, -15.7), Color("d0a070"), 0.9, 7.0)
	_light("Light_Corridor_3", Vector3(7.75, 4.8, -22), Color("d0a070"), 0.8, 7.0)

# 3. 反足者庭院：x -10..10，z -26..-46。南側 4m 是 2m 高的高台迴廊（z -26..-30）。
#    下到庭院：西側坡道（x -6..-3）或欄杆缺口直接跳下（x 1..3，單向）。
#    東側坡道（x 7..10）底部是捷徑門，只能從庭院這一側拉開。
func _build_courtyard() -> void:
	var g := _area("Courtyard")
	var c := Color("9a9284")
	Kit.floor_rect(g, "Floor", -10, 10, -30, -46)
	Kit.floor_rect(g, "Terrace", -10, 10, -26, -30, 2.0, Color("4a4440"))
	Kit.wall(g, "WallS", Vector2(-10, -26), Vector2(10, -26), 0, 5, [[17.75, 3.5]], c)
	Kit.wall(g, "WallW", Vector2(-10, -26), Vector2(-10, -46), 0, 5, [[10.0, 3.0]], c)
	Kit.wall(g, "WallE", Vector2(10, -26), Vector2(10, -46), 0, 5, [[14.0, 3.5]], c)
	Kit.wall(g, "WallN", Vector2(-10, -46), Vector2(10, -46), 0, 5, [[10.0, 4.0]], c)
	# 高台邊緣的欄杆：西坡道口、跳下缺口、東坡道口
	Kit.railing(g, "TerraceRail", Vector2(-10, -30), Vector2(10, -30), 2.0, [[5.5, 3.0], [12.0, 2.0], [18.5, 3.0]])
	Kit.ramp(g, "StairsWest", Vector3(-4.5, 0, -36), Vector3(-4.5, 2, -30), 3.0)
	Kit.wall(g, "StairsWestRailW", Vector2(-6, -30), Vector2(-6, -36), 0, 3.1, [], Color("8a8070"), 0.3)
	Kit.wall(g, "StairsWestRailE", Vector2(-3, -30), Vector2(-3, -36), 0, 3.1, [], Color("8a8070"), 0.3)
	Kit.ramp(g, "StairsEast", Vector3(8.5, 0, -36), Vector3(8.5, 2, -30), 3.0)
	Kit.wall(g, "StairsEastRail", Vector2(7, -30), Vector2(7, -36.2), 0, 3.1, [], Color("8a8070"), 0.3)
	var gate = ShortcutGate.new()
	gate.name = "ShortcutGate_Courtyard"
	gate.object_id = &"shortcut_courtyard"
	gate.gate_size = Vector3(3.0, 3.2, 0.4)
	gate.position = Vector3(8.5, 0, -36.4)
	level.get_node("Interactables").add_child(gate)
	_prop("Obelisk", Vector3(0, 0, -38), Vector3(1.2, 3.0, 1.2), Color("5a524a"))
	_prop("Pillar_1", Vector3(-6, 0, -41), Vector3(0.8, 4.0, 0.8), Color("8a8070"))
	_prop("Pillar_2", Vector3(5, 0, -41), Vector3(0.8, 4.0, 0.8), Color("8a8070"))
	_spawn(&"courtyard_reverse_1", "reverse_legged", Vector3(-4, 0, -41), 160.0)
	_spawn(&"courtyard_reverse_2", "reverse_legged", Vector3(5, 0, -44), 200.0)
	_spawn(&"courtyard_stitcher", "stitcher", Vector3(2, 0, -34), 180.0)
	# 高台：祭壇、垂死的司祭、阿格妮絲留下的手臂（提案 B）、骨鋸斧
	_altar(&"altar_courtyard", Vector3(4.5, 2.0, -27.4))
	var priest = DialogueInteractable.new()
	priest.name = "NPC_Ignatius"
	priest.object_id = &"npc_ignatius"
	priest.kind = "npc"
	priest.dialogue_id = "ignatius_talk"
	priest.repeat_dialogue_id = "ignatius_return"
	priest.first_done_flag = &"met_ignatius"
	priest.prompt_text = "E：靠近垂死的司祭"
	priest.position = Vector3(2.2, 2.0, -27.0)
	priest.rotation_degrees.y = -120
	level.get_node("Interactables").add_child(priest)
	_item("item_agnes_arm", "organ:agnes_arm", 1, Vector3(6.0, 2.0, -27.0), "阿格妮絲的字條：「它會聽你的話。」在祭壇按 T 移植")
	_pedestal("bone_saw_cleaver", Vector3(-8.5, 2.0, -27.5))
	_inscription("inscription_courtyard", Vector3(0, 0, -37.2), 0.0)
	_item("item_courtyard_suture", "suture_kit", 1, Vector3(-8.5, 0, -44.5))
	_trigger(&"enter_courtyard", Vector3(7.75, 2.0, -26.5), 2.5, "反足者庭院")
	_light("Light_Courtyard", Vector3(0, 6.0, -38), Color("a0a8c0"), 1.0, 16.0)
	_light("Light_Terrace", Vector3(3, 4.5, -27.5), Color("d0a070"), 0.8, 8.0)

# 4. 觀察者藏書室（西）：x -24..-10，z -29..-43。兩排書架隔出蛇行走道（觀察者被看著就不會動）。
#    最北側走道：牆上只有拿著觀察者眼柄才看得見的經文 → 打開隱藏書庫；另一頭的坡道往下通往水室。
func _build_archive() -> void:
	var g := _area("Archive")
	var c := Color("7a6a58")
	Kit.floor_rect(g, "Floor", -24, -10, -29, -43)
	# 南牆的門（x -20）：坡道往下通往冷藏室
	Kit.wall(g, "WallS", Vector2(-24, -29), Vector2(-10, -29), 0, 4, [[4.0, 2.5]], c)
	Kit.wall(g, "WallN", Vector2(-24, -43), Vector2(-10, -43), 0, 4, [[11.0, 2.5]], c)
	Kit.wall(g, "WallW", Vector2(-24, -29), Vector2(-24, -43), 0, 4, [[12.5, 2.0]], c)
	_gprop(g, "ShelfRow_A", Vector3(-19, 0, -33), Vector3(10.0, 3.0, 0.6), SHELF)
	_gprop(g, "ShelfRow_B", Vector3(-15, 0, -39), Vector3(10.0, 3.0, 0.6), SHELF)
	_gprop(g, "Lectern", Vector3(-17, 0, -30.4), Vector3(0.8, 1.1, 0.6), SHELF)
	_spawn(&"archive_watcher_1", "faceless_watcher", Vector3(-21.5, 0, -36), 90.0)
	_spawn(&"archive_watcher_2", "faceless_watcher", Vector3(-14, 0, -31), 90.0)
	_pedestal("anatomist_rapier", Vector3(-22.5, 0, -31))
	_inscription("inscription_archive", Vector3(-17, 0, -29.6), 180.0)
	_note("note_stripping", Vector3(-11.5, 0, -41.5))
	_item("item_archive_suture", "suture_kit", 2, Vector3(-17, 0, -42.2))
	_trigger(&"enter_archive", Vector3(-11.5, 0, -36), 2.5, "觀察者藏書室")
	_light("Light_Archive", Vector3(-17, 3.2, -36), Color("80a070"), 0.8, 10.0)
	# 隱藏經文（提案 A）與書架後的隱藏書庫（提案 G）
	var hs = HiddenScripture.new()
	hs.name = "HiddenScripture_Archive"
	hs.object_id = &"hidden_scripture_archive"
	hs.dialogue_id = "hidden_scripture"
	hs.kind = "inscription"
	hs.prompt_text = "E：閱讀浮現的經文"
	hs.position = Vector3(-23.65, 0, -38.0)
	hs.rotation_degrees.y = 90
	level.get_node("Interactables").add_child(hs)
	var sw = SecretWall.new()
	sw.name = "SecretWall_Archive"
	sw.open_flag = &"secret_archive"
	sw.size = Vector3(0.5, 4.0, 2.0)
	sw.color = SHELF
	sw.position = Vector3(-24, 0, -41.5)
	level.get_node("Secrets").add_child(sw)
	var s := _area("SecretLibrary")
	_box_room(s, -30, -24, -39, -44, 0.0, 4.0, {}, Color("5a4a3a"), ["e"])
	_gprop(s, "SecretShelf", Vector3(-27, 0, -43.4), Vector3(4.0, 2.6, 0.6), SHELF)
	_item("item_secret_watcher_eye", "organ:watcher_eye", 1, Vector3(-28.5, 0, -41.0), "被藏起來的「看見」。可以在祭壇移植")
	_item("item_secret_vials", "blood_vial", 2, Vector3(-26.0, 0, -40.0))
	_light("Light_Secret", Vector3(-27, 3.0, -41.5), Color("c9a27a"), 0.7, 6.0)

# 5. 水室（提案 G，選配）：從藏書室北側走道的坡道往下 2m。長子守著鐵製義肢。
func _build_cistern() -> void:
	var g := _area("Cistern")
	var c := Color("4a5258")
	Kit.ramp(g, "Ramp", Vector3(-13, -2, -49), Vector3(-13, 0, -43), 2.5)
	Kit.wall(g, "RampWallW", Vector2(-14.25, -43), Vector2(-14.25, -49), -2, 1.0, [], c)
	Kit.wall(g, "RampWallE", Vector2(-11.75, -43), Vector2(-11.75, -49), -2, 1.0, [], c)
	_box_room(g, -24, -10.5, -49, -57.5, -2.0, 3.0, {"s": [[11.0, 2.5]]}, c)
	_gprop(g, "Basin", Vector3(-17, -2, -53.5), Vector3(3.0, 0.4, 2.0), Color("2a3238"))
	_spawn(&"cistern_firstborn", "unborn_elite", Vector3(-19, -2, -54), 90.0)
	_item("item_cistern_iron_arm", "organ:iron_arm", 1, Vector3(-22.5, -2, -56.5), "鐵製義肢：不會排斥、不會異化（需要技術 12）")
	_item("item_cistern_suture", "suture_kit", 2, Vector3(-22.5, -2, -50.5))
	_inscription("inscription_cistern", Vector3(-15.6, 0, -42.6), 180.0)
	_trigger(&"enter_cistern", Vector3(-13, -2, -50.5), 2.0, "水室")
	_light("Light_Cistern", Vector3(-17, 1.0, -53), Color("6080a0"), 0.7, 10.0)

# 6. 多手人聖器室（東）：狹長通道 x 10..18 → 房間 x 18..30，z -34..-46。
#    拿到臍帶鑰匙時，東牆後的母親撞破牆追出來（提案 E），玩家要沿通道逃回庭院。
func _build_sacristy() -> void:
	var g := _area("Sacristy")
	var c := Color("8a6a5a")
	Kit.floor_rect(g, "PassageFloor", 10, 18, -38.25, -41.75)
	Kit.wall(g, "PassageWallS", Vector2(10, -38.25), Vector2(18, -38.25), 0, 4, [], c)
	Kit.wall(g, "PassageWallN", Vector2(10, -41.75), Vector2(18, -41.75), 0, 4, [], c)
	_box_room(g, 18, 30, -34, -46, 0.0, 4.0, {"w": [[6.0, 3.5]], "e": [[6.0, 4.0]]}, c)
	# 母親藏身的壁龕（東牆後被封住）
	_box_room(g, 30, 34, -38, -42, 0.0, 4.5, {}, Color("5a2a22"), ["w"])
	var mw = SecretWall.new()
	mw.name = "SecretWall_MotherNook"
	mw.open_flag = &"mother_chase_started"
	mw.size = Vector3(0.5, 4.0, 4.0)
	mw.color = c
	mw.position = Vector3(30, 0, -40)
	level.get_node("Secrets").add_child(mw)
	_marker("MotherChaseSpawn", Vector3(32, 0, -40), 90.0)
	_prop("Altar_Table", Vector3(25.5, 0, -44.9), Vector3(2.4, 1.0, 1.0), Color("cfc8b8"))
	_spawn(&"sacristy_many_hands", "many_hands", Vector3(24, 0, -41), 270.0)
	_pedestal("reliquary_hammer", Vector3(28.4, 0, -35.5))
	_item("item_umbilical_key", "umbilical_key", 1, Vector3(28.6, 0, -44.6))
	_inscription("inscription_sacristy", Vector3(23.0, 0, -45.6), 0.0)
	_note("note_magdalene", Vector3(19.5, 0, -45.0))
	var lock = PalmLock.new()
	lock.name = "PalmLock_Sacristy"
	lock.object_id = &"palm_lock_sacristy"
	lock.rewards = {"organ:many_hands_heart": 1, "blood_vial": 2}
	lock.position = Vector3(21.0, 0, -45.4)
	lock.rotation_degrees.y = 180
	level.get_node("Interactables").add_child(lock)
	_trigger(&"enter_sacristy", Vector3(12, 0, -40), 2.0, "多手人聖器室")
	_light("Light_Passage", Vector3(14, 3.0, -40), Color("c06050"), 0.6, 6.0)
	_light("Light_Sacristy", Vector3(24, 3.2, -40), Color("c06050"), 0.9, 10.0)

# 7. 禮拜堂大門、前廳、母親的禮拜堂（與 M7 相同）
func _build_chapel() -> void:
	var gate = BossGate.new()
	gate.name = "ChapelGate"
	gate.object_id = &"chapel_gate"
	gate.condition = {"has_item": "umbilical_key"}
	gate.locked_dialogue_id = "inscription_chapel_gate"
	gate.open_dialogue_id = "chapel_gate_open"
	gate.gate_size = Vector3(4.0, 4.0, 0.5)
	gate.position = Vector3(0, 0, -46)
	gate.prompt_text = "E：推開禮拜堂的門"
	level.get_node("Interactables").add_child(gate)
	var a := _area("Antechamber")
	_box_room(a, -4, 4, -46, -58, 0.0, 4.0, {"n": [[4.0, 4.0]]}, Color("6a5a50"), ["s"])
	_altar(&"altar_antechamber", Vector3(2.8, 0, -50))
	# 主線必遇的精英：連體修女背對入口站在禮拜堂門前唱詩。打倒她（或分裂後的兩位）之前，
	# 門口被一層肉膜封住，前廳的祭壇也不能用（不能在戰鬥中途回滿）。
	level.get_node("Altars/Altar_altar_antechamber").require_flag = &"conjoined_defeated"
	var nun = ConjoinedSpawn.new()
	nun.name = "Spawn_antechamber_conjoined"
	nun.spawn_id = &"antechamber_conjoined"
	nun.enemy_path = "res://content/enemies/conjoined_nun.tres"
	nun.defeat_flag = &"conjoined_defeated"
	nun.position = Vector3(0, 0, -54.5)
	nun.facing_degrees = 0.0
	level.get_node("Spawns").add_child(nun)
	var seal = SecretWall.new()
	seal.name = "FleshSeal_Chapel"
	seal.open_flag = &"conjoined_defeated"
	seal.size = Vector3(4.4, 4.0, 0.35)
	seal.color = Color("7a2a22")
	seal.position = Vector3(0, 0, -58)
	level.get_node("Secrets").add_child(seal)
	_trigger(&"enter_antechamber", Vector3(0, 0, -49), 2.5, "禮拜堂前廳", "antechamber_thought")
	_light("Light_Antechamber", Vector3(0, 3.2, -52), Color("e0b080"), 0.9, 8.0)
	_room("Chapel", Vector3(0, 0, -71), Vector2(22, 26), {"s": [0.0, 4.0]}, Color("5a4a44"))
	for i in 3:
		_prop("Pew_L%d" % i, Vector3(-6, 0, -62 - i * 3), Vector3(4.0, 0.9, 0.8), Color("3a2a22"))
		_prop("Pew_R%d" % i, Vector3(6, 0, -62 - i * 3), Vector3(4.0, 0.9, 0.8), Color("3a2a22"))
	_prop("WombChamber", Vector3(0, 0, -82), Vector3(5.0, 3.5, 1.5), Color("7a2a22"))
	_marker("BossSpawn", Vector3(0, 0, -74), 0.0)
	_trigger(&"chapel_arena", Vector3(0, 0, -62), 3.5, "母親的禮拜堂", "mother_intro", &"", &"chapel_open")
	var womb = DialogueInteractable.new()
	womb.name = "WombChamber_Ending"
	womb.object_id = &"womb_chamber"
	womb.kind = "inscription"
	womb.dialogue_id = "ending"
	womb.require_flag = &"boss_defeated"
	womb.prompt_text = "E：走近胎房"
	womb.interact_radius = 3.0
	womb.position = Vector3(0, 0, -80)
	level.get_node("Interactables").add_child(womb)
	_light("Light_Chapel_1", Vector3(-6, 4.0, -66), Color("c04030"), 1.1, 12.0)
	_light("Light_Chapel_2", Vector3(6, 4.0, -76), Color("c04030"), 1.1, 12.0)

# 8. 冷藏室（序章擴充）：藏書室南牆往下 2.5m。伊蓮的心臟被冰了七年的地方。
#    冰櫃排成兩道矮牆，隔出三條蛇行走道（看得過去、走不過去）；整個大廳是靜默區。
#    躺在地上的有些是真屍體、有些在裝死。最深處的冰櫃室：最初的縫線、生日信、祭壇。
const ICE := Color("b8c8d0")
const FROST_WALL := Color("8a98a4")

func _build_cold_storage() -> void:
	var y := -2.5
	var g := _area("ColdStorage")
	Kit.ramp(g, "Ramp", Vector3(-20, y, -22.5), Vector3(-20, 0, -29), 2.5)
	Kit.wall(g, "RampWallW", Vector2(-21.25, -29), Vector2(-21.25, -22.5), y, 1.0, [], FROST_WALL)
	Kit.wall(g, "RampWallE", Vector2(-18.75, -29), Vector2(-18.75, -22.5), y, 1.0, [], FROST_WALL)
	_box_room(g, -27, -13, -8, -22.5, y, 3.2, {"n": [[7.0, 2.5]], "e": [[2.25, 2.0]]}, FROST_WALL)
	# 冰櫃排成的矮牆（1.3m 高）：東側、西側輪流留缺口
	Kit.wall(g, "IceRowA", Vector2(-27, -18.5), Vector2(-16, -18.5), y, y + 1.3, [], ICE, 1.0)
	Kit.wall(g, "IceRowB", Vector2(-24, -13.5), Vector2(-13, -13.5), y, y + 1.3, [], ICE, 1.0)
	for i in 4:
		_gprop(g, "IceCradle_%d" % i, Vector3(-25.5 + i * 2.6, y, -9.0), Vector3(1.0, 0.7, 1.4), ICE)
	# 走道 1：裝死的縫屍者、真屍體、結冰的殘頁
	_spawn(&"cold_dormant_stitcher", "stitcher", Vector3(-16.5, y, -20.6), 90.0, "dormant")
	_spawn(&"cold_corpse_1", "stitcher", Vector3(-23.0, y, -20.4), 270.0, "corpse")
	_page(3, Vector3(-26.0, y, -21.6))
	# 走道 2：從冰櫃爬出來的未生者（裝死）、一具真屍體
	_spawn(&"cold_unborn_1", "unborn", Vector3(-18.0, y, -16.0), 0.0, "dormant")
	_spawn(&"cold_unborn_2", "unborn", Vector3(-22.5, y, -15.6), 180.0, "dormant")
	_spawn(&"cold_corpse_2", "stitcher", Vector3(-15.2, y, -16.2), 0.0, "corpse")
	# 走道 3：冰封的縫屍者守在冰櫃室門口
	_spawn(&"cold_frozen_stitcher", "frozen_stitcher", Vector3(-16.5, y, -10.5), 270.0)
	_spawn(&"cold_corpse_3", "unborn", Vector3(-21.0, y, -9.9), 90.0, "corpse")
	var sz = SilenceZone.new()
	sz.name = "Silence_ColdStorage"
	sz.half_extents = Vector2(7.0, 7.25)
	sz.position = Vector3(-20, y, -15.25)
	level.get_node("Triggers").add_child(sz)
	_inscription("inscription_cold_storage", Vector3(-17.8, 0, -29.6), 180.0)
	_trigger(&"enter_cold_storage", Vector3(-20, y, -21.8), 1.8, "冷藏室", "cold_storage_thought")
	_light("Light_Cold_1", Vector3(-20, 0.3, -20.5), Color("8098b0"), 0.5, 8.0)
	_light("Light_Cold_2", Vector3(-20, 0.3, -11.0), Color("8098b0"), 0.45, 8.0)
	# 伊蓮的冰櫃室（東側）
	var v := _area("IleneVault")
	_box_room(v, -13, -8, -8.5, -12.5, y, 3.0, {}, Color("d0d8dc"), ["w"])
	_gprop(v, "EmptyIceBox", Vector3(-10.4, y, -11.7), Vector3(1.2, 1.0, 0.8), Color("e4ecf0"))
	_item("item_first_suture", "first_suture", 1, Vector3(-9.0, y, -11.6), "伊格納要的東西。回到庭院的高台交給他")
	_note("note_ilene", Vector3(-10.4, y, -10.9))
	_item("item_cold_suture", "suture_kit", 2, Vector3(-8.8, y, -9.1))
	_altar(&"altar_cold_storage", Vector3(-12.0, y, -9.3))
	_light("Light_Vault", Vector3(-10.5, 0.2, -10.5), Color("d0e0f0"), 0.8, 6.0)

func _page(n: int, pos: Vector3) -> void:
	var p = ScripturePage.new()
	p.name = "ScripturePage_%d" % n
	p.object_id = StringName("scripture_page_%d" % n)
	p.page = n
	p.dialogue_id = "scripture_page_%d" % n
	p.position = pos
	level.get_node("Interactables").add_child(p)

func _scare(id: StringName, kind: String, pos: Vector3, radius: float, target: Vector3) -> void:
	var t = ScareTrigger.new()
	t.name = "Scare_%s" % id
	t.trigger_id = id
	t.kind = kind
	t.position = pos
	t.radius = radius
	t.target_offset = target
	level.get_node("Triggers").add_child(t)

# 9. 恐怖橋段（序章擴充）：一次性驚嚇（約每 5–6 分鐘一次）、其他區域的裝死敵人、聖典殘頁。
func _build_horror() -> void:
	# 縫合迴廊：背後傳來小孩的腳步聲，在你身後兩公尺停下
	_scare(&"scare_corridor_steps", "footsteps", Vector3(0, 0, -11.5), 1.6, Vector3(0, 0, 8))
	# 庭院：從高台跳下的缺口，遠處禮拜堂方向傳來嬰兒哭聲
	_scare(&"scare_courtyard_cry", "distant_cry", Vector3(2, 2.0, -29.0), 1.5, Vector3(-2, -2, -40))
	# 藏書室：燈熄滅，再亮起時有個高大的人影站在書架盡頭
	_scare(&"scare_archive_blackout", "blackout", Vector3(-13.5, 0, -36), 1.6, Vector3(-8, 0, -4.5))
	# 往聖器室的通道：一具屍體從天花板掉在你面前
	_scare(&"scare_passage_drop", "body_drop", Vector3(12.5, 0, -40), 1.4, Vector3(2.5, 0, 0))
	# 禮拜堂前廳：小女孩站在禮拜堂門口
	_scare(&"scare_antechamber_girl", "girl_glimpse", Vector3(0, 0, -48.5), 2.0, Vector3(0, 0, -8.5))
	# 冷藏室：走道盡頭的小女孩、慢慢轉過來的吊屍、燈滅後站在冰櫃室門口的人影
	_scare(&"scare_cold_girl", "girl_glimpse", Vector3(-19.0, -2.5, -20.5), 1.6, Vector3(4.5, 0, 0))
	_scare(&"scare_cold_hanging", "hanging_turn", Vector3(-16.0, -2.5, -16.0), 2.2, Vector3(-4.5, 3.2, 0))
	_scare(&"scare_cold_blackout", "blackout", Vector3(-25.5, -2.5, -11.0), 1.6, Vector3(11.0, 0, 0.75))
	# 庭院裡的裝死反足者與一具真屍體
	_spawn(&"courtyard_dormant_reverse", "reverse_legged", Vector3(-7.5, 0, -43.5), 90.0, "dormant")
	_spawn(&"courtyard_corpse", "stitcher", Vector3(6.5, 0, -43.0), 200.0, "corpse")
	# 聖典殘頁 6 頁（第 3 頁在冷藏室）
	_page(1, Vector3(8.5, 0, -15.0))
	_page(2, Vector3(0.9, 0, -39.3))
	_page(4, Vector3(-26.0, 0, -42.5))
	_page(5, Vector3(19.0, 0, -34.8))
	_page(6, Vector3(-11.5, -2, -56.5))
