class_name DamagePacket
extends RefCounted
## 一次命中的輸入資料。由攻擊（之後的 AttackDefinition + WeaponDefinition）產生。

## key 為 DamageTypes.Type，value 為原始傷害量。
var amounts := {}
var target_part_id: StringName
## 護甲穿透 0–1。
var armor_penetration: float = 0.0
var bleed_multiplier: float = 1.0
## 斷肢能力倍率（武器決定，例如斧頭 > 刺劍）。
var sever_power: float = 1.0
var source_id: StringName = &""

static func make(target: StringName, damage: Dictionary) -> DamagePacket:
	var p := DamagePacket.new()
	p.target_part_id = target
	p.amounts = damage.duplicate()
	return p
