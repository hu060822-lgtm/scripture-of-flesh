class_name CombatComponent
extends Node
## 戰鬥元件：攻擊、防禦、閃避、受擊、資源（HP/ST/AP）、死亡。玩家與敵人共用。
## 控制器（玩家輸入或 AI）只呼叫 try_attack / dodge / set_blocking，不直接算傷害。
## 時間由 advance(delta) 推進；_physics_process 會以 TimeScale 倍率呼叫它。

signal action_changed(action: int)
signal attack_started(attack: AttackDefinition)
signal attack_landed(target: CombatComponent, result: DamageResult)
signal attack_missed(attack: AttackDefinition)
signal hit_received(result: DamageResult, attacker: CombatComponent)
signal blocked(attacker: CombatComponent, guard_broken: bool)
signal dodged(attacker: CombatComponent)
signal staggered
signal died(cause: String)

enum Action { IDLE, WINDUP, ACTIVE, RECOVERY, DODGE, STAGGER, DEAD }

const GROUP := &"combatants"
## 部位 HP 損失轉為整體 HP 損失的比例。
const BODY_HP_FACTOR := 0.6
## 每點失血扣除的整體 HP。
const BLEED_HP_FACTOR := 1.0
const TARGET_RADIUS := 0.4
const AP_PER_HIT := 4.0

@export var faction: StringName = &"enemy"
@export var max_hp: float = 100.0
@export var max_st: float = 100.0
@export var max_ap: float = 100.0
## 徒手／天生攻擊（拳、踢、咬…）。武器攻擊來自手上的 WeaponDefinition。
@export var natural_attacks: Array[AttackDefinition] = []
@export var stagger_threshold: float = 12.0
@export var stagger_duration: float = 0.5
@export var block_reduction: float = 0.7
@export var block_st_per_damage: float = 1.2
@export var dodge_st_cost: float = 20.0
@export var dodge_duration: float = 0.45
@export var dodge_iframes: float = 0.3
@export var dodge_speed: float = 7.0
## 致命部位為 COUNTDOWN（肺）時，失效後幾秒死亡。
@export var vital_countdown: float = 8.0

var pools := ResourcePools.new()
var anatomy: AnatomyComponent
var equipment: EquipmentComponent
var action: int = Action.IDLE
var blocking := false
var current_attack: AttackDefinition
var current_target_part: StringName = &""
var dodge_direction := Vector3.ZERO
var vital_timer := -1.0
var _timer := 0.0
var _elapsed_in_dodge := 0.0
var _cooldowns := {}  # attack id -> 剩餘秒數

func _ready() -> void:
	var owner_body := body()
	owner_body.add_to_group(GROUP)
	if anatomy == null:
		anatomy = owner_body.get_node_or_null("AnatomyComponent")
	if equipment == null:
		equipment = owner_body.get_node_or_null("EquipmentComponent")
	if anatomy.state == null:
		anatomy.setup()
	pools.setup(max_hp, max_st, max_ap)
	pools.hp_depleted.connect(func(cause): _die(cause))
	anatomy.state.died.connect(func(part): _die("vital:%s" % part))
	anatomy.state.vital_failed.connect(_on_vital_failed)
	anatomy.state.part_restored.connect(_on_part_restored)

func body() -> Node3D:
	return get_parent() as Node3D

func is_dead() -> bool:
	return action == Action.DEAD

func _physics_process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

# ---------- 查詢 ----------

func caps() -> CapabilitySet:
	return anatomy.state.capabilities()

func weapon() -> WeaponDefinition:
	return equipment.held_weapon() if equipment != null else null

## 目前身體狀態下可用的所有攻擊（不考慮資源與冷卻）。
func available_attacks() -> Array[AttackDefinition]:
	var out: Array[AttackDefinition] = []
	var c := caps()
	var w := weapon()
	if w != null and c.count("grip") >= w.required_grip:
		for a in w.attacks():
			if c.satisfies(a.required_capabilities):
				out.append(a)
	for a in natural_attacks:
		if not a.requires_weapon and c.satisfies(a.required_capabilities):
			out.append(a)
	return out

func can_use(attack: AttackDefinition) -> bool:
	return attack in available_attacks() \
		and float(_cooldowns.get(attack.id, 0.0)) <= 0.0 \
		and pools.can_spend_st(attack.st_cost) and pools.ap >= attack.ap_cost

## 腿部能力影響移動速度：雙腿 1.0、單腿 0.45、無腿（爬行）0.15。
func movement_multiplier() -> float:
	match action:
		Action.DEAD, Action.STAGGER: return 0.0
		Action.WINDUP, Action.ACTIVE: return 0.2
		Action.RECOVERY: return 0.5
	var loco := caps().count("locomotion")
	var m := 1.0 if loco >= 2 else (0.45 if loco == 1 else 0.15)
	return m * (0.5 if blocking else 1.0)

