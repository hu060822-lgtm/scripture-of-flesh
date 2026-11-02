class_name SoundCue
extends RefCounted
## 一個「聲音事件」：遊戲只說要播哪個 cue（例如 &"sever"），由這裡決定實際的檔案、匯流排與變化。
## 音檔放在 res://audio/sfx/<id>/ 資料夾（.wav / .ogg / .mp3），資料夾裡的每個檔案都是一個變體。
## 資料夾是空的時，cue 是【暫代】靜音：照常記錄（方便測試與除錯），但不發聲。

var id: StringName
var bus: StringName = &"SFX"
var volume_db := 0.0
## 每次播放的隨機音高範圍（1.0 = 原音高）。
var pitch_min := 0.94
var pitch_max := 1.06
## 同一個 cue 同時最多幾個聲音；超過時停掉最舊的那個。
var max_voices := 4
## 兩次播放之間的最短秒數（避免同一幀多次命中疊成爆音）。
var cooldown := 0.03
## true：在 3D 位置播放（有距離衰減）；false：直接播（UI、音樂、Boss 演出）。
var positional := true
var max_distance := 30.0
var streams: Array[AudioStream] = []

func _init(cue_id: StringName = &"", cue_bus: StringName = &"SFX") -> void:
	id = cue_id
	bus = cue_bus

func is_placeholder() -> bool:
	return streams.is_empty()

## 選一個變體：不連續重複同一個（只有一個變體時例外）。
func pick(rng: RandomNumberGenerator, last_index: int) -> int:
	if streams.is_empty():
		return -1
	if streams.size() == 1:
		return 0
	if last_index < 0 or last_index >= streams.size():
		return rng.randi_range(0, streams.size() - 1)
	var i := rng.randi_range(0, streams.size() - 2)
	return i + 1 if i >= last_index else i
