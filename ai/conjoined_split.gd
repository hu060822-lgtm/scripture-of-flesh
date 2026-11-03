class_name ConjoinedSplit
extends Node
## 連體修女（主線精英）的分裂機制。EnemyFactory 在 special_behavior == &"conjoined" 時掛上。
##
## - 連接兩人的縫線（seam）被砍斷、或 HP 歸零 → 分裂成左右兩位修女（nun_sister_a／b）。
##   分裂後的身體延續連體時的傷：部位 HP 依比例換算、斷掉的手臂和頭還是斷的、出血照舊；
##   撕開的那一側（胸腔）多一道出血。整體 HP 依連體時剩下的比例。
## - 只要還有一隻內側手臂（arm_r_a、arm_l_b）抱著，縫線就被護在身前：受擊區域停用，
##   一般攻擊（自動選最近的部位）從正面或背後都打不到；戰術模式指定縫線仍然可以（要花 AP）。
## - 連體時頭不是致命部位：一顆頭被毀，那一半的手臂跟著失效；分裂時那一半直接倒下（屍體，不給經驗）。
##   兩顆頭都失效 → 連體修女死亡（不分裂，經驗較多）。
## - 存檔：分裂時記錄 GameState.killed[原生成點]、旗標 <生成點>_split；
##   兩位修女的生成點 id 是 <生成點>_a／_b（擊殺由 PrologueGame 記錄）。ConjoinedSpawn 讀檔後依此重建。

signal split_happened(sisters: Array)

const S := preload("res://art/ps1/ps1_style.gd")

const SISTER_PATHS := {
	&"a": "res://content/enemies/nun_sister_a.tres",
	&"b": "res://content/enemies/nun_sister_b.tres",
}
## 分裂後兩位修女離原本中心的距離（沿身體左右方向，公尺）。
const SPLIT_OFFSET := 0.5
## 撕開的那一側胸腔增加的出血速率（每秒）。
const TORN_BLEED := 0.6
## 分裂後每位修女至少保留的整體 HP。
const MIN_HP := 20.0
## 還沒發現玩家時，兩顆頭輪流低聲唱詩的間隔（秒）。
const HYMN_INTERVAL := 6.0

var split_done := false
var _executed := false
var _hymn_left := 1.5

func body() -> CharacterBody3D:
	return get_parent() as CharacterBody3D

func _anatomy() -> AnatomyComponent:
	return body().get_node("AnatomyComponent")

func _combat() -> CombatComponent:
	return body().get_node("CombatComponent")

func _ready() -> void:
	var st := _anatomy().state
	if st == null:
		_anatomy().setup()
		st = _anatomy().state
	st.part_severed.connect(func(_p, _ids): check())
	st.part_disabled.connect(func(_p, _r): check())
	st.capabilities_changed.connect(func(_c): update_guard())
	update_guard.call_deferred()

const INNER_ARMS := [&"arm_r_a", &"arm_l_b"]

## 縫線是否被內側手臂護住。
func seam_guarded() -> bool:
	var st := _anatomy().state
	for pid in INNER_ARMS:
		var p := st.get_part(pid)
		if p != null and p.is_functional():
			return true
	return false

## 依內側手臂的狀態開關縫線的受擊區域。
func update_guard() -> void:
	if not is_inside_tree() or split_done:
		return
	var ctrl := body().get_node_or_null("DismembermentController") as DismembermentController
	if ctrl == null:
		return
	var hb := ctrl.hurtbox_for(&"seam")
	if hb == null:
		return
	var seam := _anatomy().state.get_part(&"seam")
	if seam_guarded() or seam.severed:
		if hb.active:
			hb.deactivate()
	elif not hb.active:
		hb.activate()

func _physics_process(delta: float) -> void:
	if split_done or _combat().is_dead():
		return
	var ai := body().get_node_or_null("EnemyAI") as EnemyAI
	if ai == null or ai.state() in [&"chase", &"attack", &"defend", &"dismember_react"]:
		return
	_hymn_left -= TimeScale.scaled(delta)
	if _hymn_left <= 0.0:
		_hymn_left = HYMN_INTERVAL
		if body().is_inside_tree():
			AudioManager.play(&"twin_hymn", body().global_position + Vector3.UP * 1.8)

