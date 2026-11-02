
extends RefCounted
## 測試共用工具。

const HUMANOID := "res://content/anatomy/humanoid.tres"
const MULTI_ARMED := "res://content/anatomy/multi_armed.tres"
const T := DamageTypes.Type

static func humanoid() -> AnatomyState:
	return AnatomyState.from_profile(load(HUMANOID))

static func multi_armed() -> AnatomyState:
	return AnatomyState.from_profile(load(MULTI_ARMED))

static func rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## 不會斷肢的命中（sever_power = 0），用來測試純傷害與功能失效。
static func no_sever(target: StringName, damage: Dictionary) -> DamagePacket:
	var p := DamagePacket.make(target, damage)
	p.sever_power = 0.0
	return p

## 記錄 signal 的小工具。
class SignalLog:
	var events: Array = []
	func connect_all(s: AnatomyState) -> void:
		s.part_status_changed.connect(func(id, a, b): events.append(["status", id, a, b]))
		s.part_disabled.connect(func(id, reason): events.append(["disabled", id, reason]))
		s.part_severed.connect(func(id, ids): events.append(["severed", id, ids]))
		s.capabilities_changed.connect(func(c): events.append(["caps", c]))
		s.vital_failed.connect(func(id, rule): events.append(["vital", id, rule]))
		s.died.connect(func(id): events.append(["died", id]))
		s.part_restored.connect(func(id): events.append(["restored", id]))
	func of(kind: String) -> Array:
		return events.filter(func(e): return e[0] == kind)
