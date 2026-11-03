class_name AudioDirector
extends Node
## 把遊戲事件轉成聲音：監聽場景樹中新加入的節點，自動接上它們的 signal。
## 不需要修改戰鬥、AI、Boss、UI 的程式碼（模型與 AI 由其他工作負責，這裡只「聽」）。
## 也負責決定音樂狀態：menu／explore／tension／combat／boss_1／boss_2／death／ending_*。

const T := DamageTypes.Type
## 特定攻擊用專屬的聲音（其餘用 attack_swing）。
const ATTACK_CUES := {
	&"birth_scream": &"boss_birth_cry",
}
## EnemyAI 狀態 → 警戒程度（1 緊張、2 戰鬥）。
const AI_ALERT := {
	&"detect": 1,
	&"chase": 2, &"attack": 2, &"defend": 2, &"dodge": 2,
	&"retreat": 2, &"dismember_react": 2, &"special": 2,
}
## 沒有敵人在戰鬥後，戰鬥音樂再維持幾秒（避免忽開忽關）。
const COMBAT_HOLD := 4.0
const TENSION_HOLD := 2.0
const STRIDE := {&"player": 1.4}
## 區域（AreaTrigger.trigger_id）→ 環境音。玩家所在位置最近的那個區域觸發點決定環境音
## （觸發點只觸發一次，所以不用 triggered 訊號，往回走也會換回來）。【暫代】近似：之後關卡有房間體積再改。
const AREA_AMBIENCE := {
	&"enter_delivery": &"ward",
	&"enter_corridor": &"corridor",
	&"enter_courtyard": &"courtyard",
	&"enter_archive": &"library",
	&"enter_sacristy": &"sacristy",
	&"enter_antechamber": &"chapel",
	&"chapel_arena": &"chapel",
	&"enter_cold_storage": &"corridor",
}
const START_AMBIENCE := &"ward"
const DEFAULT_STRIDE := 1.6

var manager: Node
var _creatures := {}  # instance id -> {c, state, last_pos, walked}（不用物件當鍵：Godot 4.3 迭代含已釋放物件鍵的字典會卡住）
var _alert := {}        # instance id -> {ai, level}
var _bosses: Array = []
var _blocked_frame := {}  # CombatComponent instance id -> physics frame
var _menus: Array = []
var _areas: Array = []
var _ending := &""
var _combat_hold := 0.0
var _tension_hold := 0.0

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)

## 清除音樂狀態的計時（換場景、測試用）。
func reset() -> void:
	if _psyche() != null:
		_psyche().reset()
	_alert.clear()
	_combat_hold = 0.0
	_tension_hold = 0.0
	_ending = &""

