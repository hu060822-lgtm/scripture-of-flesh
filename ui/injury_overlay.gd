class_name InjuryOverlay
extends CanvasLayer
## 受傷／瀕死畫面效果。只看玩家：
## - HP 30% 開始：暗紅暗角隨心跳收縮、色階變少、輕微色差；10% 以下出現雙重影像。心跳聲越來越快。
## - 依部位：眼睛受損／失去 → 那一側變暗變糊；頭部重傷 → 畫面歪斜晃動；
##   心臟（伊蓮的心）垂危 → 心跳裡混進小女孩的哼聲，畫面閃過她的剪影；失血 → 顏色流走變灰。
## - 死亡：畫面從上下被縫線縫起來。
## 閃爍類效果（剪影、雙重影像）可在設定關閉：user://settings.cfg [video] injury_flashes。
## 和 PsycheAudio 的低血量悶聲用同一條 HP 曲線（30% → 5%）。

const SHADER := preload("res://ui/injury_fx.gdshader")
const HEARTBEAT := "res://audio/music/stingers/heartbeat.ogg"
const CHILD_HUM := "res://audio/music/stingers/child_hum.ogg"
const START_HP := 0.30
const FULL_HP := 0.05
## 每秒出血量達到此值時，失血效果最強（斷一條手臂約 1.5／秒）。
const BLEED_FULL := 3.0
## 部位 HP 低於此比例才開始影響畫面。
const PART_START := 0.7
## 心臟 HP 比例低於此值時，剪影與哼聲才會出現。
const HEART_GHOST := 0.35
const BPM := Vector2(66.0, 150.0)
const SEW_SECONDS := 1.6
const GHOST_SECONDS := 0.09
const GHOST_COOLDOWN := 9.0
const GHOST_CHANCE := 0.15
const SETTINGS_PATH := "user://settings.cfg"

var player: CombatComponent
var flashes_enabled := true
var rng := RandomNumberGenerator.new()
var rect: ColorRect
var mat: ShaderMaterial
var heart_player: AudioStreamPlayer
var hum_player: AudioStreamPlayer
## 最近一次計算的效果值（測試與除錯用）。
var fx := {}
var beats := 0
var ghosts := 0
var _beat_left := 0.0
var _pulse := 0.0
var _ghost_left := 0.0
var _ghost_cd := 0.0
var _sew := -1.0

func _ready() -> void:
	layer = 0  # 3D 畫面之上、HUD（layer 1）之下
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	rect.visible = false
	add_child(rect)
	heart_player = _voice(HEARTBEAT)
	hum_player = _voice(CHILD_HUM)
	flashes_enabled = load_flashes_setting(SETTINGS_PATH)

func _voice(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Voice"  # 不被低血量的悶聲濾掉
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p

static func load_flashes_setting(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return true
	return bool(cfg.get_value("video", "injury_flashes", true))

static func save_flashes_setting(path: String, on: bool) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)  # 保留其他區段
	cfg.set_value("video", "injury_flashes", on)
	return cfg.save(path)

## HP 比例 → 0–1 強度（30% 以上為 0，5% 以下為 1）。
static func intensity_for(hp_ratio: float) -> float:
	return clampf((START_HP - hp_ratio) / (START_HP - FULL_HP), 0.0, 1.0)

## 單一部位的損傷程度：斷離或失效 = 1；HP 70% 以上 = 0。
static func part_loss(anat: AnatomyState, part_id: StringName) -> float:
	if anat == null:
		return 0.0
	var p := anat.get_part(part_id)
	if p == null:
		return 0.0
	if p.severed or not p.is_functional():
		return 1.0
	return clampf((PART_START - p.hp_ratio()) / PART_START, 0.0, 1.0)

## 由身體狀態算出所有效果值。純函式，方便測試。
static func compute(anat: AnatomyState, hp_ratio: float) -> Dictionary:
	var i := intensity_for(hp_ratio)
	var bleed := clampf(anat.total_bleed_rate() / BLEED_FULL, 0.0, 1.0) if anat != null else 0.0
	var heart := anat.get_part(&"heart") if anat != null else null
	var heart_ratio := heart.hp_ratio() if heart != null and not heart.severed else 1.0
	return {
		"intensity": i,
		"desat": clampf(bleed * 0.65 + i * 0.35, 0.0, 1.0),
		"eye_l": part_loss(anat, &"eye_l"),
		"eye_r": part_loss(anat, &"eye_r"),
		"wobble": part_loss(anat, &"head"),
		"double_vision": clampf((i - 0.6) / 0.4, 0.0, 1.0),
		"bpm": lerpf(BPM.x, BPM.y, i),
		"heart_ghost": heart_ratio < HEART_GHOST,
	}

func _anatomy() -> AnatomyState:
	return player.anatomy.state if player != null and player.anatomy != null else null

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		fx = compute(null, 1.0)
		_apply(0.0)
		return
	if player.is_dead() and _sew < 0.0:
		_sew = 0.0
	fx = compute(_anatomy(), player.pools.hp / maxf(1.0, player.pools.max_hp))
	if _sew >= 0.0:
		_sew = minf(1.0, _sew + delta / SEW_SECONDS)
	_tick_heart(delta)
	_apply(delta)

func _tick_heart(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 5.0)
	_ghost_left = maxf(0.0, _ghost_left - delta)
	_ghost_cd = maxf(0.0, _ghost_cd - delta)
	var i: float = fx.intensity
	if (i <= 0.0 and not fx.heart_ghost) or _sew >= 0.0:
		_beat_left = 0.0
		return
	_beat_left -= delta
	if _beat_left > 0.0:
		return
	_beat_left = 60.0 / float(fx.bpm)
	beats += 1
	_pulse = 1.0
	if heart_player.stream != null:
		heart_player.volume_db = linear_to_db(lerpf(0.25, 1.0, maxf(i, 0.3)))
		heart_player.play()
	if fx.heart_ghost and _ghost_cd <= 0.0 and rng.randf() < GHOST_CHANCE:
		_ghost_cd = GHOST_COOLDOWN
		ghosts += 1
		if hum_player.stream != null:
			hum_player.play()
		if flashes_enabled:
			_ghost_left = GHOST_SECONDS
			mat.set_shader_parameter(&"ghost_pos", Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.45, 0.65)))

## 把效果值交給 shader。全部為 0 時隱藏，避免多一次全螢幕處理。
func _apply(_delta: float) -> void:
	var sew := maxf(0.0, _sew)
	var dv: float = fx.get("double_vision", 0.0) if flashes_enabled else 0.0
	var params := {
		&"intensity": fx.get("intensity", 0.0),
		&"pulse": _pulse,
		&"desat": fx.get("desat", 0.0),
		&"eye_l": fx.get("eye_l", 0.0),
		&"eye_r": fx.get("eye_r", 0.0),
		&"wobble": fx.get("wobble", 0.0),
		&"double_vision": dv,
		&"sew": sew,
		&"ghost": 1.0 if _ghost_left > 0.0 else 0.0,
	}
	var any := false
	for k in params:
		mat.set_shader_parameter(k, params[k])
		if float(params[k]) > 0.0 and k != &"pulse":
			any = true
	var vp := get_viewport()
	if vp != null:
		var s := vp.get_visible_rect().size
		mat.set_shader_parameter(&"aspect", s.x / maxf(1.0, s.y))
	rect.visible = any

## 目前縫合進度（-1 = 沒有死亡）。
func sew_progress() -> float:
	return _sew

## 重生／換場時清除。
func reset() -> void:
	_sew = -1.0
	_pulse = 0.0
	_ghost_left = 0.0
	_beat_left = 0.0
