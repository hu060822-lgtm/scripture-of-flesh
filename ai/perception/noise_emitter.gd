class_name NoiseEmitter
extends Node
## 把生物的戰鬥動作轉成聲響事件（EventBus.noise_emitted），供敵人 AI 的聽覺使用。
## 掛在生物本體下（與 CombatComponent 同層）。玩家與敵人都可以用。
## 【暫代】半徑為初值，未經遊玩測試；之後音效執行緒可以在同一時機播放音效。

const RADIUS := {
	&"attack": 6.0,   # 出招（揮動、吼叫）
	&"impact": 9.0,   # 命中、被擋下
	&"dodge": 3.5,    # 翻滾、腳步聲
	&"sever": 12.0,   # 斷肢、慘叫
}

var combat: CombatComponent

func _ready() -> void:
	combat = get_parent().get_node("CombatComponent")
	combat.attack_started.connect(func(_a): _emit(&"attack"))
	combat.attack_landed.connect(func(_t, _r): _emit(&"impact"))
	combat.blocked.connect(func(_a, _b): _emit(&"impact"))
	combat.action_changed.connect(func(a): if a == CombatComponent.Action.DODGE: _emit(&"dodge"))
	combat.anatomy.state.part_severed.connect(func(_p, _ids): _emit(&"sever"))

func _emit(kind: StringName) -> void:
	var b := get_parent() as Node3D
	if b == null or not b.is_inside_tree():
		return
	EventBus.emit_noise(b.global_position, RADIUS.get(kind, 5.0), b, kind)
