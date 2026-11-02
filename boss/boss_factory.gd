class_name BossFactory
extends RefCounted
## 組裝 Boss：一般敵人組裝 + 階段控制元件。

const MOTHER := "res://content/enemies/walking_mother.tres"

static func create_mother(creature_id: StringName = &"walking_mother") -> CharacterBody3D:
	var body := EnemyFactory.create(load(MOTHER), creature_id)
	body.set_meta(&"boss", true)
	var phase := BossPhaseComponent.new()
	phase.name = "BossPhase"
	body.add_child(phase)
	return body