func _scan(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_scan(c)

func _on_node_added(n: Node) -> void:
	if n.has_meta(&"_audio_hooked"):
		return
	if n is CombatComponent or n is EnemyAI or n is BossPhaseComponent or n is PlayerData \
			or n is StitchingAltar or n is ItemPickup or n is WeaponPedestal or n is BossGate \
			or n is TransplantScreen or n is DialogueBox or n is BaseButton or n is MainMenu \
			or n is PrologueGame or n is AreaTrigger:
		n.set_meta(&"_audio_hooked", true)
		if n.is_node_ready():
			_hook(n)
		else:
			n.ready.connect(_hook.bind(n), CONNECT_ONE_SHOT)

func _hook(n: Node) -> void:
	if n is CombatComponent:
		_hook_combat(n)
	elif n is EnemyAI:
		var ai := n as EnemyAI
		ai.state_changed.connect(func(_o, s): _on_ai_state(ai, s))
	elif n is BossPhaseComponent:
		var bp := n as BossPhaseComponent
		_bosses.append(bp)
		bp.phase_changed.connect(func(_p): _cue(&"boss_kneel", bp.body()))
		bp.summoned.connect(func(add): _cue(&"boss_summon", add))
		bp.cords_severed.connect(func(): _cue(&"cord_snap", bp.body()))
		bp.defeated.connect(func(): _cue(&"boss_defeated"))
	elif n is PlayerData:
		var pd := n as PlayerData
		var b := pd.get_parent() as Node3D
		pd.suture_started.connect(func(_p, _d): _cue(&"suture_start", b))
		pd.suture_finished.connect(func(_p): _cue(&"stitch_done", b))
		pd.suture_interrupted.connect(func(): _cue(&"suture_break", b))
	elif n is StitchingAltar:
		(n as StitchingAltar).rested.connect(func(_p): _cue(&"altar_rest"))
	elif n is ItemPickup or n is WeaponPedestal:
		(n as Interactable).interacted.connect(func(_p): _cue(&"pickup"))
	elif n is BossGate:
		var g := n as BossGate
		g.opened.connect(func(): _cue(&"gate_open", g))
	elif n is TransplantScreen:
		var ts := n as TransplantScreen
		ts.transplanted.connect(func(o): _cue(&"transplant" if o.success else &"transplant_reject"))
		ts.closed.connect(func(): _cue(&"ui_close"))
	elif n is DialogueBox:
		(n as DialogueBox).closed.connect(func(): _cue(&"ui_close"))
	elif n is BaseButton:
		var btn := n as BaseButton
		btn.pressed.connect(func(): _cue(&"ui_confirm"))
		btn.mouse_entered.connect(func():
			if not btn.disabled:
				_cue(&"ui_hover"))
	elif n is MainMenu:
		_menus.append(n)
	elif n is AreaTrigger:
		if AREA_AMBIENCE.has((n as AreaTrigger).trigger_id):
			_areas.append(n)
	elif n is PrologueGame:
		var g := n as PrologueGame
		_ending = &""
		_ambience(START_AMBIENCE)
		g.ending_reached.connect(func(id): _ending = StringName("ending_" + id))
		g.player_respawned.connect(func(): _ending = &"")
		g.tree_exiting.connect(func():
			reset()
			_ambience(&""))

# ---------- 戰鬥與解剖 ----------

func _hook_combat(c: CombatComponent) -> void:
	_creatures[c.get_instance_id()] = {"c": c, "state": null, "last_pos": null, "walked": 0.0}
	var b := c.body()
	c.attack_started.connect(func(a): _cue(ATTACK_CUES.get(a.id, &"attack_swing"), b))
	c.attack_missed.connect(func(_a): _cue(&"miss", b))
	c.hit_received.connect(func(r, _att): _on_hit(c, r))
	c.blocked.connect(func(_att, broken):
		_blocked_frame[c.get_instance_id()] = Engine.get_physics_frames()
		_cue(&"guard_break" if broken else &"block", b))
	c.dodged.connect(func(_att): _cue(&"dodge", b))
	c.staggered.connect(func(): _cue(&"stagger", b))
	c.died.connect(func(cause): if cause != "decor": _cue(&"death_player" if c.faction == &"player" else &"death_enemy", b))
	_rehook_anatomy(c)

## 讀檔會換掉 AnatomyState，所以每幀檢查並重新接上。
func _rehook_anatomy(c: CombatComponent) -> void:
	var info: Dictionary = _creatures.get(c.get_instance_id(), {})
	if info.is_empty() or c.anatomy == null or c.anatomy.state == null:
		return
	var st := c.anatomy.state
	if info.state == st:
		return
	info.state = st
	var b := c.body()
	st.part_severed.connect(func(_p, _ids):
		_cue(&"sever", b)
		_cue(&"bone_snap", b)
		if c.faction == &"player" and _psyche() != null:
			_psyche().on_player_severed())
	st.part_disabled.connect(func(_p, _r): _cue(&"part_disabled", b))
	st.vital_failed.connect(func(_p, _r): _cue(&"vital_fail", b))

func _on_hit(c: CombatComponent, r: DamageResult) -> void:
	if _blocked_frame.get(c.get_instance_id(), -1) == Engine.get_physics_frames():
		return  # 已經播了格擋聲
	_cue(hit_cue(r), c.body())

## 依命中結果選擇打擊聲：沒有造成傷害 → 打在護甲上；否則看最主要的損傷類型。
static func hit_cue(r: DamageResult) -> StringName:
	var loss := 0.0
	var by_type := {}
	for h in r.hits:
		loss += h.hp_loss
		for t in h.injuries:
			by_type[t] = float(by_type.get(t, 0.0)) + float(h.injuries[t])
	if loss <= 0.01 or by_type.is_empty():
		return &"hit_armor"
	var best: int = by_type.keys()[0]
	for t in by_type:
		if by_type[t] > by_type[best]:
			best = t
	match best:
		T.CUT, T.LACERATION:
			return &"hit_cut"
		T.CRUSH, T.FRACTURE:
			return &"hit_blunt"
		T.PIERCE:
			return &"hit_pierce"
		_:
			return &"hit_burn"

func _psyche() -> PsycheAudio:
	return manager.get(&"psyche") as PsycheAudio if manager != null else null

func _player() -> CombatComponent:
	for info in _creatures.values():
		if _live(info.c) and info.c.faction == &"player":
			return info.c
	return null

## 把玩家的 HP 與異化交給 PsycheAudio。沒有玩家（主選單）時效果歸零。
func update_psyche(delta: float) -> void:
	var ps := _psyche()
	if ps == null:
		return
	var p := _player()
	if p == null or p.is_dead():
		ps.update(delta, 1.0, 0.0, null)
		return
	var mut := p.body().get_node_or_null("MutationComponent") as MutationComponent
	var hp := p.pools.hp / maxf(1.0, p.pools.max_hp)
	ps.update(delta, hp, mut.value if mut != null else 0.0, p.body())

## 玩家是否站在靜默區裡（SilenceZone）。
func player_silenced() -> bool:
	var p := _player()
	if p == null or p.is_dead() or not p.body().is_inside_tree():
		return false
	var pos := p.body().global_position
	for z in get_tree().get_nodes_in_group(SilenceZone.GROUP):
		if _live(z) and (z as SilenceZone).contains(pos):
			return true
	return false

## 玩家所在區域的環境音；沒有玩家或沒有區域時回傳 &""。
func area_ambience() -> StringName:
	var player: CombatComponent = null
	for info in _creatures.values():
		if _live(info.c) and info.c.faction == &"player":
			player = info.c
	if player == null:
		return &""
	var pos := player.body().global_position
	var best: AreaTrigger = null
	var best_d := INF
	for a in _areas:
		if not _live(a):
			continue
		var d := Vector2(a.global_position.x - pos.x, a.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = a
	return AREA_AMBIENCE[best.trigger_id] if best != null else &""

func _ambience(id: StringName) -> void:
	if manager != null and manager.has_method(&"set_ambience"):
		manager.set_ambience(id)

func _cue(id: StringName, at: Variant = null) -> void:
	if manager != null and manager.has_method(&"play"):
		manager.play(id, at)

# ---------- 每幀：腳步、重新接上解剖、音樂狀態 ----------

func _physics_process(delta: float) -> void:
	_prune()
	for info in _creatures.values():
		var c: CombatComponent = info.c
		_rehook_anatomy(c)
		_step(c, delta)
	update_music(delta)
	update_psyche(delta)
	var amb := area_ambience()
	if compute_music_state() == &"silence" and player_silenced():
		_ambience(&"")
	elif amb != &"":
		_ambience(amb)

func _step(c: CombatComponent, _delta: float) -> void:
	var b := c.body() as CharacterBody3D
	if b == null or not b.is_inside_tree() or c.is_dead():
		return
	var info: Dictionary = _creatures[c.get_instance_id()]
	var pos := b.global_position
	if info.last_pos != null and b.is_on_floor():
		var d := Vector2(pos.x - info.last_pos.x, pos.z - info.last_pos.z).length()
		if d < 1.0:  # 傳送（重生、讀檔）不算走路
			info.walked += d
	info.last_pos = pos
	var stride: float = STRIDE.get(c.faction, DEFAULT_STRIDE)
	if info.walked >= stride:
		info.walked -= stride
		_cue(&"footstep", b)

func _on_ai_state(ai: EnemyAI, s: StringName) -> void:
	var level: int = AI_ALERT.get(s, 0)
	if level > 0:
		_alert[ai.get_instance_id()] = {"ai": ai, "level": level}
	else:
		_alert.erase(ai.get_instance_id())

## 依目前的遊戲狀況決定音樂狀態（優先順序：結局 > 死亡 > Boss > 戰鬥 > 緊張 > 探索 > 主選單）。
func compute_music_state() -> StringName:
	if _ending != &"":
		return _ending
	var player: CombatComponent = null
	for info in _creatures.values():
		if _live(info.c) and info.c.faction == &"player":
			player = info.c
	if player != null and player.is_dead():
		return &"death"
	for bp in _bosses:
		if _live(bp) and bp.engaged and not bp.combat.is_dead():
			return &"boss_2" if bp.phase >= 2 else &"boss_1"
	var top := 0
	for e in _alert.values():
		if _live(e.ai) and not e.ai.combat.is_dead():
			top = maxi(top, e.level)
	if top == 0 and _combat_hold <= 0.0 and _tension_hold <= 0.0 and player_silenced():
		return &"silence"
	if top >= 2 or _combat_hold > 0.0:
		return &"combat"
	if top == 1 or _tension_hold > 0.0:
		return &"tension"
	if player != null:
		return &"explore"
	if _menus.any(func(m): return _live(m)):
		return &"menu"
	return &"silence"

func update_music(delta: float) -> void:
	var top := 0
	for e in _alert.values():
		if _live(e.ai) and not e.ai.combat.is_dead():
			top = maxi(top, e.level)
	if top >= 2:
		_combat_hold = COMBAT_HOLD
	else:
		_combat_hold = maxf(0.0, _combat_hold - delta)
	if top == 1:
		_tension_hold = TENSION_HOLD
	else:
		_tension_hold = maxf(0.0, _tension_hold - delta)
	if manager != null and manager.has_method(&"set_music_state"):
		manager.set_music_state(compute_music_state())

## 只算還在場景樹裡的節點（已釋放或暫時移出的都不算）。
static func _live(n) -> bool:
	return is_instance_valid(n) and (n as Node).is_inside_tree()

func _prune() -> void:
	for id in _creatures.keys():
		if not is_instance_valid(_creatures[id].c):
			_creatures.erase(id)
			_blocked_frame.erase(id)
	for id in _alert.keys():
		if not is_instance_valid(_alert[id].ai):
			_alert.erase(id)
	_bosses = _bosses.filter(func(b): return is_instance_valid(b))
	_menus = _menus.filter(func(m): return is_instance_valid(m))
	_areas = _areas.filter(func(a): return is_instance_valid(a))
