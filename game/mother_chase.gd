class_name MotherChase
extends Node
## 母親的中途登場（序章提案 E，追逐戰強化版）：拿到臍帶鑰匙的那一刻，行走的母親撞破聖器室的東牆追出來。
## - 東側樓梯口被長出來的肉封死，玩家要穿過通道與庭院，繞到西側樓梯逃上高台（祭壇所在）才算逃掉。
## - 她的速度跟距離連動：離遠了比你快、貼近時比你稍慢，所以會一直黏在背後幾公尺。
## - 靠近時先舉手預備（WINDUP）再撲過來（LUNGE），翻滾的無敵時間躲得掉；撲空會撞地愣住。
## - 第一次被抓：被拖回去，狂按 E 掙脫，最後被扯掉一條手臂，她繼續追。第二次被抓：被拖進牆裡死掉。
## - 她身後拖著一條臍帶（沿著走過的路），經過的燈一盞盞熄滅，路上長出肉塊。庭院的敵人嚇得縮在原地。
## 只發生一次（旗標 mother_chase_done，隨祭壇存檔）；死掉會從最後的祭壇重來，追逐也會重新上演。
## 這是演出用的分身：沒有 BossPhase，不影響真正的 Boss 戰；EnemyAI 停用，由這個節點直接驅動移動。

signal started
signal ended(reason: StringName)  # &"escaped"、&"timeout"
## 被抓住（count 為第幾次）；lethal = 這次會死。
signal caught(count: int, lethal: bool)
## 掙脫（被扯掉一條手臂後放開）。
signal released(part: StringName)
signal windup_started
## 重踏／撞牆等衝擊（strength 0–1，鏡頭震動用）。
signal stomped(strength: float)

enum Phase { IDLE, BURST, CHASE, WINDUP, LUNGE, RECOVER, HOLD, RETREAT }

const MOTHER := "res://content/enemies/walking_mother.tres"
const START_FLAG := &"mother_chase_started"
const DONE_FLAG := &"mother_chase_done"
const TRIGGER_ITEM := "umbilical_key"
const HUM := "res://audio/music/stems/hum.ogg"

## 速度跟距離連動（玩家 4.2）：距離 NEAR_GAP 以內用 SPEED_NEAR，FAR_GAP 以外用 SPEED_FAR。
## 兩者相等的平衡點約在 3 公尺（在撲擊距離內）：直線跑也甩不掉，她每隔一陣子就會撲一次，要翻滾才躲得掉。
const SPEED_NEAR := 3.8
const SPEED_FAR := 5.6
const NEAR_GAP := 2.0
const FAR_GAP := 6.0
## 撲抓：進入此距離開始預備，預備秒數、撲擊秒數與速度、撲中判定距離（中心到中心，含兩人的碰撞半徑）。
const LUNGE_RANGE := 3.4
const WINDUP_SECONDS := 0.5
const LUNGE_SECONDS := 0.35
const LUNGE_SPEED := 10.0
const GRAB_RANGE := 1.9
const LUNGE_COOLDOWN := 1.2
## 翻滾判定窗：預備的最後這麼多秒到撲擊結束之間，只要玩家在翻滾（整個翻滾動作，不只無敵幀）就算閃過。
## 太早翻（一聽到尖叫就翻）會在她撲出前就滾完，照樣被抓。
const DODGE_WINDOW := 0.3
## 撲空後撞地愣住、掙脫後被推開的秒數。
const MISS_RECOVER := 0.9
const RELEASE_RECOVER := 1.4
## 抓住：最多拖幾秒、要按幾下 E 才掙脫、拖行速度；第幾次被抓會死、致死的拖行秒數。
const HOLD_SECONDS := 3.0
const STRUGGLE_PRESSES := 6
const DRAG_SPEED := 1.2
const LETHAL_CATCHES := 2
const LETHAL_HOLD := 1.6
const MAX_SECONDS := 60.0
## 破牆後愣住的秒數（給玩家反應時間）。
const STARTUP_SECONDS := 1.2
## 被臍帶沿原路拖回去的速度。
const RETREAT_SPEED := 7.0
const GRAVITY := 18.0
## 每走這麼遠記一個足跡點（臍帶與肉塊沿著足跡，不會穿牆）。
const TRAIL_STEP := 0.6
const MAX_FLESH := 70
## 燈：她的水平距離小於這個值就閃爍熄滅（大燈的半徑另計）。
const CANDLE_RADIUS := 2.2
const BIG_LIGHT_RADIUS := 4.0
const LIGHT_FLICKER := 0.5
## 這些大燈在她經過時只會暗到這個比例（不讓整區全黑，看不見路）。
const BIG_LIGHTS := {&"Light_Sacristy": 0.0, &"Light_Passage": 0.0, &"Light_Courtyard": 0.35}
## 音樂：距離小於 HUSH_GAP 時音樂全斷（離開要大於 HUSH_EXIT，避免忽開忽關）。
const HUSH_GAP := 2.2
const HUSH_EXIT := 2.9
const NEAR_MUSIC_GAP := 5.0
## 庭院與聖器室範圍：這裡面的敵人在追逐中縮在原地。
const COWER_ZONE := AABB(Vector3(-10.5, -1.0, -47.0), Vector3(45.0, 4.5, 22.0))

