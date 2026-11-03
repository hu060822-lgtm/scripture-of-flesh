class_name ResourcePools
extends RefCounted
## HP（生命）、ST（體力）、AP（戰術行動點）。

signal hp_changed(value: float, max_value: float)
signal st_changed(value: float, max_value: float)
signal ap_changed(value: float, max_value: float)
signal hp_depleted(cause: String)

var max_hp := 100.0
var max_st := 100.0
var max_ap := 100.0
var hp := 100.0
var st := 100.0
var ap := 0.0
## 每秒體力回復，花費後延遲一段時間才開始回復。
var st_regen := 22.0
var st_regen_delay := 0.6
## 器官造成的體力回復倍率。
var st_regen_scale := 1.0
var _st_cooldown := 0.0

func setup(hp_max: float, st_max: float, ap_max: float, ap_start: float = 0.0) -> void:
	max_hp = hp_max; hp = hp_max
	max_st = st_max; st = st_max
	max_ap = ap_max; ap = clampf(ap_start, 0.0, ap_max)

func is_dead() -> bool:
	return hp <= 0.0

func damage_hp(amount: float, cause: String = "damage") -> void:
	if amount <= 0.0 or hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		hp_depleted.emit(cause)

func heal_hp(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)

func can_spend_st(amount: float) -> bool:
	return amount <= 0.0 or st > 0.0 and st >= amount * 0.5  # 體力不足一半時不能行動；夠一半可透支到 0

func spend_st(amount: float) -> bool:
	if not can_spend_st(amount):
		return false
	st = maxf(0.0, st - amount)
	_st_cooldown = st_regen_delay
	st_changed.emit(st, max_st)
	return true

## 強制扣除（防禦時被打）。回傳是否被扣到見底。
func drain_st(amount: float) -> bool:
	st = maxf(0.0, st - amount)
	_st_cooldown = st_regen_delay
	st_changed.emit(st, max_st)
	return st <= 0.0

func add_ap(amount: float) -> void:
	ap = clampf(ap + amount, 0.0, max_ap)
	ap_changed.emit(ap, max_ap)

func spend_ap(amount: float) -> bool:
	if ap < amount:
		return false
	ap -= amount
	ap_changed.emit(ap, max_ap)
	return true

func tick(delta: float, regen_allowed: bool = true) -> void:
	if _st_cooldown > 0.0:
		_st_cooldown -= delta
	elif regen_allowed and st < max_st:
		st = minf(max_st, st + st_regen * st_regen_scale * delta)
		st_changed.emit(st, max_st)

func to_save() -> Dictionary:
	return {"hp": hp, "st": st, "ap": ap, "max_hp": max_hp, "max_st": max_st, "max_ap": max_ap}

func load_save(d: Dictionary) -> void:
	max_hp = float(d.get("max_hp", max_hp)); max_st = float(d.get("max_st", max_st)); max_ap = float(d.get("max_ap", max_ap))
	hp = clampf(float(d.get("hp", max_hp)), 0.0, max_hp)
	st = clampf(float(d.get("st", max_st)), 0.0, max_st)
	ap = clampf(float(d.get("ap", 0.0)), 0.0, max_ap)
