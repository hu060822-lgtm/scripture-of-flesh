class_name CreatureAnimator
extends Node
## 生物的動畫驅動：建立 AnimationTree（狀態機 → TimeScale），依戰鬥狀態、移動速度與身體能力切換動作。
## 玩家與敵人共用，不需要 AI 或玩家控制器呼叫任何東西：
##   CombatComponent.action_changed → 攻擊前搖／判定／收招、閃避、僵直、死亡
##   CombatComponent.hit_received   → 受擊
##   AnatomyState.part_severed      → 斷肢反應
##   DismembermentController.animation_set_changed → 步態（雙腿／單腿跛行／爬行）
##   CharacterBody3D.velocity       → 待機或行走，播放速度隨移動速度變化
##
## 時序同步：攻擊片段長度為 1 秒，進入每個階段時把 TimeScale 設為 1／該階段秒數，
## 所以出手姿勢與 CombatComponent 的命中判定落在同一刻（資料改了動畫自動跟著改）。
## 以 TimeScale（戰術減速／暫停）推進，並以 12fps 逐格更新，保留 PS1 的低幀數頓挫感。
## 動畫只寫骨骼「旋轉」與 Skeleton 節點的位移／旋轉，不碰骨骼縮放，所以斷肢後縮為零的骨骼不受影響。

const FPS := 12.0
const LOCO_STATES := [&"idle", &"walk", &"limp", &"crawl", &"crawl_idle", &"block"]
const ONE_SHOT_STATES := [&"hit", &"stagger", &"sever", &"dodge", &"death"]
const ATTACK_STATES := [&"attack_windup", &"attack_active", &"attack_recovery"]
## 達到此水平速度才播放行走（公尺／秒）。
const WALK_THRESHOLD := 0.25
## 行走片段的參考速度：以此速度移動時播放倍率為 1。
const WALK_REFERENCE_SPEED := 2.6
const HIT_TIME := 0.3
const SEVER_TIME := 0.6

var body: CharacterBody3D
var combat: CombatComponent
var anatomy: AnatomyComponent
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var animation_set := {"arms": AnimationSet.ARMS_TWO, "legs": AnimationSet.LEGS_TWO}
## 目前的狀態與實際播放的片段名稱（測試與除錯用）。
var current_state: StringName = &""
var current_clip: StringName = &""
var playback_scale := 1.0
## 劇本演出（Boss 跪伏等）暫時接管：非空時固定播放此片段。
var override_clip: StringName = &""

var _acc := 0.0
var _hit_timer := 0.0
var _sever_timer := 0.0
var _phase_duration := 1.0
var _attack_style: StringName = &""
var _attack_arm: StringName = &""
var _nodes := {}  # state -> AnimationNodeAnimation

func _ready() -> void:
	body = get_parent() as CharacterBody3D
	combat = body.get_node_or_null("CombatComponent")
	anatomy = body.get_node_or_null("AnatomyComponent")
	if anatomy.state == null:
		anatomy.setup()
	_build_tree()
	if combat != null:
		combat.action_changed.connect(_on_action_changed)
		combat.hit_received.connect(func(_r, _a): _hit_timer = HIT_TIME)
	anatomy.state.part_severed.connect(func(_top, _ids): _sever_timer = SEVER_TIME)
	var ctrl: DismembermentController = body.get_node_or_null("DismembermentController")
	if ctrl != null:
		if not ctrl.animation_set.is_empty():
			animation_set = ctrl.animation_set
		ctrl.animation_set_changed.connect(func(s): animation_set = s)
	_update_state()
	tree.advance(0.0)

func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.add_animation_library(&"", CreatureAnimationLibrary.for_profile(anatomy.profile))
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var sm := AnimationNodeStateMachine.new()
	for st in LOCO_STATES + ONE_SHOT_STATES + ATTACK_STATES:
		var n := AnimationNodeAnimation.new()
		n.animation = st if not (st in ATTACK_STATES) else &"idle"
		sm.add_node(st, n)
		_nodes[st] = n
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"state", sm)
	bt.add_node(&"speed", AnimationNodeTimeScale.new())
	bt.connect_node(&"speed", 0, &"state")
	bt.connect_node(&"output", 0, &"speed")
	tree.tree_root = bt
	add_child(tree)
	tree.root_node = tree.get_path_to(body)
	tree.active = true
	playback = tree.get("parameters/state/playback")

func _process(delta: float) -> void:
	_acc += TimeScale.scaled(delta)
	var step := 1.0 / FPS
	if _acc < step:
		return
	var dt := _acc
	_acc = 0.0
	tick(dt)

## 推進 dt 秒（已套用戰鬥時間倍率）。測試可直接呼叫。
func tick(dt: float) -> void:
	_hit_timer = maxf(0.0, _hit_timer - dt)
	_sever_timer = maxf(0.0, _sever_timer - dt)
	_update_state()
	tree.set("parameters/speed/scale", playback_scale)
	tree.advance(dt)

# ---------- 狀態選擇 ----------