## 帶路點（ChaseGuide 的箭頭依序指向）：通道出口 → 西側樓梯口 → 高台（樓梯頂）。東梯被肉封住，所以不走那邊。
const GUIDE := [
	[Vector3(10.0, 0.0, -40.0), "穿過通道"],
	[Vector3(-4.5, 0.0, -36.8), "西側樓梯"],
	[Vector3(-4.5, 2.0, -29.6), "逃上高台"],
]
## 高台祭壇上的光柱：讓終點從庭院與通道都看得到。
const BEAM_ALTAR := "Altars/Altar_altar_courtyard"
const BEAM_COLOR := Color("f2e6c4")

@export var spawn_marker: NodePath = NodePath("Markers/MotherChaseSpawn")
@export var barrier_marker: NodePath = NodePath("Markers/ChaseFleshBarrier")
## 安全區：庭院南側的高台（y 高於 escape_min_y，z 大於 escape_min_z）。
@export var escape_min_y: float = 1.4
@export var escape_min_z: float = -30.8

var level: Node3D
var player: CharacterBody3D
var mother: CharacterBody3D
var active := false
var phase: int = Phase.IDLE
var elapsed := 0.0
var catches := 0
var presses := 0
var trail: Array[Vector3] = []
var flesh: Array[Node3D] = []
var barrier: StaticBody3D
var cord: MeshInstance3D
var hum: AudioStreamPlayer3D
var cowering: Array = []
var lights := {}  # light instance id -> {light, energy, radius, floor, t}（t：-1 亮著、>=0 熄滅中、INF 已熄）
var end_reason: StringName = &""
var beam: Node3D
var _beam_mat: StandardMaterial3D
var _beam_light: OmniLight3D
var _beam_flash := -1.0
var _phase_t := 0.0
var _lunge_cd := 0.0
var _lunge_dir := Vector3.ZERO
var _home := Vector3.ZERO
var _nav := AiNavigator.new()
var _step_left := 0.0
var _breath_cd := 0.0
var _flesh_sfx_cd := 0.0
var _hushed := false
var _restore_t := -1.0
var _rng := RandomNumberGenerator.new()

func setup(lvl: Node3D, pl: CharacterBody3D) -> void:
	level = lvl
	player = pl
	_rng.seed = 732

func is_done() -> bool:
	return GameState.has_flag(DONE_FLAG)

func _physics_process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.HOLD and event.is_action_pressed(&"interact"):
		struggle()
		get_viewport().set_input_as_handled()

