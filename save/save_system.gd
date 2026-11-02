class_name SaveSystem
extends RefCounted
## 版本化存檔。只存 ID 與數值（不存節點或資源路徑），新增內容不會破壞舊存檔。
## 讀檔時依版本號套用遷移函式（MIGRATIONS）。

const VERSION := 1
const DEFAULT_PATH := "user://save_0.json"

## 版本遷移：from_version -> Callable(data: Dictionary) -> Dictionary
## 範例：未來 VERSION 改為 2 時，加入 {1: _migrate_1_to_2}。
const MIGRATIONS := {}

static func collect(player: Node3D) -> Dictionary:
	var combat: CombatComponent = player.get_node("CombatComponent")
	var ctrl: PlayerController = player.get_node("PlayerController")
	var d := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game": GameState.to_save(),
		"player": {
			"anatomy": combat.anatomy.state.to_save(),
			"pools": combat.pools.to_save(),
			"weapons": ctrl.weapons.map(func(w): return String(w.id)),
			"weapon_index": ctrl.weapon_index,
		},
	}
	var prog: ProgressionComponent = player.get_node_or_null("ProgressionComponent")
	if prog != null:
		d["player"]["progression"] = prog.to_save()
	var mut: MutationComponent = player.get_node_or_null("MutationComponent")
	if mut != null:
		d["player"]["mutation"] = mut.to_save()
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data != null:
		d["player"]["data"] = data.to_save()
	return d

static func write(data: Dictionary, path: String = DEFAULT_PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	return OK

static func read(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	return migrate(parsed)

static func exists(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)

static func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 1))
	while v < VERSION and MIGRATIONS.has(v):
		data = MIGRATIONS[v].call(data)
		v += 1
	data["version"] = v
	return data

static func save_game(player: Node3D, path: String = DEFAULT_PATH) -> Error:
	return write(collect(player), path)

## 把存檔套用到一個剛建立的玩家（加入場景前或後皆可，需已 _ready）。
static func apply(player: Node3D, data: Dictionary) -> void:
	GameState.load_save(data.get("game", {}))
	var pd: Dictionary = data.get("player", {})
	var combat: CombatComponent = player.get_node("CombatComponent")
	var ctrl: PlayerController = player.get_node("PlayerController")
	var prog: ProgressionComponent = player.get_node_or_null("ProgressionComponent")
	if prog != null and pd.has("progression"):
		var cls_id := String(pd["progression"].get("class", ""))
		if cls_id != "" and ResourceLoader.exists("res://content/classes/%s.tres" % cls_id):
			prog.class_definition = load("res://content/classes/%s.tres" % cls_id)
		prog.load_save(pd["progression"])
	var mut: MutationComponent = player.get_node_or_null("MutationComponent")
	if mut != null and pd.has("mutation"):
		mut.load_save(pd["mutation"])
	var pdata: PlayerData = player.get_node_or_null("PlayerData")
	if pdata != null and pd.has("data"):
		pdata.load_save(pd["data"])
	if pd.has("anatomy"):
		var profile := combat.anatomy.profile
		var new_state := AnatomyState.from_save(profile, pd["anatomy"], OrganRegistry.lookup_for(profile))
		_replace_anatomy(player, new_state)
	if pd.has("pools"):
		combat.pools.load_save(pd["pools"])
	var ws: Array[WeaponDefinition] = []
	for wid in pd.get("weapons", []):
		var path := "res://content/weapons/%s.tres" % wid
		if ResourceLoader.exists(path):
			ws.append(load(path))
	ctrl.weapons = ws
	var current := ctrl.equipment.weapon_part()
	if current != &"":
		ctrl.equipment.unequip(current).queue_free()
	ctrl.weapon_index = -1
	var idx := int(pd.get("weapon_index", 0))
	if not ws.is_empty():
		ctrl.switch_weapon(clampi(idx, 0, ws.size() - 1))

## 以讀檔的解剖狀態重建玩家（斷肢需要表現層同步，因此重放斷離事件）。
static func _replace_anatomy(player: Node3D, loaded: AnatomyState) -> void:
	var anatomy: AnatomyComponent = player.get_node("AnatomyComponent")
	var st := anatomy.state
	# 先套用器官（部位定義），再套用數值，最後重放斷離讓模型、碰撞同步。
	for pid in loaded.organs:
		var organ := OrganRegistry.get_organ(loaded.organs[pid])
		if organ != null:
			st.replace_part_definition(pid, TransplantService.build_definition(organ, st.get_part(pid).def), organ.id)
	for pid in loaded.part_ids():
		var src := loaded.get_part(pid)
		var dst := st.get_part(pid)
		if dst == null or src.severed:
			continue
		dst.hp = src.hp
		dst.injuries = src.injuries.duplicate()
		dst.bleed_rate = src.bleed_rate
		dst.mutation = src.mutation
		dst.own_disabled = src.own_disabled
	for pid in loaded.part_ids():
		var src := loaded.get_part(pid)
		if src.severed and not st.get_part(pid).severed:
			var parent := src.def.parent_id
			if parent == &"" or not loaded.get_part(parent).severed:
				st.sever_part(pid)
	st.tick(0.0001)  # 觸發依賴與能力刷新
