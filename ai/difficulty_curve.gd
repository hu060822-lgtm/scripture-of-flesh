class_name DifficultyCurve
extends RefCounted
## 新手難度曲線：依敵人在序章中的位置（進度 0..1）縮放強度。
## 進度 0（第一隻縫屍者）最溫和，進度 1（Boss）是原本的完整強度。
## 預設用指數曲線：前段長時間保持溫和，接近 Boss 時才快速上升。
## 【暫代】各係數為初值，需要實際遊玩調整。

enum Mode { EXPONENTIAL, LINEAR, OFF }

static var mode: int = Mode.EXPONENTIAL
## 指數曲線的陡度（越大前段越平、後段越陡）。
const STEEPNESS := 2.5

## 進度 0 時相對於完整強度的倍率（進度 1 時都是 1.0）。
const EASY := {
	"damage": 0.45,          # 對玩家造成的傷害
	"max_hp": 0.65,
	"aggression": 0.5,
	"punish_skill": 0.2,     # 趁隙
	"adaptivity": 0.0,       # 讀玩家習慣
	"injured_target_bias": 0.25,
	"flank_tendency": 0.3,
	"dodge_chance": 0.3,
	"defend_chance": 0.5,
	"decision_interval": 1.7, # >1：反應較慢
}
## 曲線值低於這個門檻時：一次只有 1 隻出手、不呼叫同伴。
const SOLO_BELOW := 0.35

## 序章各生成點的進度（依預期遊玩順序）。不在表中的生成點依 Z 座標推估。
const PROLOGUE_PROGRESS := {
	&"corridor_stitcher_1": 0.0,
	&"corridor_stitcher_2": 0.12,
	&"courtyard_stitcher": 0.3,
	&"courtyard_reverse_1": 0.4,
	&"courtyard_reverse_2": 0.45,
	&"archive_watcher_1": 0.6,
	&"archive_watcher_2": 0.62,
	&"sacristy_many_hands": 0.8,
}
## Z 推估：產房（z=0）到禮拜堂（z=-71）。
const LEVEL_DEPTH := 71.0

static func progress_for(spawn_id: StringName, position: Vector3) -> float:
	if PROLOGUE_PROGRESS.has(spawn_id):
		return PROLOGUE_PROGRESS[spawn_id]
	return clampf(-position.z / LEVEL_DEPTH, 0.0, 1.0)

## 曲線值 0..1。
static func ramp(progress: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	match mode:
		Mode.OFF:
			return 1.0
		Mode.LINEAR:
			return p
	return (exp(STEEPNESS * p) - 1.0) / (exp(STEEPNESS) - 1.0)

static func factor(key: String, progress: float) -> float:
	return lerpf(float(EASY[key]), 1.0, ramp(progress))

## 回傳依進度調整過的定義副本（進度 1 或關閉時回傳原本的資源）。
static func apply(def: EnemyDefinition, progress: float) -> EnemyDefinition:
	var t := ramp(progress)
	if t >= 0.999:
		return def
	var d := def.duplicate() as EnemyDefinition
	d.damage_scale = def.damage_scale * factor("damage", progress)
	d.max_hp = def.max_hp * factor("max_hp", progress)
	for k in ["aggression", "punish_skill", "adaptivity", "injured_target_bias", "flank_tendency", "dodge_chance", "defend_chance", "decision_interval"]:
		d.set(k, float(def.get(k)) * factor(k, progress))
	if t < SOLO_BELOW:
		d.squad_attackers = 1
		d.alarm_radius = 0.0
	return d