## 推進（測試直接呼叫）。
func advance(delta: float) -> void:
	if delta <= 0.0 or level == null or player == null or not is_instance_valid(player):
		return
	_advance_lights(delta)
	_advance_flesh(delta)
	_advance_beam(delta)
	if phase == Phase.RETREAT:
		_advance_retreat(delta)
		_update_cord()
		return
	if not active:
		if not is_done() and _has_key():
			start()
		return
	var pc: CombatComponent = player.get_node("CombatComponent")
	if pc.is_dead():
		return
	elapsed += delta
	_phase_t += delta
	_lunge_cd = maxf(0.0, _lunge_cd - delta)
	_breath_cd = maxf(0.0, _breath_cd - delta)
	_flesh_sfx_cd = maxf(0.0, _flesh_sfx_cd - delta)
	if phase != Phase.HOLD:
		if is_safe(player.global_position):
			finish(&"escaped")
			return
		if elapsed >= MAX_SECONDS:
			finish(&"timeout")
			return
	var g := gap()
	match phase:
		Phase.BURST:
			_move(Vector3.ZERO, delta)
			if _phase_t >= STARTUP_SECONDS:
				_set_phase(Phase.CHASE)
		Phase.CHASE:
			if g <= LUNGE_RANGE and _lunge_cd <= 0.0:
				_set_phase(Phase.WINDUP)
				windup_started.emit()
				_cue(&"mother_shriek")
			else:
				_move(_chase_dir() * speed_for_gap(g), delta)
				_tick_steps(delta, speed_for_gap(g))
		Phase.WINDUP:
			if _phase_t >= WINDUP_SECONDS - DODGE_WINDOW and pc.action == CombatComponent.Action.DODGE:
				_dodged = true
			# 舉手預備：邊追邊舉手（不會停下來給你拉開距離）
			_move(_chase_dir() * speed_for_gap(g) * 0.9, delta)
			if _phase_t >= WINDUP_SECONDS:
				_lunge_dir = _flat(player.global_position - mother.global_position).normalized()
				if _lunge_dir == Vector3.ZERO:
					_lunge_dir = -mother.global_transform.basis.z
				_set_phase(Phase.LUNGE)
		Phase.LUNGE:
			_move(_lunge_dir * LUNGE_SPEED, delta)
			if pc.action == CombatComponent.Action.DODGE or pc.is_invulnerable():
				_dodged = true
			if g <= GRAB_RANGE and not _dodged:
				_grab()
			elif _phase_t >= LUNGE_SECONDS:
				# 撲空：撞地愣住
				_lunge_cd = LUNGE_COOLDOWN
				_set_phase(Phase.RECOVER)
				_cue(&"mother_stomp")
				stomped.emit(0.8)
		Phase.RECOVER:
			_move(Vector3.ZERO, delta)
			var wait := RELEASE_RECOVER if catches > 0 and _phase_t_is_release else MISS_RECOVER
			if _phase_t >= wait:
				_phase_t_is_release = false
				_set_phase(Phase.CHASE)
		Phase.HOLD:
			_advance_hold(delta, pc)
	if phase != Phase.HOLD:
		_record_trail()
	_update_cord()
	_update_hum()

var _phase_t_is_release := false
var _dodged := false

func _has_key() -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	return data != null and data.inventory.count(TRIGGER_ITEM) > 0

## 高台安全區（逃脫終點）。
func is_safe(pos: Vector3) -> bool:
	return pos.y >= escape_min_y and pos.z >= escape_min_z and pos.x > -10.0 and pos.x < 10.0

## 與玩家的水平距離。
func gap() -> float:
	if mother == null or not is_instance_valid(mother):
		return INF
	return _flat(player.global_position - mother.global_position).length()

static func speed_for_gap(g: float) -> float:
	return lerpf(SPEED_NEAR, SPEED_FAR, clampf((g - NEAR_GAP) / (FAR_GAP - NEAR_GAP), 0.0, 1.0))

## 0–1 的壓迫感（畫面效果用）：越近越強，預備撲擊與被抓時最強。
func dread() -> float:
	if not active or mother == null:
		return 0.0
	if phase == Phase.HOLD:
		return 1.0
	var d := clampf((9.0 - gap()) / 7.0, 0.0, 1.0)
	if phase in [Phase.WINDUP, Phase.LUNGE]:
		d = maxf(d, 0.9)
	if phase == Phase.BURST:
		d = maxf(d, 0.6)
	return d

