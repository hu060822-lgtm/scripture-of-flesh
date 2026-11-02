class_name AnatomyComponent
extends Node
## 把 AnatomyState（純資料）掛到場景上。所有生物（玩家、敵人、NPC、Boss）共用。
## 其他元件透過 `state` 的 signal 反應，不直接修改部位。

@export var profile: AnatomyProfile
## 場景內的實體 ID，用於 EventBus 與存檔。
@export var creature_id: StringName = &"creature"
## 斷肢機率倍率。依 D2 決策：玩家約 0.5（比敵人難斷，但不能太低），敵人 1.0。
@export var sever_chance_scale: float = 1.0

var state: AnatomyState
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	if state == null:
		setup()

## 建立狀態。也可在加入場景前手動呼叫（測試、讀檔）。
func setup(from_state: AnatomyState = null) -> void:
	assert(profile != null, "AnatomyComponent needs a profile")
	state = from_state if from_state != null else AnatomyState.from_profile(profile)
	state.part_severed.connect(_on_part_severed)
	state.part_disabled.connect(_on_part_disabled)
	state.vital_failed.connect(_on_vital_failed)

## 對此生物套用一次命中。斷肢倍率在這裡套用，DamageResolver 本身不知道誰是玩家。
func receive(packet: DamagePacket) -> DamageResult:
	var p := packet
	if not is_equal_approx(sever_chance_scale, 1.0):
		p = DamagePacket.make(packet.target_part_id, packet.amounts)
		p.armor_penetration = packet.armor_penetration
		p.bleed_multiplier = packet.bleed_multiplier
		p.sever_power = packet.sever_power * sever_chance_scale
		p.source_id = packet.source_id
	return state.receive(p, rng)

func _on_part_severed(_part_id: StringName, ids: PackedStringArray) -> void:
	if is_inside_tree():
		EventBus.creature_part_severed.emit(creature_id, ids)

func _on_part_disabled(part_id: StringName, _reason: String) -> void:
	if is_inside_tree():
		EventBus.creature_part_disabled.emit(creature_id, part_id)

func _on_vital_failed(part_id: StringName, rule: int) -> void:
	if is_inside_tree():
		EventBus.creature_vital_failed.emit(creature_id, part_id, rule)
