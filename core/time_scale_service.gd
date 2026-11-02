extends Node
## 戰鬥時間倍率（autoload: TimeScale）。
## 戰術介面（D3）預設減速到 10%，可切換為完全暫停。只影響戰鬥實體，UI 不受影響，
## 因此不使用 Engine.time_scale。戰鬥相關節點以 TimeScale.scaled(delta) 推進。

signal mode_changed(mode: int)

enum Mode { NORMAL, SLOW, PAUSE }

const SLOW_SCALE := 0.1

var mode: int = Mode.NORMAL

func combat_scale() -> float:
	match mode:
		Mode.SLOW: return SLOW_SCALE
		Mode.PAUSE: return 0.0
		_: return 1.0

func scaled(delta: float) -> float:
	return delta * combat_scale()

func set_mode(m: int) -> void:
	if m != mode:
		mode = m
		mode_changed.emit(m)