## 音樂狀態（AudioDirector 用）：沒在追逐時回傳空字串。
func music_state() -> StringName:
	if not active or mother == null:
		return &""
	var g := gap()
	if phase in [Phase.WINDUP, Phase.LUNGE, Phase.HOLD] or g < HUSH_GAP or (_hushed and g < HUSH_EXIT):
		_hushed = true
		return &"chase_hush"
	_hushed = false
	return &"chase_near" if g < NEAR_MUSIC_GAP else &"chase"

func start() -> void:
	active = true
	elapsed = 0.0
	catches = 0
	end_reason = &""
	GameState.set_flag(START_FLAG)  # SecretWall（聖器室東牆）看這個旗標打開
	var m := level.get_node_or_null(spawn_marker) as Node3D
	_home = m.global_position if m != null else player.global_position + Vector3(0, 0, 4)
	mother = EnemyFactory.create(load(MOTHER), &"walking_mother_apparition")
	mother.set_meta(&"apparition", true)
	mother.position = _home
	mother.rotation.y = m.rotation.y if m != null else PI
	level.add_child(mother)
	var ai := mother.get_node_or_null("EnemyAI")
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	trail = [_home]
	_build_cord()
	_build_hum()
	_build_barrier()
	_build_beam()
	_collect_lights()
	_cower_enemies(true)
	_set_phase(Phase.BURST)
	_cue(&"mother_wall_burst", _home)
	_cue(&"mother_shriek", _home)
	stomped.emit(1.0)
	started.emit()

func _set_phase(p: int) -> void:
	phase = p
	_phase_t = 0.0
	if p == Phase.WINDUP:
		_dodged = false
	var clip: StringName = {
		Phase.BURST: &"lunge_windup", Phase.CHASE: &"chase_run", Phase.WINDUP: &"lunge_windup",
		Phase.LUNGE: &"lunge", Phase.RECOVER: &"kneel", Phase.HOLD: &"grab_hold", Phase.RETREAT: &"stagger",
	}.get(p, &"")
	_anim(clip)

func _anim(clip: StringName) -> void:
	if mother == null or not is_instance_valid(mother):
		return
	var a := mother.get_node_or_null("CreatureAnimator")
	if a != null and a.has_method(&"play_override"):
		var lib_ok := true
		if clip != &"" and a.get("tree") != null:
			var player_node: AnimationMixer = a.tree
			lib_ok = player_node.has_animation(clip)
		a.play_override(clip if lib_ok else &"")

# ---------- 移動 ----------

func _chase_dir() -> Vector3:
	_nav.tick(get_physics_process_delta_time())
	var wp := _nav.next_point(mother, player.global_position)
	var dir := _flat(wp - mother.global_position)
	if dir.length() < 0.05:
		dir = _flat(player.global_position - mother.global_position)
	return dir.normalized()

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _move(v: Vector3, delta: float) -> void:
	var vy := mother.velocity.y - GRAVITY * delta if not mother.is_on_floor() else 0.0
	mother.velocity = Vector3(v.x, vy, v.z)
	if v.length() > 0.01:
		mother.rotation.y = atan2(-v.x, -v.z)
	if not mother.is_inside_tree():
		return
	if Engine.is_in_physics_frame():
		mother.move_and_slide()
	else:
		# 測試直接呼叫 advance() 時不在物理影格裡，move_and_slide 用的物理 delta 不對：改用位移量
		var col := mother.move_and_collide(Vector3(v.x, 0.0, v.z) * delta)
		if col != null:
			mother.move_and_collide(col.get_remainder().slide(col.get_normal()))

## 重踏聲與鏡頭震動：跑越快踏得越密，越近震得越大。
func _tick_steps(delta: float, speed: float) -> void:
	_step_left -= delta * speed
	if _step_left > 0.0:
		return
	_step_left = 1.7
	_cue(&"mother_stomp")
	stomped.emit(clampf(1.0 - gap() / 12.0, 0.1, 0.7))
	if gap() < 3.5 and _breath_cd <= 0.0:
		_breath_cd = 1.3
		_cue(&"mother_breath")

func _record_trail() -> void:
	if mother == null:
		return
	var p := mother.global_position
	if trail.is_empty() or trail[-1].distance_to(p) >= TRAIL_STEP:
		trail.append(p)
		if trail.size() % 2 == 0:
			_spawn_flesh(p)

