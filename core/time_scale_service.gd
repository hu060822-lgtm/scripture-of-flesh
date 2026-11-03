extends Node
## 戰鬥時間倍率（autoload: TimeScale）。
## 戰術介面（D3）預設減速到 10%，可切換為完全暫停。只影響戰鬥實體，UI 不受影響，
## 因此不使用 Engine.time_scale。戰鬥相關節點以 TimeScale.scaled(delta) 推進。

signal mode_changed(mode: int)

enum Mode { NORMAL, SLOW, PAUSE }

const SLOW_SCALE := 0.1
## 頓幀（hitstop）期間的戰鬥時間倍率：幾乎停住，但不是完全靜止。
const HITSTOP_SCALE := 0.03
## 單次頓幀的上限（秒，真實時間），避免連續命中疊加成卡頓。
const HITSTOP_MAX := 0.2

var mode: int = Mode.NORMAL
## 關閉後 hitstop() 不作用（自動化測試／模擬用）。
var hitstop_enabled := true
## 頓幀結束的真實時間（微秒）。以真實時鐘計算，不依賴 _process，也不受戰鬥減速影響。
var _hitstop_end_us := 0

## 打擊頓幀：命中瞬間讓戰鬥時間停頓 duration 秒（真實時間），製造打擊的重量感。
## 只影響以 TimeScale 推進的戰鬥實體；UI、鏡頭震動、受擊閃白以真實時間進行。
## 已在頓幀中時取較長者，不累加。
func hitstop(duration: float) -> void:
	if not hitstop_enabled or duration <= 0.0:
		return
	var end := Time.get_ticks_usec() + int(minf(duration, HITSTOP_MAX) * 1000000.0)
	_hitstop_end_us = maxi(_hitstop_end_us, end)

func in_hitstop() -> bool:
	return _hitstop_end_us > 0 and Time.get_ticks_usec() < _hitstop_end_us

func clear_hitstop() -> void:
	_hitstop_end_us = 0

func combat_scale() -> float:
	if mode == Mode.NORMAL and in_hitstop():
		return HITSTOP_SCALE
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
