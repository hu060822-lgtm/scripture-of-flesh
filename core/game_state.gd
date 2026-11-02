extends Node
## 全域遊戲狀態（autoload: GameState）：劇情旗標、世界狀態、目前檢查點。
## 玩家身體等狀態在玩家節點上，由 SaveSystem 統一收集。

signal flag_set(flag: StringName, value: Variant)

var flags := {}
## 已被擊殺且不會重生的敵人（spawn id）。
var killed := {}
## 已拿取的物品／已開啟的機關（object id）。
var taken := {}
var checkpoint_altar: StringName = &""
var class_id: StringName = &""
var playtime := 0.0
## 執行期（不存檔）：主選單選擇的開始方式，"new" 或 "continue"。
var start_mode := "new"

func _process(delta: float) -> void:
	playtime += delta

func reset() -> void:
	flags.clear()
	killed.clear()
	taken.clear()
	checkpoint_altar = &""
	class_id = &""
	playtime = 0.0

func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value
	flag_set.emit(flag, value)
	EventBus.flag_changed.emit(flag, value)

func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return flags.get(flag, default)

func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))

func to_save() -> Dictionary:
	var f := {}
	for k in flags:
		f[String(k)] = flags[k]
	return {"flags": f, "killed": killed.keys().map(func(k): return String(k)),
		"taken": taken.keys().map(func(k): return String(k)),
		"checkpoint": String(checkpoint_altar), "class": String(class_id), "playtime": playtime}

func load_save(d: Dictionary) -> void:
	reset()
	for k in d.get("flags", {}):
		flags[StringName(k)] = d["flags"][k]
	for k in d.get("killed", []):
		killed[StringName(k)] = true
	for k in d.get("taken", []):
		taken[StringName(k)] = true
	checkpoint_altar = StringName(d.get("checkpoint", ""))
	class_id = StringName(d.get("class", ""))
	playtime = float(d.get("playtime", 0.0))