# ---------- 抓住 ----------

func _grab() -> void:
	catches += 1
	presses = 0
	_set_phase(Phase.HOLD)
	# 抓在手上時兩個身體重疊：互相忽略碰撞，不然物理會把她往後推開
	mother.add_collision_exception_with(player)
	player.add_collision_exception_with(mother)
	var ctrl := player.get_node_or_null("PlayerController")
	if ctrl != null:
		ctrl.input_enabled = false
	var pc: CombatComponent = player.get_node("CombatComponent")
	pc.set_blocking(false)
	_cue(&"body_drag")
	stomped.emit(0.9)
	caught.emit(catches, is_lethal())

## 這次被抓會不會死：第 LETHAL_CATCHES 次，或已經沒有手臂可以扯。
func is_lethal() -> bool:
	return catches >= LETHAL_CATCHES or _arm_to_take() == &""

## 被抓時按 E（掙扎）。
func struggle() -> void:
	if phase != Phase.HOLD or is_lethal():
		return
	presses += 1
	stomped.emit(0.25)

func _advance_hold(delta: float, pc: CombatComponent) -> void:
	# 她沿著足跡往回拖（走過的足跡點會被收回，不會繞圈）
	var target_pt := trail[-1] if not trail.is_empty() else _home
	var back := _flat(target_pt - mother.global_position)
	while back.length() < 0.3 and trail.size() > 1:
		trail.pop_back()
		target_pt = trail[-1]
		back = _flat(target_pt - mother.global_position)
	if back.length() > 0.05:
		var face := mother.rotation.y
		_move(back.normalized() * DRAG_SPEED, delta)
		mother.rotation.y = face  # 拖行時一直面向玩家
	var fwd := -mother.global_transform.basis.z
	var target := mother.global_position + _flat(fwd).normalized() * 1.2
	target.y = player.global_position.y
	player.global_position = target
	player.velocity = Vector3.ZERO
	if int(_phase_t * 2.0) != int((_phase_t - delta) * 2.0):
		_cue(&"body_drag")
	if is_lethal():
		if _phase_t >= LETHAL_HOLD:
			pc._die("mother_chase")
		return
	if presses >= STRUGGLE_PRESSES or _phase_t >= HOLD_SECONDS:
		_release(pc)

func _arm_to_take() -> StringName:
	var pc: CombatComponent = player.get_node("CombatComponent")
	var st := pc.anatomy.state
	var eq: EquipmentComponent = player.get_node_or_null("EquipmentComponent")
	var weapon_arm := eq.weapon_part() if eq != null else &""
	var choice := &""
	for arm in [&"arm_l", &"arm_r"]:
		var p := st.get_part(arm)
		if p == null or p.severed:
			continue
		if choice == &"" or arm != weapon_arm:
			choice = arm
	return choice

## 扯下一條手臂（優先沒拿武器的那隻）然後放開，把玩家甩向前方。
func _release(pc: CombatComponent) -> void:
	var arm := _arm_to_take()
	if arm != &"":
		pc.anatomy.state.sever_part(arm)
	mother.remove_collision_exception_with(player)
	player.remove_collision_exception_with(mother)
	var ctrl := player.get_node_or_null("PlayerController")
	if ctrl != null:
		ctrl.input_enabled = true
	var away := _flat(player.global_position - mother.global_position).normalized()
	if away != Vector3.ZERO:
		player.move_and_collide(away * 1.4)
	_lunge_cd = LUNGE_COOLDOWN + 0.6
	_phase_t_is_release = true
	_set_phase(Phase.RECOVER)
	stomped.emit(0.7)
	released.emit(arm)

# ---------- 結束 ----------

func finish(reason: StringName) -> void:
	if not active:
		return
	active = false
	end_reason = reason
	GameState.set_flag(DONE_FLAG)
	var ctrl := player.get_node_or_null("PlayerController")
	if ctrl != null:
		ctrl.input_enabled = true
	_cower_enemies(false)
	_beam_flash = 0.0
	_set_phase(Phase.RETREAT)
	_cue(&"cord_snap", mother)
	ended.emit(reason)