func is_invulnerable() -> bool:
	return action == Action.DODGE and _elapsed_in_dodge < dodge_iframes

# ---------- 行動 ----------

## 開始一次攻擊。target_part 由戰術介面指定（空字串代表依攻擊方向自動決定）。
func try_attack(attack: AttackDefinition, target_part: StringName = &"") -> bool:
	if action != Action.IDLE or attack == null or not can_use(attack):
		return false
	if attack.ap_cost > 0.0 and not pools.spend_ap(attack.ap_cost):
		return false
	pools.spend_st(attack.st_cost)
	blocking = false
	current_attack = attack
	current_target_part = target_part
	if attack.cooldown > 0.0:
		_cooldowns[attack.id] = attack.cooldown
	_set_action(Action.WINDUP, attack.windup)
	attack_started.emit(attack)
	return true

## 閃避。需要至少一條可用的腿。direction 為世界座標的水平方向。
func dodge(direction: Vector3) -> bool:
	if action != Action.IDLE or caps().count("locomotion") < 1:
		return false
	if not pools.spend_st(dodge_st_cost):
		return false
	blocking = false
	var d := Vector3(direction.x, 0, direction.z)
	dodge_direction = d.normalized() if d.length() > 0.01 else body().global_transform.basis.z
	_elapsed_in_dodge = 0.0
	_set_action(Action.DODGE, dodge_duration)
	return true

## 防禦需要至少一隻可用的手。
func set_blocking(on: bool) -> void:
	blocking = on and action == Action.IDLE and caps().count("grip") >= 1 and not is_dead()

# ---------- 時間推進 ----------

func advance(delta: float) -> void:
	if delta <= 0.0 or is_dead():
		return
	for k in _cooldowns.keys():
		_cooldowns[k] = float(_cooldowns[k]) - delta
	pools.tick(delta, action == Action.IDLE and not blocking)
	var blood := anatomy.state.tick(delta)
	if blood > 0.0:
		pools.damage_hp(blood * BLEED_HP_FACTOR, "bleeding")
	if vital_timer >= 0.0 and not is_dead():
		vital_timer -= delta
		if vital_timer <= 0.0:
			_die("vital_countdown")
	if is_dead():
		return
	if action == Action.DODGE:
		_elapsed_in_dodge += delta
	if action != Action.IDLE:
		_timer -= delta
		if _timer <= 0.0:
			_advance_action()

func _advance_action() -> void:
	match action:
		Action.WINDUP:
			_set_action(Action.ACTIVE, current_attack.active)
			_perform_hit()
		Action.ACTIVE:
			_set_action(Action.RECOVERY, current_attack.recovery)
		Action.RECOVERY, Action.DODGE, Action.STAGGER:
			current_attack = null
			_set_action(Action.IDLE, 0.0)

func _set_action(a: int, duration: float) -> void:
	action = a
	_timer = duration
	action_changed.emit(a)

# ---------- 命中 ----------

## 在攻擊扇形內找最近的敵對目標。純幾何計算，不需要物理步進（方便測試與戰術減速）。
func find_target(attack: AttackDefinition) -> CombatComponent:
	var me := body()
	var origin := me.global_position
	var forward := -me.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var best: CombatComponent = null
	var best_dist := INF
	for n in get_tree().get_nodes_in_group(GROUP):
		if n == me:
			continue
		var other: CombatComponent = n.get_node_or_null("CombatComponent")
		if other == null or other.is_dead() or other.faction == faction:
			continue
		var to := (n as Node3D).global_position - origin
		to.y = 0
		var dist := to.length()
		if dist > attack.reach + TARGET_RADIUS:
			continue
		if dist > 0.05 and rad_to_deg(forward.angle_to(to / dist)) > attack.arc_degrees * 0.5:
			continue
		if dist < best_dist:
			best_dist = dist
			best = other
	return best

## 決定命中部位：戰術指定的部位優先，否則取最接近攻擊點的可命中部位。
func choose_part(target: CombatComponent, attack: AttackDefinition, requested: StringName) -> StringName:
	var targetable := target.anatomy.state.targetable_part_ids()
	if requested != &"" and requested in targetable:
		return requested
	if attack.preferred_target_part != &"" and attack.preferred_target_part in targetable:
		return attack.preferred_target_part
	var me := body()
	var to := target.body().global_position - me.global_position
	to.y = 0
	var point := me.global_position + to * 0.85 + Vector3.UP * attack.aim_height
	var best: StringName = &""
	var best_d := INF
	var ctrl: DismembermentController = target.body().get_node_or_null("DismembermentController")
	for pid in targetable:
		var hb: Hurtbox = ctrl.hurtbox_for(pid) if ctrl != null else null
		if hb == null or not hb.active:
			continue
		var d := hb.global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = pid
	if best == &"" and not targetable.is_empty():
		best = targetable[0]
	return best

