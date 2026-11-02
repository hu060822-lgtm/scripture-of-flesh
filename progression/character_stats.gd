@tool
class_name CharacterStats
extends Resource
## 六種基礎屬性與衍生數值。職業只決定起始值，之後可自由分配（不鎖成長路線）。

@export var STR: int = 10  ## 力量：切割／粉碎傷害、雙手武器
@export var DEX: int = 10  ## 敏捷：體力消耗、刺劍
@export var VIT: int = 10  ## 體質：HP、出血抗性
@export var PER: int = 10  ## 感知：AP 獲得、戰術預覽
@export var WIL: int = 10  ## 意志：AP 上限、異化抗性
@export var TEC: int = 10  ## 技術：縫合、器官相容性

const NAMES := ["STR", "DEX", "VIT", "PER", "WIL", "TEC"]

func get_stat(n: String) -> int:
	return int(get(n))

func add(n: String, amount: int) -> void:
	set(n, get_stat(n) + amount)

func max_hp() -> float:
	return 100.0 + (VIT - 10) * 8.0

func max_st() -> float:
	return 100.0 + (DEX - 10) * 3.0 + (VIT - 10) * 2.0

func max_ap() -> float:
	return 100.0 + (WIL - 10) * 4.0

## 依武器類型的屬性傷害倍率。
func damage_scale(weapon_type: StringName) -> float:
	match weapon_type:
		&"hammer": return 1.0 + (STR - 10) * 0.04
		&"rapier": return 1.0 + (DEX - 10) * 0.04
		&"cleaver": return 1.0 + (STR - 10) * 0.025 + (DEX - 10) * 0.015
		_: return 1.0 + (STR - 10) * 0.02

## 異化抗性：降低異化增加量。
func mutation_resistance() -> float:
	return clampf((WIL - 10) * 0.03, -0.3, 0.5)

## 器官相容性加成。
func compatibility_bonus() -> float:
	return (TEC - 10) * 0.025

func to_dict() -> Dictionary:
	var d := {}
	for n in NAMES:
		d[n] = get_stat(n)
	return d

func load_dict(d: Dictionary) -> void:
	for n in NAMES:
		if d.has(n):
			set(n, int(d[n]))