## 檢查分裂或死亡條件（部位變化時呼叫；測試也可直接呼叫）。
func check() -> void:
	if split_done or _combat().is_dead():
		return
	var st := _anatomy().state
	if not _head_alive(st, &"a") and not _head_alive(st, &"b"):
		_combat()._die("vital:heads")
		return
	var seam := st.get_part(&"seam")
	if seam != null and (seam.severed or not seam.is_functional()):
		split_done = true
		# 部位事件可能在傷害結算途中發出；等這一格結束再換掉身體
		call_deferred("split")

static func _head_alive(st: AnatomyState, which: StringName) -> bool:
	for pid in ["head_", "neck_"]:
		var p := st.get_part(StringName(pid + String(which)))
		if p == null or not p.is_functional():
			return false
	return true

## 分裂：生成兩位修女、移除連體的身體。回傳生成的修女（不含倒下的那一半）。
func split() -> Array:
	# check() 會延後呼叫一次；測試或劇本也可能直接呼叫。只執行一次。
	if _executed:
		return []
	_executed = true
	split_done = true
	var b := body()
	var parent := b.get_parent()
	var st := _anatomy().state
	var hp_ratio := clampf(_combat().pools.hp / maxf(1.0, _combat().pools.max_hp), 0.0, 1.0)
	var spawn_id := StringName(b.get_meta(&"spawn_id", ""))
	var target := _current_target()
	var alive := []
	for which in [&"a", &"b"]:
		var def: EnemyDefinition = load(SISTER_PATHS[which])
		var side := 1.0 if which == &"a" else -1.0
		var pos := b.global_transform * Vector3(side * SPLIT_OFFSET, 0, 0)
		var sis := create_sister(def, which, st, hp_ratio, spawn_id)
		# 先設定位置再加入場景（否則物理會把重疊的身體推開）
		sis.position = (parent as Node3D).to_local(pos) if parent is Node3D else pos
		sis.rotation.y = b.rotation.y + side * 0.6  # 兩人往外側轉開
		var dead_half := not _head_alive(st, which) or not _half_heart_alive(st, which)
		if parent != null:
			parent.add_child(sis)
			(sis.get_node("DismembermentController") as DismembermentController).sync_severed_visuals()
		if dead_half:
			# 頭已經被毀的那一半：撕開後直接倒下（屍體，不給經驗、不能摘器官）
			sis.set_meta(EnemySpawn.CORPSE_META, true)
			sis.set_meta(&"harvestable", [])
			sis.remove_meta(&"spawn_id")
			var c: CombatComponent = sis.get_node("CombatComponent")
			c.last_attacker = null
			if c.is_inside_tree():
				c._die("decor")
			if spawn_id != &"":
				GameState.killed[StringName("%s_%s" % [spawn_id, which])] = true
		else:
			alive.append(sis)
			if target != null and sis.is_inside_tree():
				var ai: EnemyAI = sis.get_node("EnemyAI")
				ai.runtime.target = target
				ai.runtime.last_known_position = target.body().global_position
				ai.runtime.time_since_seen = 0.0
				ai.runtime.alert = 1.0
				ai.force_state(&"chase")
	if spawn_id != &"":
		GameState.killed[spawn_id] = true
		GameState.set_flag(StringName("%s_split" % spawn_id))
	if b.is_inside_tree():
		AudioManager.play(&"twin_split", b.global_position + Vector3.UP * 1.3)
		_spawn_fx(parent, b.global_position)
	split_happened.emit(alive)
	# 這一格結束時移除連體的身體；在那之前先讓它不再參與戰鬥、碰撞與畫面
	b.visible = false
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.collision_layer = 0
	b.collision_mask = 0
	if b.is_in_group(CombatComponent.GROUP):
		b.remove_from_group(CombatComponent.GROUP)
	b.queue_free()
	return alive