## 被臍帶沿原路拖回牆後（足跡倒著走，不會穿牆），到家後消失；肉牆枯萎，燈慢慢亮回來。
func _advance_retreat(delta: float) -> void:
	if mother == null or not is_instance_valid(mother):
		_end_retreat()
		return
	var target := trail[-1] if not trail.is_empty() else _home
	var to := _flat(target - mother.global_position)
	var step := RETREAT_SPEED * delta
	while to.length() <= step and trail.size() > 1:
		trail.pop_back()
		target = trail[-1]
		to = _flat(target - mother.global_position)
	if to.length() > 0.2:
		var face := mother.rotation.y
		mother.global_position += to.normalized() * minf(step, to.length())
		mother.rotation.y = face  # 背對著被拖走
	elif trail.size() <= 1:
		_end_retreat()

func _end_retreat() -> void:
	phase = Phase.IDLE
	if mother != null and is_instance_valid(mother):
		mother.queue_free()
	mother = null
	if cord != null and is_instance_valid(cord):
		cord.queue_free()
	cord = null
	hum = null
	if barrier != null and is_instance_valid(barrier):
		barrier.set_meta(&"wither", 0.0)
	_restore_t = 0.0

# ---------- 帶路 ----------

## 目前要去的帶路點索引（0 通道出口、1 西側樓梯口、2 高台）。
func guide_index() -> int:
	var p := player.global_position
	if p.x > 9.0:
		return 0
	if p.y > 0.6 or (p.x < -2.5 and p.x > -6.5 and p.z > -37.5):
		return 2  # 已經在西梯上（或高台上）
	return 1

func guide_target() -> Vector3:
	return GUIDE[guide_index()][0]

func guide_label() -> String:
	return GUIDE[guide_index()][1]

## 光柱：半透明、不受光照的圓柱＋暖光，追逐中脈動；逃脫時亮一下再淡出。
func _build_beam() -> void:
	var altar := level.get_node_or_null(BEAM_ALTAR) as Node3D
	if altar == null:
		return
	beam = Node3D.new()
	beam.name = "ChaseSafeBeam"
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.9
	cyl.height = 14.0
	cyl.radial_segments = 8
	cyl.rings = 1
	mi.mesh = cyl
	mi.position = Vector3(0, 7.0, 0)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(BEAM_COLOR, 0.25)
	mi.material_override = _beam_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.add_child(mi)
	_beam_light = OmniLight3D.new()
	_beam_light.light_color = BEAM_COLOR
	_beam_light.light_energy = 1.2
	_beam_light.omni_range = 7.0
	_beam_light.position = Vector3(0, 1.5, 0)
	beam.add_child(_beam_light)
	beam.position = altar.global_position
	level.add_child(beam)

func _advance_beam(delta: float) -> void:
	if beam == null or not is_instance_valid(beam):
		return
	if _beam_flash >= 0.0:
		_beam_flash += delta
		var k := clampf(1.0 - (_beam_flash - 0.3) / 2.2, 0.0, 1.0)
		var flash := 1.0 if _beam_flash < 0.3 else k
		_beam_mat.albedo_color.a = 0.6 * flash
		_beam_light.light_energy = 3.0 * flash
		if _beam_flash > 2.5:
			beam.queue_free()
			beam = null
		return
	var pulse := 0.5 + 0.5 * sin(elapsed * 4.0)
	_beam_mat.albedo_color.a = 0.18 + 0.14 * pulse
	_beam_light.light_energy = 0.9 + 0.6 * pulse

# ---------- 臍帶、哼唱、肉牆、肉塊 ----------

func _build_cord() -> void:
	cord = MeshInstance3D.new()
	cord.name = "ChaseCord"
	cord.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6a2a26")
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cord.material_override = mat
	level.add_child(cord)

