class_name ImpactFeedback
extends Node
## 打擊回饋（打擊感）。由 PlaceholderBodyBuilder.build_creature 加到每個生物上，
## 只監聽 CombatComponent 的訊號，不需要 AI 或玩家控制器呼叫任何東西：
##   hit_received → 受擊閃白、擊退、噴血；牽涉玩家時再加頓幀與鏡頭震動
##   blocked      → 格擋火花、小幅擊退（破防時加重）
## 音效已由 AudioDirector 掛在同一組訊號上（hit_cut／hit_blunt／block…），這裡不重複播放。
##
## 強度依「這一下有多重」縮放：以部位 HP 損失相對於硬直門檻計算，斷肢與擊殺再加重。
## 頓幀只在玩家出手命中或玩家被打中時觸發（敵人互毆不會讓整個畫面停住）。

## 閃白持續時間（真實秒數）：前半全白、後半半白，逐格切換（PS1 的硬切感）。
const FLASH_TIME := 0.1
## 擊退：基本距離（公尺）、上限、在幾秒（戰鬥時間）內推完。
const KNOCK_BASE := 0.22
const KNOCK_MAX := 0.7
const KNOCK_TIME := 0.14
## 頓幀秒數（真實時間）。
const HITSTOP_LIGHT := 0.05
const HITSTOP_HEAVY := 0.09
const HITSTOP_SEVER := 0.14
const HITSTOP_KILL := 0.16
const HITSTOP_PLAYER_HURT := 0.07
const FLASH_SHADER := preload("res://art/ps1/ps1_flash.gdshader")

## 閃白疊加材質（全白／半白），所有生物共用。
static var _flash_mats := {}

var body: CharacterBody3D
var combat: CombatComponent
## 擊退抗性倍率：Boss 等巨大身體接近 0。
var knockback_scale := 1.0
## 最近一次回饋的內容（測試與除錯用）。
var last := {}

var _flash_left := 0.0
var _flash_meshes: Array[GeometryInstance3D] = []
var _knock_dir := Vector3.ZERO
var _knock_left := 0.0      # 尚未推完的距離
var _knock_time_left := 0.0

func _ready() -> void:
	body = get_parent() as CharacterBody3D
	combat = body.get_node_or_null("CombatComponent")
	if combat == null:
		return
	combat.hit_received.connect(_on_hit_received)
	combat.blocked.connect(_on_blocked)
	if body.get_node_or_null("BossPhaseComponent") != null:
		knockback_scale = 0.12

func is_player() -> bool:
	return combat != null and combat.faction == &"player"

# ---------- 訊號 ----------

func _on_hit_received(result: DamageResult, attacker: CombatComponent) -> void:
	if result == null or result.rejected:
		return
	var loss := 0.0
	var severed := false
	var part: StringName = &""
	for h in result.hits:
		loss += h.hp_loss
		severed = severed or h.severed
		if part == &"":
			part = h.part_id
	var weight := clampf(loss / maxf(combat.stagger_threshold, 1.0), 0.25, 1.5)
	var killed := combat.is_dead()
	var dir := _away_from(attacker)
	var dist := KNOCK_BASE * (0.6 + weight * 0.6)
	if severed:
		dist += 0.2
	if killed:
		dist += 0.15
	dist = minf(dist, KNOCK_MAX) * knockback_scale * (0.7 if is_player() else 1.0)
	knockback(dir, dist)
	flash(1.0)
	var at := _part_position(part)
	var n := int(6 + weight * 10.0) + (16 if severed else 0)
	HitBurst.spawn(_world(), at, dir, n, HitBurst.Kind.BLOOD)
	# 頓幀與鏡頭震動：只有牽涉玩家的命中
	var stop := 0.0
	var shake := 0.0
	if attacker != null and attacker.faction == &"player":
		stop = HITSTOP_LIGHT if weight < 1.0 else HITSTOP_HEAVY
		shake = 0.18 + weight * 0.12
		if severed:
			stop = HITSTOP_SEVER
			shake += 0.25
		if killed:
			stop = maxf(stop, HITSTOP_KILL)
			shake += 0.15
	elif is_player():
		stop = HITSTOP_PLAYER_HURT
		shake = 0.3 + weight * 0.15 + (0.3 if severed else 0.0)
	if stop > 0.0:
		TimeScale.hitstop(stop)
	if shake > 0.0:
		CameraShake.shake(_camera(), shake)
	last = {"kind": &"hit", "weight": weight, "knockback": dist, "hitstop": stop, "shake": shake,
		"severed": severed, "killed": killed, "particles": n}

