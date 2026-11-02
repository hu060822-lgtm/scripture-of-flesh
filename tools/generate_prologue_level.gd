extends SceneTree
## 一次性產生序章灰盒關卡 scenes/prologue/prologue_level.tscn（之後以 Godot 編輯器直接編輯 .tscn 為準）。
## 執行：godot --headless --path . -s tools/generate_prologue_level.gd
## 注意：重新執行會覆蓋同名檔案（在編輯器中做的修改會遺失）。
##
## 區域（由南往北）：
##   白色產房 → 縫合迴廊 → 反足者庭院 ─┬─ 西：觀察者藏書室
##                                      ├─ 東：多手人聖器室（臍帶鑰匙）
##                                      └─ 北：禮拜堂大門（需臍帶鑰匙）→ 前廳 → 母親的禮拜堂
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
	level = Node3D.new()
	level.name = "PrologueLevel"
	geo = _group("Geometry")
	for n in ["Markers", "Altars", "Interactables", "Spawns", "Triggers", "Lights"]:
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

func _spawn(id: StringName, enemy: String, pos: Vector3, facing: float = 0.0) -> void:
	var s = EnemySpawn.new()
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

func _item(id: String, item: String, count: int, pos: Vector3) -> void:
	var it = ItemPickup.new()
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