## 臍帶：從牆後的家沿著足跡連到她的背上（兩片交叉的帶子，從斜上方看起來像一條管子）。
func _update_cord() -> void:
	if cord == null or not is_instance_valid(cord) or mother == null or not is_instance_valid(mother):
		return
	var im := cord.mesh as ImmediateMesh
	im.clear_surfaces()
	var pts: Array[Vector3] = []
	for i in trail.size():
		var p := trail[i]
		pts.append(p + Vector3(0, 0.12 + 0.05 * sin(i * 1.7), 0))
	pts.append(mother.global_position + Vector3(0, 1.5, 0) + mother.global_transform.basis.z * 0.3)
	if pts.size() < 2:
		return
	for pass_i in 2:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in pts.size():
			var a := pts[maxi(0, i - 1)]
			var b := pts[mini(pts.size() - 1, i + 1)]
			var along := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector3.FORWARD
			var w := 0.07 + 0.03 * sin(i * 0.9 + elapsed * 4.0)
			var side := along.cross(Vector3.UP).normalized() * w if pass_i == 0 else Vector3.UP * w
			if side == Vector3.ZERO:
				side = Vector3.RIGHT * w
			im.surface_add_vertex(pts[i] - side)
			im.surface_add_vertex(pts[i] + side)
		im.surface_end()

func _build_hum() -> void:
	if not ResourceLoader.exists(HUM):
		return
	var s = (load(HUM) as AudioStream).duplicate()
	if "loop" in s:
		s.loop = true
	hum = AudioStreamPlayer3D.new()
	hum.name = "Hum"
	hum.stream = s
	hum.bus = &"Voice"
	hum.unit_size = 3.0
	hum.max_distance = 30.0
	hum.position = Vector3(0, 2.0, 0)
	mother.add_child(hum)
	if hum.is_inside_tree():
		hum.play()

## 越近哼得越大聲；被抓住時哼聲壓低，只剩呼吸。
func _update_hum() -> void:
	if hum == null or not is_instance_valid(hum):
		return
	hum.volume_db = -14.0 if phase == Phase.HOLD else lerpf(-6.0, 2.0, dread())
	hum.pitch_scale = 1.0 if phase == Phase.CHASE else 0.94

func _build_barrier() -> void:
	var m := level.get_node_or_null(barrier_marker) as Node3D
	if m == null:
		return
	barrier = StaticBody3D.new()
	barrier.name = "ChaseFleshBarrier"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 3.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 1.6, 0)
	barrier.add_child(shape)
	for i in 22:
		var lump := _flesh_mesh(_rng.randf_range(0.6, 1.3))
		lump.position = Vector3(_rng.randf_range(-1.7, 1.7), _rng.randf_range(0.2, 3.8), _rng.randf_range(-0.9, 0.5))
		barrier.add_child(lump)
	barrier.position = m.global_position
	barrier.scale = Vector3.ONE * 0.05
	barrier.set_meta(&"grow", 0.0)
	level.add_child(barrier)

func _flesh_mesh(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 6
	sm.rings = 3
	sm.radius = size * 0.5
	sm.height = size * _rng.randf_range(0.6, 1.0)
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	var tone := _rng.randf()
	mat.albedo_color = Color("7a2a24").lerp(Color("c9a0a0"), tone * 0.6)
	mat.roughness = 0.5
	mi.material_override = mat
	return mi

func _spawn_flesh(at: Vector3) -> void:
	if flesh.size() >= MAX_FLESH:
		return
	var lump := _flesh_mesh(_rng.randf_range(0.25, 0.6))
	var side := Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)) * 0.9
	lump.position = at + side + Vector3(0, 0.05, 0)
	lump.scale = Vector3.ONE * 0.01
	lump.set_meta(&"grow", 0.0)
	level.add_child(lump)
	flesh.append(lump)
	if _flesh_sfx_cd <= 0.0:
		_flesh_sfx_cd = 0.9
		_cue(&"flesh_grow", lump)