func _on_blocked(attacker: CombatComponent, guard_broken: bool) -> void:
	var dir := _away_from(attacker)
	var dist := (0.32 if guard_broken else 0.1) * knockback_scale
	knockback(dir, dist)
	var at := body.global_position + Vector3.UP * 1.1 - dir * 0.3
	HitBurst.spawn(_world(), at, -dir, 14 if guard_broken else 8, HitBurst.Kind.SPARK)
	var involved := is_player() or (attacker != null and attacker.faction == &"player")
	var stop := 0.0
	var shake := 0.0
	if involved:
		stop = HITSTOP_HEAVY if guard_broken else 0.04
		shake = 0.35 if guard_broken else 0.12
		TimeScale.hitstop(stop)
		CameraShake.shake(_camera(), shake)
	last = {"kind": &"block", "knockback": dist, "hitstop": stop, "shake": shake, "guard_broken": guard_broken}

# ---------- 效果 ----------

## 受擊閃白：身上所有 PS1 材質的網格（包括武器）短暫疊上一層白（material_overlay）。
func flash(strength: float = 1.0) -> void:
	_clear_overlays()
	for n in body.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mat := gi.material_override as ShaderMaterial
		if mat != null and mat.shader == PS1Style.SHADER and gi.material_overlay == null:
			_flash_meshes.append(gi)
	_flash_left = FLASH_TIME * strength
	_apply_flash()

static func flash_material(level: float) -> ShaderMaterial:
	var key := 0 if level >= 1.0 else 1
	if not _flash_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLASH_SHADER
		m.set_shader_parameter("strength", 0.65 if key == 0 else 0.3)
		_flash_mats[key] = m
	var mat: ShaderMaterial = _flash_mats[key]
	# 跟著 PS1Style 目前的頂點吸附設定（解析度可能被畫面設定改過）
	mat.set_shader_parameter("snap_resolution", PS1Style.snap_resolution)
	mat.set_shader_parameter("jitter_enabled", PS1Style.jitter_enabled)
	return mat

func _clear_overlays() -> void:
	for gi in _flash_meshes:
		if is_instance_valid(gi) and gi.material_overlay != null and gi.material_overlay.get(&"shader") == FLASH_SHADER:
			gi.material_overlay = null
	_flash_meshes.clear()

func flash_level() -> float:
	if _flash_left <= 0.0:
		return 0.0
	return 1.0 if _flash_left > FLASH_TIME * 0.5 else 0.5

func _apply_flash() -> void:
	var v := flash_level()
	if v == 0.0:
		_clear_overlays()
		return
	var mat := flash_material(v)
	for gi in _flash_meshes:
		if is_instance_valid(gi) and body.is_ancestor_of(gi):
			gi.material_overlay = mat

## 擊退：在 KNOCK_TIME（戰鬥時間）內把身體往 dir 推 dist 公尺，先快後慢。
## 以 move_and_collide 位移，不改 velocity（AI 與玩家控制器每格會重設 velocity），撞牆就停。
func knockback(dir: Vector3, dist: float) -> void:
	dir.y = 0.0
	if dist <= 0.0 or dir.length() < 0.01:
		return
	_knock_dir = dir.normalized()
	_knock_left = dist
	_knock_time_left = KNOCK_TIME

func pending_knockback() -> float:
	return _knock_left

func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_apply_flash()

func _physics_process(delta: float) -> void:
	advance_knockback(TimeScale.scaled(delta))

func advance_knockback(dt: float) -> void:
	if _knock_left <= 0.0 or dt <= 0.0:
		return
	# 指數衰減：剩餘時間內推完，前幾格位移最大（「被打飛」的頓挫）
	var k := 1.0 - exp(-dt * 5.0 / KNOCK_TIME)
	_knock_time_left -= dt
	var step := _knock_left if _knock_time_left <= 0.0 else _knock_left * k
	_knock_left -= step
	if _knock_time_left <= 0.0 or _knock_left < 0.002:
		_knock_left = 0.0
	if body.is_inside_tree():
		var col := body.move_and_collide(_knock_dir * step)
		if col != null:
			_knock_left = 0.0
	else:
		body.position += _knock_dir * step

# ---------- 輔助 ----------

func _away_from(attacker: CombatComponent) -> Vector3:
	if attacker == null or attacker.body() == null:
		return body.global_transform.basis.z  # 沒有攻擊者：往後
	var d := body.global_position - attacker.body().global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else body.global_transform.basis.z

func _part_position(part: StringName) -> Vector3:
	var ctrl: DismembermentController = body.get_node_or_null("DismembermentController")
	if ctrl != null and part != &"":
		var hb := ctrl.hurtbox_for(part)
		if hb != null and hb.is_inside_tree():
			return hb.global_position
	return body.global_position + Vector3.UP * 1.0

func _world() -> Node:
	var p := body.get_parent()
	return p if p != null else body

func _camera() -> Camera3D:
	if not body.is_inside_tree():
		return null
	return body.get_viewport().get_camera_3d()