static func _half_heart_alive(st: AnatomyState, which: StringName) -> bool:
	var h := st.get_part(StringName("heart_" + String(which)))
	return h == null or h.is_functional()

func _current_target() -> CombatComponent:
	var ai := body().get_node_or_null("EnemyAI") as EnemyAI
	if ai != null and ai.runtime.target != null and is_instance_valid(ai.runtime.target):
		return ai.runtime.target
	return _combat().last_attacker if _combat().last_attacker != null and is_instance_valid(_combat().last_attacker) else null

## 建立一位分裂後的修女（尚未加入場景）。conjoined_state 為 null 時是完整的（讀檔重建用）。
static func create_sister(def: EnemyDefinition, which: StringName, conjoined_state: AnatomyState, hp_ratio: float, spawn_id: StringName) -> CharacterBody3D:
	var id := StringName("%s_%s" % [spawn_id, which]) if spawn_id != &"" else StringName("nun_sister_" + String(which))
	var sis := EnemyFactory.create(def, id)
	if spawn_id != &"":
		sis.set_meta(&"spawn_id", id)
	var anatomy: AnatomyComponent = sis.get_node("AnatomyComponent")
	if conjoined_state != null:
		anatomy.setup(half_state(conjoined_state, def.anatomy_profile, which))
	var combat: CombatComponent = sis.get_node("CombatComponent")
	combat.max_hp = def.max_hp
	if conjoined_state != null:
		# CombatComponent._ready 會用 max_hp 建立資源池；之後再依比例扣掉
		var hp := maxf(MIN_HP, def.max_hp * hp_ratio)
		sis.ready.connect(func(): combat.pools.hp = minf(combat.pools.max_hp, hp), CONNECT_ONE_SHOT)
	return sis

## 把連體的身體狀態換算成一位修女的身體：部位 id 去掉 _a／_b，HP 依最大值比例換算。
## 腿：左修女拿 leg_l、右修女拿 leg_r；腹部承接共用骨盆的狀態。
static func half_state(conj: AnatomyState, half_profile: AnatomyProfile, which: StringName) -> AnatomyState:
	var src := conj.to_save()["parts"] as Dictionary
	var parts := {}
	for d in half_profile.parts:
		var key := String(d.id)
		var from := "%s_%s" % [key, which]
		if key == "abdomen":
			from = "pelvis"
		elif key.begins_with("leg_"):
			from = key
		if not src.has(from):
			continue
		var e: Dictionary = (src[from] as Dictionary).duplicate(true)
		var from_def := conj.get_part(StringName(from)).def
		e["hp"] = float(e["hp"]) / from_def.max_hp * d.max_hp
		parts[key] = e
	# 撕開的那一側：胸腔的斷面在流血
	if parts.has("chest") and not bool(parts["chest"].get("severed", false)):
		parts["chest"]["bleed"] = float(parts["chest"].get("bleed", 0.0)) + TORN_BLEED
	return AnatomyState.from_save(half_profile, {"parts": parts})

## 分裂的畫面：中間噴出乾涸紅的聲波環（兩聲尖叫）與一灘留在地上的血。
static func _spawn_fx(parent: Node, at: Vector3) -> void:
	if parent == null:
		return
	var w := ScreamWave.new()
	w.name = "SplitScream"
	parent.add_child(w)
	w.global_position = at + Vector3.UP * 1.3
	var pool := MeshInstance3D.new()
	pool.name = "SplitBloodPool"
	var m := CylinderMesh.new()
	m.top_radius = 0.9
	m.bottom_radius = 0.9
	m.height = 0.02
	m.radial_segments = 9
	m.rings = 1
	pool.mesh = m
	pool.material_override = S.material(S.DRIED_RED.darkened(0.25), "flesh")
	parent.add_child(pool)
	pool.global_position = at + Vector3.UP * 0.015
	pool.scale = Vector3(0.2, 1, 0.2)
	var tw := pool.create_tween()
	tw.tween_property(pool, "scale", Vector3(1.0, 1, 0.8), 1.4).set_ease(Tween.EASE_OUT)