func _on_action_changed(action: int) -> void:
	match action:
		CombatComponent.Action.WINDUP:
			_choose_attack_clips(combat.current_attack)
			_phase_duration = combat.current_attack.windup
		CombatComponent.Action.ACTIVE:
			_phase_duration = combat.current_attack.active if combat.current_attack != null else 0.1
		CombatComponent.Action.RECOVERY:
			_phase_duration = combat.current_attack.recovery if combat.current_attack != null else 0.3
		CombatComponent.Action.DODGE:
			_phase_duration = combat.dodge_duration
		CombatComponent.Action.STAGGER:
			_phase_duration = combat.stagger_duration
	# 階段切換時立刻換片段（不等下一格），讓出手姿勢與命中判定同一刻開始
	_update_state(true)
	tree.set("parameters/speed/scale", playback_scale)
	tree.advance(0.0)

func _choose_attack_clips(attack: AttackDefinition) -> void:
	_attack_style = AttackStyles.style_for(attack)
	_attack_arm = &""
	if AttackStyles.is_arm_style(_attack_style):
		_attack_arm = striking_arm(attack)
		if _attack_arm == &"":
			_attack_style = &"strike"
	if not CreatureAnimationLibrary.ensure_attack(anatomy.profile, _attack_style, _attack_arm):
		_attack_style = &"strike"
		_attack_arm = &""
		CreatureAnimationLibrary.ensure_attack(anatomy.profile, _attack_style, _attack_arm)

## 出手的手臂：武器攻擊用持武器的手；徒手攻擊優先用右手，右手斷了就用剩下的手。
func striking_arm(attack: AttackDefinition) -> StringName:
	var eq: EquipmentComponent = body.get_node_or_null("EquipmentComponent")
	if attack != null and attack.requires_weapon and eq != null and eq.weapon_part() != &"":
		return eq.weapon_part()
	var best: StringName = &""
	var best_x := INF
	for d in anatomy.profile.parts:
		if not (d.functions.has("arm") and d.functions.has("grip")):
			continue
		var st := anatomy.state.get_part(d.id)
		if st == null or not st.is_functional():
			continue
		var x: float = PlaceholderBodyBuilder.part_frames(anatomy.profile)[d.id]["center"].x
		if x < best_x:
			best_x = x
			best = d.id
	return best

func _update_state(force: bool = false) -> void:
	var st: StringName
	var clip: StringName
	playback_scale = 1.0
	var action: int = combat.action if combat != null else CombatComponent.Action.IDLE
	if override_clip != &"":
		st = &"idle"
		clip = override_clip
	elif action == CombatComponent.Action.DEAD:
		st = &"death"
	elif action in [CombatComponent.Action.WINDUP, CombatComponent.Action.ACTIVE, CombatComponent.Action.RECOVERY]:
		var phase: String = {CombatComponent.Action.WINDUP: "windup", CombatComponent.Action.ACTIVE: "active",
			CombatComponent.Action.RECOVERY: "recovery"}[action]
		st = StringName("attack_" + phase)
		clip = CreatureAnimationLibrary.attack_clip_name(_attack_style, _attack_arm, phase)
		playback_scale = 1.0 / maxf(_phase_duration, 0.01)
	elif _sever_timer > 0.0:
		st = &"sever"
	elif action == CombatComponent.Action.STAGGER:
		st = &"stagger"
		playback_scale = 1.0 / maxf(_phase_duration, 0.01)
	elif action == CombatComponent.Action.DODGE:
		st = &"dodge"
		playback_scale = 1.0 / maxf(_phase_duration, 0.01)
	elif _hit_timer > 0.0:
		st = &"hit"
	else:
		st = _locomotion_state()
		if st in [&"walk", &"limp", &"crawl"]:
			playback_scale = clampf(horizontal_speed() / _reference_speed(), 0.5, 2.0)
	if clip == &"":
		clip = st
	var changed := st != current_state or clip != current_clip
	if changed or (force and st in ATTACK_STATES):
		var node: AnimationNodeAnimation = _nodes[st]
		node.animation = clip
		current_state = st
		current_clip = clip
		playback.start(st, true)

func _locomotion_state() -> StringName:
	var moving := horizontal_speed() > WALK_THRESHOLD
	if animation_set.get("legs") == AnimationSet.LEGS_CRAWL:
		return &"crawl" if moving else &"crawl_idle"
	if combat != null and combat.blocking:
		return &"block"
	if not moving:
		return &"idle"
	return &"limp" if animation_set.get("legs") == AnimationSet.LEGS_ONE else &"walk"

func _reference_speed() -> float:
	var m := 1.0
	if combat != null:
		var loco := combat.caps().count("locomotion")
		m = 1.0 if loco >= 2 else (0.45 if loco == 1 else 0.15)
	return WALK_REFERENCE_SPEED * m

func horizontal_speed() -> float:
	var v := body.velocity
	v.y = 0.0
	return v.length()

## 劇本演出用：固定播放某片段（傳空字串恢復正常）。
func play_override(clip: StringName) -> void:
	override_clip = clip
	_update_state(true)
	tree.advance(0.0)