func _build() -> void:
	# 1. 白色產房（起點）：z 6 .. -6
	_room("DeliveryRoom", Vector3(0, 0, 0), Vector2(12, 12), {"n": [0.0, 3.0]}, Color("efece6"))
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

	# 2. 縫合迴廊：z -6 .. -26
	_room("SutureCorridor", Vector3(0, 0, -16), Vector2(6, 20), {"s": [0.0, 3.0], "n": [0.0, 3.0]}, Color("b8b0a0"))
	_prop("Gurney_1", Vector3(-2, 0, -12), Vector3(0.8, 0.8, 1.8), Color("6b625a"))
	_prop("Gurney_2", Vector3(2, 0, -19), Vector3(0.8, 0.8, 1.8), Color("6b625a"))
	_spawn(&"corridor_stitcher_1", "stitcher", Vector3(0.8, 0, -14), 180.0)
	_spawn(&"corridor_stitcher_2", "stitcher", Vector3(-1.2, 0, -22), 180.0)
	_inscription("inscription_corridor", Vector3(-2.5, 0, -9), 90.0)
	_note("note_stitcher", Vector3(-2.2, 0, -14.2))
	_trigger(&"enter_corridor", Vector3(0, 0, -8), 2.5, "縫合迴廊", "corridor_thought")
	_light("Light_Corridor_1", Vector3(0, 3.2, -10), Color("d0a070"), 0.9, 7.0)
	_light("Light_Corridor_2", Vector3(0, 3.2, -21), Color("d0a070"), 0.9, 7.0)

	# 3. 反足者庭院：z -26 .. -46，x -10 .. 10
	_room("Courtyard", Vector3(0, 0, -36), Vector2(20, 20), {"s": [0.0, 3.0], "n": [0.0, 4.0], "w": [0.0, 3.0], "e": [0.0, 3.0]}, Color("9a9284"))
	_prop("Obelisk", Vector3(0, 0, -36), Vector3(1.2, 3.0, 1.2), Color("5a524a"))
	_prop("Pillar_1", Vector3(-6, 0, -31), Vector3(0.8, 4.0, 0.8), Color("8a8070"))
	_prop("Pillar_2", Vector3(6, 0, -31), Vector3(0.8, 4.0, 0.8), Color("8a8070"))
	_prop("Pillar_3", Vector3(-6, 0, -41), Vector3(0.8, 4.0, 0.8), Color("8a8070"))
	_prop("Pillar_4", Vector3(6, 0, -41), Vector3(0.8, 4.0, 0.8), Color("8a8070"))
	_spawn(&"courtyard_reverse_1", "reverse_legged", Vector3(-4, 0, -38), 160.0)
	_spawn(&"courtyard_reverse_2", "reverse_legged", Vector3(5, 0, -43), 200.0)
	_spawn(&"courtyard_stitcher", "stitcher", Vector3(3, 0, -33), 180.0)
	_pedestal("bone_saw_cleaver", Vector3(-8, 0, -28.5))
	_inscription("inscription_courtyard", Vector3(0, 0, -34.2), 0.0)
	_altar(&"altar_courtyard", Vector3(8, 0, -28.5))
	var priest = DialogueInteractable.new()
	priest.name = "NPC_Ignatius"
	priest.object_id = &"npc_ignatius"
	priest.kind = "npc"
	priest.dialogue_id = "ignatius_talk"
	priest.repeat_dialogue_id = "ignatius_dead"
	priest.first_done_flag = &"met_ignatius"
	priest.prompt_text = "E：靠近垂死的司祭"
	priest.position = Vector3(8.6, 0, -31.2)
	priest.rotation_degrees.y = -120
	level.get_node("Interactables").add_child(priest)
	_item("item_courtyard_suture", "suture_kit", 1, Vector3(-8.5, 0, -44.5))
	_trigger(&"enter_courtyard", Vector3(0, 0, -28), 3.0, "反足者庭院")
	_light("Light_Courtyard", Vector3(0, 5.0, -36), Color("a0a8c0"), 1.0, 16.0)

	# 4. 觀察者藏書室（西）：x -10 .. -24
	_room("Archive", Vector3(-17, 0, -36), Vector2(14, 14), {"e": [0.0, 3.0]}, Color("7a6a58"))
	for i in 4:
		_prop("Shelf_%d" % i, Vector3(-21 + i * 2.6, 0, -41), Vector3(1.8, 3.0, 0.6), Color("4a3a2c"))
	_prop("Lectern", Vector3(-17, 0, -31.5), Vector3(0.8, 1.1, 0.6), Color("4a3a2c"))
	_spawn(&"archive_watcher_1", "faceless_watcher", Vector3(-19, 0, -38), 90.0)
	_spawn(&"archive_watcher_2", "faceless_watcher", Vector3(-14, 0, -33), 90.0)
	_pedestal("anatomist_rapier", Vector3(-22.5, 0, -31))
	_inscription("inscription_archive", Vector3(-17, 0, -30.6), 180.0)
	_note("note_stripping", Vector3(-12.5, 0, -38.5))
	_item("item_archive_suture", "suture_kit", 2, Vector3(-22.5, 0, -42))
	_trigger(&"enter_archive", Vector3(-11.5, 0, -36), 2.5, "觀察者藏書室")
	_light("Light_Archive", Vector3(-17, 3.2, -36), Color("80a070"), 0.8, 10.0)

	# 5. 多手人聖器室（東）：x 10 .. 24
	_room("Sacristy", Vector3(17, 0, -36), Vector2(14, 14), {"w": [0.0, 3.0]}, Color("8a6a5a"))
	_prop("ReliquaryCabinet", Vector3(17, 0, -42), Vector3(4.0, 2.4, 0.8), Color("5a1a14"))
	_prop("Altar_Table", Vector3(21, 0, -36), Vector3(1.2, 1.0, 2.4), Color("cfc8b8"))
	_spawn(&"sacristy_many_hands", "many_hands", Vector3(17, 0, -37), 270.0)
	_pedestal("reliquary_hammer", Vector3(22, 0, -31))
	_item("item_umbilical_key", "umbilical_key", 1, Vector3(21, 0, -36))
	_inscription("inscription_sacristy", Vector3(17, 0, -41.4), 0.0)
	_note("note_magdalene", Vector3(13.2, 0, -41.5))
	_trigger(&"enter_sacristy", Vector3(11.5, 0, -36), 2.5, "多手人聖器室")
	_light("Light_Sacristy", Vector3(17, 3.2, -36), Color("c06050"), 0.9, 10.0)

	# 6. 禮拜堂大門與前廳：z -46 .. -58
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
	_room("Antechamber", Vector3(0, 0, -52), Vector2(8, 12), {"s": [0.0, 4.0], "n": [0.0, 4.0]}, Color("6a5a50"))
	_altar(&"altar_antechamber", Vector3(2.8, 0, -50))
	_trigger(&"enter_antechamber", Vector3(0, 0, -49), 2.5, "禮拜堂前廳", "antechamber_thought")
	_light("Light_Antechamber", Vector3(0, 3.2, -52), Color("e0b080"), 0.9, 8.0)

	# 7. 母親的禮拜堂：z -58 .. -84
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
