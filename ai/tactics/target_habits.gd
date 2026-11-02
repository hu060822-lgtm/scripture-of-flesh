class_name TargetHabits
extends RefCounted
## 記錄目標（玩家）面對「我的攻擊」時的習慣：常防禦、常閃避、常搶攻。
## 只讀取畫面上看得到的動作（防禦姿勢、翻滾、出招），不讀玩家輸入。
## 以指數移動平均累積，越新的反應影響越大。

const LEARN_RATE := 0.35

## 0..1：最近幾次被攻擊時防禦／閃避／反擊的比例。
var block_rate := 0.0
var dodge_rate := 0.0
var counter_rate := 0.0
var samples := 0

var _watching := false
var _saw_block := false
var _saw_dodge := false
var _saw_counter := false

## 每次決策推進時呼叫：mine = 我的戰鬥元件、target = 目標。
func observe(mine: CombatComponent, target: CombatComponent) -> void:
	if target == null:
		_watching = false
		return
	var attacking := mine.action in [CombatComponent.Action.WINDUP, CombatComponent.Action.ACTIVE]
	if attacking:
		if not _watching:
			_watching = true
			_saw_block = false
			_saw_dodge = false
			_saw_counter = false
		if target.blocking:
			_saw_block = true
		if target.action == CombatComponent.Action.DODGE:
			_saw_dodge = true
		if target.action in [CombatComponent.Action.WINDUP, CombatComponent.Action.ACTIVE]:
			_saw_counter = true
	elif _watching:
		_watching = false
		record(_saw_block, _saw_dodge, _saw_counter)

func record(blocked: bool, dodged: bool, countered: bool) -> void:
	samples += 1
	block_rate = lerpf(block_rate, 1.0 if blocked else 0.0, LEARN_RATE)
	dodge_rate = lerpf(dodge_rate, 1.0 if dodged else 0.0, LEARN_RATE)
	counter_rate = lerpf(counter_rate, 1.0 if countered else 0.0, LEARN_RATE)