func build_packet(attack: AttackDefinition, part: StringName) -> DamagePacket:
	var w := weapon()
	var p := DamagePacket.new()
	p.target_part_id = part
	p.source_id = attack.id
	if attack.requires_weapon and w != null:
		p.amounts = DamageTypes.merge(DamageTypes.from_names(w.damage, attack.damage_scale), DamageTypes.from_names(attack.damage))
		p.sever_power = w.sever_power * attack.sever_power
		p.armor_penetration = clampf(w.armor_penetration + attack.armor_penetration_bonus, 0.0, 1.0)
		p.bleed_multiplier = w.bleed_multiplier
	else:
		p.amounts = DamageTypes.from_names(attack.damage, attack.damage_scale)
		p.sever_power = attack.sever_power
		p.armor_penetration = clampf(attack.armor_penetration_bonus, 0.0, 1.0)
	return p

func _perform_hit() -> void:
	var attack := current_attack
	var target := find_target(attack)
	if target == null:
		attack_missed.emit(attack)
		return
	var part := choose_part(target, attack, current_target_part)
	if part == &"":
		attack_missed.emit(attack)
		return
	var result := target.receive_hit(build_packet(attack, part), self, attack)
	if result != null and not result.rejected:
		pools.add_ap(AP_PER_HIT)
		attack_landed.emit(target, result)

## 受到攻擊。回傳 null 代表被閃避；被防禦時傷害已減免。
func receive_hit(packet: DamagePacket, attacker: CombatComponent, attack: AttackDefinition = null) -> DamageResult:
	if is_dead():
		return null
	if is_invulnerable():
		dodged.emit(attacker)
		return null
	var p := packet
	if blocking and attacker != null and _is_facing(attacker.body()):
		var total := 0.0
		for t in packet.amounts:
			total += float(packet.amounts[t])
		var broken := pools.drain_st(total * block_st_per_damage)
		blocked.emit(attacker, broken)
		if broken:
			blocking = false
			_stagger()
		else:
			p = DamagePacket.make(packet.target_part_id, {})
			for t in packet.amounts:
				p.amounts[t] = float(packet.amounts[t]) * (1.0 - block_reduction)
			p.sever_power = 0.0  # 成功防禦時不會被斷肢
			p.armor_penetration = packet.armor_penetration
			p.bleed_multiplier = packet.bleed_multiplier
			p.source_id = packet.source_id
	var result := anatomy.receive(p)
	if result.rejected:
		return result
	var part_loss := 0.0
	for h in result.hits:
		part_loss += h.hp_loss
	pools.damage_hp(part_loss * BODY_HP_FACTOR, "hit")
	hit_received.emit(result, attacker)
	var threshold := stagger_threshold + (attack.stagger_threshold_bonus if attack != null else 0.0)
	if not is_dead() and result.hits.size() > 0 and result.hits[0].hp_loss >= threshold:
		_stagger()
	return result

func _is_facing(other: Node3D) -> bool:
	var me := body()
	var to := other.global_position - me.global_position
	to.y = 0
	if to.length() < 0.01:
		return true
	var forward := -me.global_transform.basis.z
	forward.y = 0
	return forward.normalized().dot(to.normalized()) > 0.3

func _stagger() -> void:
	if is_dead():
		return
	current_attack = null
	blocking = false
	_set_action(Action.STAGGER, stagger_duration)
	staggered.emit()

func _on_vital_failed(_part: StringName, rule: int) -> void:
	if rule == BodyPartDef.VitalRule.COUNTDOWN and vital_timer < 0.0:
		vital_timer = vital_countdown

func _on_part_restored(_part: StringName) -> void:
	# 修復後若已無失效的倒數型致命部位，停止倒數。
	for pid in anatomy.state.part_ids():
		var p := anatomy.state.get_part(pid)
		if p.def.vital == BodyPartDef.VitalRule.COUNTDOWN and not p.is_functional():
			return
	vital_timer = -1.0

func _die(cause: String) -> void:
	if is_dead():
		return
	blocking = false
	current_attack = null
	if pools.hp > 0.0:
		pools.hp = 0.0
		pools.hp_changed.emit(0.0, pools.max_hp)
	_set_action(Action.DEAD, 0.0)
	died.emit(cause)
