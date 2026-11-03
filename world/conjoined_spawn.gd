class_name ConjoinedSpawn
extends EnemySpawn
## 連體修女的生成點（主線精英，禮拜堂前廳）。
## - 還沒被打倒：生成連體修女。
## - 已經分裂（旗標 <spawn_id>_split）：只生成還沒被擊殺的那幾位修女（讀檔、死亡重生後）。
## - 打倒（連體時直接殺死，或分裂後兩位都死了）→ 設定 defeat_flag，前廳通往禮拜堂的肉膜打開。

## 打倒後設定的旗標（SecretWall.open_flag 讀這個）。
@export var defeat_flag: StringName = &"conjoined_defeated"

func split_flag() -> StringName:
	return StringName("%s_split" % spawn_id)

func sister_id(which: StringName) -> StringName:
	return StringName("%s_%s" % [spawn_id, which])

func is_defeated() -> bool:
	if not GameState.killed.has(spawn_id):
		return false
	if not GameState.has_flag(split_flag()):
		return true
	return GameState.killed.has(sister_id(&"a")) and GameState.killed.has(sister_id(&"b"))

func should_spawn() -> bool:
	return enemy_path != "" and not is_defeated()

func spawn(parent: Node) -> CharacterBody3D:
	if is_defeated():
		_mark_defeated()
		return null
	if not GameState.killed.has(spawn_id):
		return super.spawn(parent)
	# 已經分裂過：重建還活著的修女（完整的身體，延續的傷不存檔）
	var first: CharacterBody3D = null
	for which in [&"a", &"b"]:
		if GameState.killed.has(sister_id(which)):
			continue
		var def: EnemyDefinition = load(ConjoinedSplit.SISTER_PATHS[which])
		var sis := ConjoinedSplit.create_sister(def, which, null, 1.0, spawn_id)
		var side := 1.0 if which == &"a" else -1.0
		sis.position = global_position + global_transform.basis.x * side * ConjoinedSplit.SPLIT_OFFSET
		sis.rotation.y = deg_to_rad(facing_degrees)
		parent.add_child(sis)
		if first == null:
			first = sis
	return first

func _physics_process(_delta: float) -> void:
	if defeat_flag != &"" and not GameState.has_flag(defeat_flag) and is_defeated():
		_mark_defeated()

func _mark_defeated() -> void:
	if defeat_flag != &"" and not GameState.has_flag(defeat_flag):
		GameState.set_flag(defeat_flag)