func _advance_flesh(delta: float) -> void:
	for lump in flesh:
		if is_instance_valid(lump) and lump.has_meta(&"grow"):
			var t := minf(1.0, float(lump.get_meta(&"grow")) + delta / 0.6)
			lump.set_meta(&"grow", t)
			lump.scale = Vector3(1.0, 0.45, 1.0) * maxf(0.01, ease(t, 0.4))
			if t >= 1.0:
				lump.remove_meta(&"grow")
	if barrier != null and is_instance_valid(barrier):
		if barrier.has_meta(&"grow"):
			var t := minf(1.0, float(barrier.get_meta(&"grow")) + delta / 1.5)
			barrier.set_meta(&"grow", t)
			barrier.scale = Vector3.ONE * maxf(0.05, ease(t, 0.5))
			if t >= 1.0:
				barrier.remove_meta(&"grow")
		elif barrier.has_meta(&"wither"):
			var t := float(barrier.get_meta(&"wither")) + delta / 2.0
			barrier.set_meta(&"wither", t)
			barrier.scale = Vector3(1.0, maxf(0.02, 1.0 - t), 1.0)
			if t >= 1.0:
				barrier.queue_free()
				barrier = null

# ---------- 燈 ----------

func _collect_lights() -> void:
	lights.clear()
	var root := level.get_node_or_null("Lights")
	if root == null:
		return
	for l in root.get_children():
		if not l is Light3D:
			continue
		var n := String(l.name)
		if n.begins_with("ChaseCandle_"):
			lights[l.get_instance_id()] = {"light": l, "energy": l.light_energy, "radius": CANDLE_RADIUS, "floor": 0.0, "t": -1.0}
		elif BIG_LIGHTS.has(StringName(n)):
			lights[l.get_instance_id()] = {"light": l, "energy": l.light_energy, "radius": BIG_LIGHT_RADIUS, "floor": BIG_LIGHTS[StringName(n)], "t": -1.0}

## 她經過時：閃爍 LIGHT_FLICKER 秒後熄滅。追逐結束後 3 秒內慢慢亮回來。
func _advance_lights(delta: float) -> void:
	if _restore_t >= 0.0:
		_restore_t = minf(1.0, _restore_t + delta / 3.0)
		for info in lights.values():
			if is_instance_valid(info.light):
				var cur: float = info.energy * (info.floor if info.t != -1.0 else 1.0)
				info.light.light_energy = lerpf(cur, info.energy, _restore_t)
		if _restore_t >= 1.0:
			_restore_t = -1.0
			lights.clear()
		return
	if not active or mother == null or not is_instance_valid(mother):
		return
	for info in lights.values():
		var l: Light3D = info.light
		if not is_instance_valid(l) or info.t == INF:
			continue
		if info.t < 0.0:
			if _flat(l.global_position - mother.global_position).length() < info.radius:
				info.t = 0.0
		else:
			info.t += delta
			if info.t >= LIGHT_FLICKER:
				info.t = INF
				l.light_energy = info.energy * info.floor
				_cue(&"light_die", l)
			else:
				l.light_energy = info.energy * (1.0 if _rng.randf() < 0.45 else 0.08)

func dark_lights() -> int:
	var n := 0
	for info in lights.values():
		if info.t == INF:
			n += 1
	return n

# ---------- 庭院的敵人 ----------

func _cower_enemies(on: bool) -> void:
	if on:
		cowering.clear()
		for e in level.find_children("*", "CharacterBody3D", true, false):
			if e == mother or e == player or e.has_meta(&"apparition"):
				continue
			var ai: Node = e.get_node_or_null("EnemyAI")
			var c: CombatComponent = e.get_node_or_null("CombatComponent")
			if ai == null or c == null or c.is_dead() or e.has_node("BossPhase"):
				continue
			if not COWER_ZONE.has_point(e.global_position):
				continue
			ai.process_mode = Node.PROCESS_MODE_DISABLED
			e.velocity = Vector3.ZERO
			var a: Node = e.get_node_or_null("CreatureAnimator")
			if a != null:
				a.play_override(&"block")
			cowering.append(e)
	else:
		for e in cowering:
			if not is_instance_valid(e):
				continue
			var ai: Node = e.get_node_or_null("EnemyAI")
			if ai != null:
				ai.process_mode = Node.PROCESS_MODE_INHERIT
			var a: Node = e.get_node_or_null("CreatureAnimator")
			if a != null:
				a.play_override(&"")
		cowering.clear()

# ---------- 聲音 ----------

func _cue(id: StringName, at: Variant = null) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	if at == null:
		at = mother
	if at is Node and not is_instance_valid(at):
		at = null
	am.play(id, at)
