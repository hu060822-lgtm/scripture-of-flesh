class_name CreatureAnimationLibrary
extends RefCounted
## 【程序生成動畫】依 AnatomyProfile 產生 AnimationLibrary。任何身體模板（人形、多手人、行走的母親…）
## 都由部位的功能（arm／leg／tether…）與靜止位置推導出動作，不需要每種生物手工做一套。
##
## 慣例（見 PlaceholderBodyBuilder.part_frames）：
##   骨骼原點在關節，靜止姿勢沒有旋轉，所以「姿勢」就是每根骨骼的旋轉。
##   pitch（前擺）：肢體末端往角色前方（-Z）轉；軀幹／頭往前傾。
##   side（外展）：肢體末端往身體外側轉（先套用）。負值為往身體內側（橫過身前）。
##   twist：繞肢體本身的方向扭轉；軀幹為繞 Y 軸轉身（正值往左）。
##   "$pos"／"$rot"：整個 Skeleton 節點的位移與旋轉（爬行、倒地、撲擊等全身動作），旋轉正值往後倒。
##
## 片段：
##   循環：idle、walk、limp、crawl、crawl_idle、block
##   反應：hit、stagger、sever、dodge、death
##   攻擊：<風格>_windup／_active／_recovery，長度 1 秒，由 CreatureAnimator 依攻擊資料的
##        前搖／判定／收招秒數縮放，畫面與命中時序完全同步。單臂風格另以手臂區分：<風格>@<arm_id>_<階段>。
##   姿態變體：<片段>~prone（倒地／爬行：失去雙腿時）、<片段>~kneel（Boss 跪伏後）。
##        反應與攻擊都有變體，倒在地上的身體會「在地上」受擊、出手，不會先站起來。
## 動畫以 linear 內插，播放端（CreatureAnimator）以 12fps 逐格推進，保留 PS1 低幀數的頓挫感。

const SKELETON_PATH := "Body/Skeleton"
const PHASES := ["windup", "active", "recovery"]
## 姿態：倒地（爬行）與跪伏。
const PRONE := &"prone"
const KNEEL := &"kneel"
## 有姿態變體的基本片段（爬行狀態本身就是趴姿，不需要變體）。
const PRONE_CLIPS := [&"hit", &"stagger", &"sever", &"dodge"]  # death~prone 另外手工設計
const KNEEL_CLIPS := [&"idle", &"walk", &"limp", &"block", &"hit", &"stagger", &"sever", &"dodge", &"death"]

static var _cache := {}

## 每個 profile 一份（同一種生物共用）。攻擊片段在第一次需要時才產生並加入。
static func for_profile(profile: AnatomyProfile) -> AnimationLibrary:
	var key := "%s#%d" % [profile.id, profile.parts.size()]
	if _cache.has(key):
		return _cache[key]
	var lib := AnimationLibrary.new()
	var b := new(profile)
	for clip in b.base_clips():
		lib.add_animation(clip[0], clip[1])
	_cache[key] = lib
	return lib

## 攻擊片段名稱。arm_id 為空代表全身風格；posture 為空代表站姿。
static func attack_clip_name(style: StringName, arm_id: StringName, phase: String, posture: StringName = &"") -> StringName:
	var base := "%s_%s" % [style, phase] if arm_id == &"" else "%s@%s_%s" % [style, arm_id, phase]
	return posture_clip(StringName(base), posture)

## 片段的姿態變體名稱。
static func posture_clip(clip: StringName, posture: StringName) -> StringName:
	if posture == &"":
		return clip
	return StringName("%s~%s" % [clip, posture])

## 確保攻擊片段存在（三個階段）。回傳 false 代表這個身體無法產生該風格（例如沒有手臂的單臂風格）。
static func ensure_attack(profile: AnatomyProfile, style: StringName, arm_id: StringName, posture: StringName = &"") -> bool:
	var lib := for_profile(profile)
	if lib.has_animation(attack_clip_name(style, arm_id, "windup", posture)):
		return true
	var b := new(profile)
	var clips := b.attack_clips(style, arm_id, posture)
	if clips.is_empty():
		return false
	for clip in clips:
		lib.add_animation(clip[0], clip[1])
	return true

# ---------- 身體結構推導 ----------

var profile: AnatomyProfile
var frames := {}
var root_id: StringName
var arms: Array[StringName] = []
var legs: Array[StringName] = []
var cradles: Array[StringName] = []
var cords: Array[StringName] = []
var stalks: Array[StringName] = []
var heads: Array[StringName] = []   # head
var necks: Array[StringName] = []
var jaw: StringName = &""
var abdomen: StringName = &""
var womb: StringName = &""

func _init(p: AnatomyProfile) -> void:
	profile = p
	frames = PlaceholderBodyBuilder.part_frames(p)
	for d in p.parts:
		if d.is_internal:
			continue
		var s := AnatomyTypes.base_part_id(d.id)  # 連體生物：head_a、neck_b… 視為 head、neck
		if d.parent_id == &"":
			root_id = d.id
		elif d.functions.has("cradle"):
			cradles.append(d.id)
		elif d.functions.has("arm"):
			arms.append(d.id)
		elif d.functions.has("leg"):
			legs.append(d.id)
		elif d.functions.has("tether"):
			cords.append(d.id)
		elif s.begins_with("stalk"):
			stalks.append(d.id)
		elif s == "head":
			heads.append(d.id)
		elif s == "neck":
			necks.append(d.id)
		elif s == "jaw":
			if jaw == &"":
				jaw = d.id
		elif s == "abdomen":
			abdomen = d.id
		elif s == "womb":
			womb = d.id

func _dir(id: StringName) -> Vector3:
	var f: Dictionary = frames[id]
	var d: Vector3 = f["center"] - f["pivot"]
	return d.normalized() if d.length() > 0.001 else Vector3.UP

## 身體左右：+X 為左（arm_l 在 +X）。
func _side_sign(id: StringName) -> float:
	var x: float = frames[id]["center"].x
	return 1.0 if x > 0.01 else (-1.0 if x < -0.01 else 0.0)

func _is_left(id: StringName) -> bool:
	return _side_sign(id) > 0.0

func _rotation(id: StringName, pose: Vector3) -> Quaternion:
	var pitch := deg_to_rad(pose.x)
	var side := deg_to_rad(pose.y)
	var twist := deg_to_rad(pose.z)
	if id == root_id:
		# 軀幹：前傾（繞 -X）、側傾（繞 Z，正值往左）、轉身（繞 Y）
		return Quaternion(Vector3.UP, twist) * Quaternion(Vector3.BACK, -side) * Quaternion(Vector3.LEFT, pitch)
	var d := _dir(id)
	var fwd_axis := d.cross(Vector3.FORWARD)
	if fwd_axis.length() < 0.01:
		fwd_axis = Vector3.RIGHT  # 肢體本身朝前（極少見）
	var out := Vector3.RIGHT * (_side_sign(id) if _side_sign(id) != 0.0 else 1.0)
	var side_axis := d.cross(out)
	if side_axis.length() < 0.01:
		side_axis = Vector3.BACK
	# 先外展（side）再前擺（pitch）：手臂先抬到側面，再往前／往上揮，水平橫掃與高舉都能表達
	return Quaternion(fwd_axis.normalized(), pitch) * Quaternion(side_axis.normalized(), side) * Quaternion(d, twist)

func _lower_anchor() -> StringName:
	if abdomen != &"" and profile.get_part(abdomen).parent_id == root_id:
		return abdomen
	if womb != &"" and profile.get_part(womb).parent_id == root_id:
		return womb
	return &""

func _bone(id: StringName) -> String:
	return String(profile.get_part(id).bone_name)

# ---------- 片段建立 ----------

## keys：Array of [time, pose Dictionary]。pose 未提到的骨骼回到靜止姿勢。
func _clip(length: float, loop: bool, keys: Array) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var used := {}
	var use_pos := false
	var use_rot := false
	for k in keys:
		for id in (k[1] as Dictionary):
			if id == "$pos":
				use_pos = true
			elif id == "$rot":
				use_rot = true
			else:
				used[id] = true
	# 下半身錨點（腹部／子宮）抵消軀幹的旋轉，讓上半身轉身、前傾時腿不會跟著轉
	var anchor := _lower_anchor()
	if used.has(root_id) and anchor != &"":
		used[anchor] = true
	for id in used:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("%s:%s" % [SKELETON_PATH, _bone(id)]))
		for k in keys:
			var pose: Dictionary = k[1]
			var q := _rotation(id, pose.get(id, Vector3.ZERO))
			if id == anchor and pose.has(root_id):
				q = _rotation(root_id, pose[root_id]).inverse() * q
			a.rotation_track_insert_key(t, k[0], q)
	if use_pos:
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath(SKELETON_PATH))
		for k in keys:
			a.position_track_insert_key(t, k[0], (k[1] as Dictionary).get("$pos", Vector3.ZERO))
	if use_rot:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath(SKELETON_PATH))
		for k in keys:
			var r: Vector3 = (k[1] as Dictionary).get("$rot", Vector3.ZERO)
			a.rotation_track_insert_key(t, k[0], Quaternion.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))))
	return a

## 把多個姿勢合併（後者覆蓋／相加）。
static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = (out.get(k, Vector3.ZERO) as Vector3) + (b[k] as Vector3)
	return out

## 循環步態：在 n 個關鍵格上取樣 f(phase 0..1)。
func _cycle(length: float, n: int, f: Callable) -> Animation:
	return _clip(length, true, _cycle_keys(length, n, f))

func _cycle_keys(length: float, n: int, f: Callable) -> Array:
	var keys := []
	for i in n + 1:
		var t := float(i) / float(n)
		keys.append([t * length, f.call(t)])
	return keys

# ---------- 姿態變體 ----------

## 把站姿的關鍵格轉成某姿態。attack：這些關鍵格是攻擊的蓄力／出手姿勢（手臂維持出手方向）。
func _posture_keys(keys: Array, posture: StringName, attack: bool = false) -> Array:
	var out := []
	for k in keys:
		out.append([k[0], _posture_pose(k[1], posture, attack)])
	return out

func _posture_pose(pose: Dictionary, posture: StringName, attack: bool) -> Dictionary:
	if posture == PRONE:
		return _prone_pose(pose, attack)
	if posture == KNEEL:
		return _kneel_pose(pose)
	return pose

## 倒地姿態：整個骨架趴下（與 crawl 相同的 $rot／$pos），手臂以爬行的前伸姿勢為基準，
## 頭抬起看前方，腿拖在後面。攻擊時出手的手臂換算成「趴著時」的角度：趴下讓身體前傾 72 度，
## 所以手臂相對角度加 72 才會指向原本的世界方向（再限制在不穿進地面的範圍）。
func _prone_pose(pose: Dictionary, attack: bool) -> Dictionary:
	var out := {}
	for id in pose:
		if id is StringName:
			out[id] = pose[id]
	for a in arms:
		var v: Vector3 = pose.get(a, Vector3.ZERO)
		if attack and pose.has(a):
			out[a] = Vector3(clampf(72.0 + v.x, 110.0, 235.0), v.y, v.z)
		else:
			out[a] = Vector3(150.0 + v.x * 0.35, 15.0 + v.y * 0.5, v.z)
	for h in heads:
		out[h] = Vector3(-35.0, 0, 0) + (pose.get(h, Vector3.ZERO) as Vector3) * 0.5
	for l in legs:
		out[l] = Vector3(-5.0 + (pose.get(l, Vector3.ZERO) as Vector3).x * 0.15, 0, 0)
	if root_id != &"" and pose.has(root_id):
		var r: Vector3 = pose[root_id]
		out[root_id] = Vector3(r.x * 0.3, r.y * 0.5, r.z)
	var rot: Vector3 = pose.get("$rot", Vector3.ZERO)
	var pos: Vector3 = pose.get("$pos", Vector3.ZERO)
	out["$rot"] = Vector3(-72.0, 0, 0) + rot * 0.25
	out["$pos"] = _prone_offset() + Vector3(pos.x, clampf(pos.y * 0.3, -0.03, 0.1), pos.z)
	return out

## 跪伏姿態（Boss 第二階段）：身體已由 BossPhaseComponent 降低，這裡只維持前傾、低頭，
## 出手與受擊時軀幹不會回到直立。
func _kneel_pose(pose: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	if root_id != &"":
		out[root_id] = (pose.get(root_id, Vector3.ZERO) as Vector3) + Vector3(22.0, 0, 0)
	for h in heads:
		out[h] = (pose.get(h, Vector3.ZERO) as Vector3) + Vector3(12.0, 0, 0)
	return out

## 加入片段與它的姿態變體。
func _add_clip(out: Array, name: StringName, length: float, loop: bool, keys: Array) -> void:
	out.append([name, _clip(length, loop, keys)])
	if name in PRONE_CLIPS:
		out.append([posture_clip(name, PRONE), _clip(length, loop, _posture_keys(keys, PRONE))])
	if name in KNEEL_CLIPS:
		out.append([posture_clip(name, KNEEL), _clip(length, loop, _posture_keys(keys, KNEEL))])

func _leg_phase(id: StringName) -> float:
	var c: Vector3 = frames[id]["center"]
	var ph := 0.0 if c.x > 0.0 else 0.5
	if absf(c.z) > 0.05 and c.z > 0.0:
		ph += 0.5  # 前後腳對角交替（行走的母親的高蹺）
	return ph

func _sway(pose: Dictionary, t: float, amount: float) -> void:
	for i in cords.size():
		pose[cords[i]] = Vector3(sin(TAU * (t + i * 0.3)) * amount, cos(TAU * (t + i * 0.2)) * amount * 0.6, 0)
	for i in stalks.size():
		pose[stalks[i]] = Vector3(sin(TAU * (t + i * 0.25)) * amount * 0.8, sin(TAU * (t * 2.0 + i * 0.4)) * amount * 0.5, 0)

func base_clips() -> Array:
	var out := []
	_add_clip(out, &"idle", 2.0, true, _cycle_keys(2.0, 8, func(t):
		var p := {}
		if root_id != &"": p[root_id] = Vector3(sin(TAU * t) * 2.0, 0, 0)
		for h in heads: p[h] = Vector3(-sin(TAU * t) * 2.0, 0, sin(TAU * t * 0.5) * 3.0)
		for a in arms: p[a] = Vector3(sin(TAU * t) * 2.0, 4.0 + sin(TAU * t) * 1.5, 0)
		for c in cradles: p[c] = Vector3(35.0 + sin(TAU * t) * 3.0, -10.0, 0)
		if jaw != &"": p[jaw] = Vector3(maxf(0.0, sin(TAU * t)) * 4.0, 0, 0)
		_sway(p, t, 4.0)
		return p))
	_add_clip(out, &"walk", 1.0, true, _cycle_keys(1.0, 8, func(t):
		var p := {}
		if root_id != &"": p[root_id] = Vector3(4.0, 0, sin(TAU * t) * 5.0)
		if abdomen != &"": p[abdomen] = Vector3(-3.0, 0, -sin(TAU * t) * 5.0)
		for l in legs: p[l] = Vector3(sin(TAU * (t + _leg_phase(l))) * 26.0, 0, 0)
		for a in arms:
			var ph := 0.5 if _is_left(a) else 0.0
			p[a] = Vector3(sin(TAU * (t + ph)) * 20.0, 5.0, 0)
		for c in cradles: p[c] = Vector3(35.0, -10.0, 0)
		for h in heads: p[h] = Vector3(2.0, 0, -sin(TAU * t) * 3.0)
		_sway(p, t, 10.0)
		var bob := absf(sin(TAU * t)) * 0.03
		p["$pos"] = Vector3(0, bob, 0)
		return p))
	# 單腳：拖行跛步，身體往剩下的腿傾斜並上下頓挫
	_add_clip(out, &"limp", 1.3, true, _cycle_keys(1.3, 8, func(t):
		var p := {}
		var hop := maxf(0.0, sin(TAU * t))
		if root_id != &"": p[root_id] = Vector3(10.0, sin(TAU * t) * 8.0, 0)
		for l in legs: p[l] = Vector3(sin(TAU * t) * 18.0, 0, 0)
		for a in arms: p[a] = Vector3(10.0 + hop * 15.0, 20.0 * hop, 0)
		for h in heads: p[h] = Vector3(8.0, 0, sin(TAU * t) * 6.0)
		_sway(p, t, 12.0)
		p["$pos"] = Vector3(0, -0.04 - hop * 0.06, 0)
		return p))
	# 爬行：整個骨架往前倒成趴姿，手臂輪流往前拉
	var prone := Vector3(-72.0, 0, 0)
	var prone_pos := _prone_offset()
	out.append([&"crawl", _cycle(1.6, 8, func(t):
		var p := {}
		for a in arms:
			var ph := 0.5 if _is_left(a) else 0.0
			p[a] = Vector3(145.0 + sin(TAU * (t + ph)) * 30.0, 15.0, 0)
		for h in heads: p[h] = Vector3(-35.0, 0, sin(TAU * t) * 6.0)
		for l in legs: p[l] = Vector3(-5.0 + sin(TAU * t) * 6.0, 0, 0)
		if root_id != &"": p[root_id] = Vector3(0, 0, sin(TAU * t) * 6.0)
		_sway(p, t, 8.0)
		p["$rot"] = prone
		p["$pos"] = prone_pos + Vector3(0, absf(sin(TAU * t)) * 0.02, 0)
		return p)])
	out.append([&"crawl_idle", _cycle(2.0, 4, func(t):
		var p := {}
		for a in arms: p[a] = Vector3(150.0, 15.0, 0)
		for h in heads: p[h] = Vector3(-35.0 + sin(TAU * t) * 3.0, 0, 0)
		_sway(p, t, 4.0)
		p["$rot"] = prone
		p["$pos"] = prone_pos
		return p)])
	_add_clip(out, &"block", 0.5, true, [[0.0, _block_pose()], [0.5, _block_pose()]])
	var neutral := {}
	# 受擊：第一格就到位（12fps 下不會有「慢慢彎下去」的軟感），頭被打得往後甩、
	# 軀幹扭開、手臂甩開，整個骨架被往後推，再分兩段回來。
	var flinch := {}
	if root_id != &"": flinch[root_id] = Vector3(-20.0, 6.0, 14.0)
	for h in heads: flinch[h] = Vector3(-32.0, 0, -12.0)
	for n in necks: flinch[n] = Vector3(-14.0, 0, 0)
	for a in arms: flinch[a] = Vector3(-18.0, 34.0, 0)
	for c in cradles: flinch[c] = Vector3(20.0, 25.0, 0)
	if jaw != &"": flinch[jaw] = Vector3(22.0, 0, 0)
	for l in legs: flinch[l] = Vector3(-8.0 if _is_left(l) else 6.0, 0, 0)
	flinch["$pos"] = Vector3(0, -0.04, 0.12)
	var flinch_half := {}
	for k in flinch:
		flinch_half[k] = (flinch[k] as Vector3) * 0.45
	_add_clip(out, &"hit", 0.35, false, [[0.0, neutral], [0.03, flinch], [0.12, flinch], [0.22, flinch_half], [0.35, neutral]])
	# 硬直：先被打得後仰，接著膝蓋一軟、彎腰抱住身體往下沉，最後才站穩
	var reel := flinch.duplicate()
	if root_id != &"": reel[root_id] = Vector3(-26.0, 10.0, 16.0)
	for a in arms: reel[a] = Vector3(-30.0, 50.0, 0)
	for l in legs: reel[l] = Vector3(-16.0 if _is_left(l) else 12.0, 0, 0)
	reel["$pos"] = Vector3(0, -0.06, 0.2)
	var buckle := {}
	if root_id != &"": buckle[root_id] = Vector3(34.0, -6.0, -10.0)
	for h in heads: buckle[h] = Vector3(24.0, 0, 18.0)
	for n in necks: buckle[n] = Vector3(10.0, 0, 0)
	for a in arms: buckle[a] = Vector3(40.0, -22.0, 0)
	for c in cradles: buckle[c] = Vector3(60.0, -20.0, 0)
	if jaw != &"": buckle[jaw] = Vector3(15.0, 0, 0)
	for l in legs: buckle[l] = Vector3(38.0 if _is_left(l) else 18.0, 0, 0)
	buckle["$pos"] = Vector3(0, -0.2, 0.24)
	_add_clip(out, &"stagger", 1.0, false, [[0.0, neutral], [0.06, reel], [0.22, reel], [0.4, buckle], [0.8, buckle], [1.0, neutral]])
	# 斷肢：劇烈後仰、手臂亂揮（失去的部位骨骼已縮為零，不受影響）
	var shock := {}
	if root_id != &"": shock[root_id] = Vector3(-25.0, 12.0, -20.0)
	for h in heads: shock[h] = Vector3(-35.0, 0, 15.0)
	for a in arms: shock[a] = Vector3(40.0, 55.0, 0)
	if jaw != &"": shock[jaw] = Vector3(30.0, 0, 0)
	shock["$pos"] = Vector3(0, -0.08, 0.15)
	var shock2 := shock.duplicate()
	for a in arms: shock2[a] = Vector3(-20.0, 30.0, 0)
	_add_clip(out, &"sever", 0.6, false, [[0.0, neutral], [0.05, shock], [0.3, shock2], [0.6, neutral]])
	var duck := {}
	if root_id != &"": duck[root_id] = Vector3(30.0, 0, 0)
	for l in legs: duck[l] = Vector3(45.0 if _is_left(l) else -25.0, 0, 0)
	for a in arms: duck[a] = Vector3(30.0, 25.0, 0)
	for h in heads: duck[h] = Vector3(15.0, 0, 0)
	duck["$pos"] = Vector3(0, -0.3, 0)
	_add_clip(out, &"dodge", 1.0, false, [[0.0, neutral], [0.2, duck], [0.7, duck], [1.0, neutral]])
	# 登場（Boss）：從蜷伏中站起、仰頭張口尖叫。劇本演出用（CreatureAnimator.play_override）。
	var curl := {"$pos": Vector3(0, -_height() * 0.25, 0)}
	if root_id != &"": curl[root_id] = Vector3(45.0, 0, 0)
	for h in heads: curl[h] = Vector3(30.0, 0, 0)
	for a in arms + cradles: curl[a] = Vector3(60.0, -20.0, 0)
	for l in legs: curl[l] = Vector3(-10.0, 0, 0)
	var rise := {"$pos": Vector3.ZERO}
	if root_id != &"": rise[root_id] = Vector3(-15.0, 0, 0)
	for h in heads: rise[h] = Vector3(-45.0, 0, 0)
	for a in arms + cradles: rise[a] = Vector3(40.0, 70.0, 0)
	if jaw != &"": rise[jaw] = Vector3(55.0, 0, 0)
	_sway(rise, 0.5, 18.0)
	var settle := rise.duplicate()
	for h in heads: settle[h] = Vector3(-10.0, 0, 0)
	for a in arms + cradles: settle[a] = Vector3(10.0, 15.0, 0)
	out.append([&"intro", _clip(3.0, false, [[0.0, curl], [0.8, curl], [1.8, rise], [2.6, rise], [3.0, settle]])])
	# 跪伏（Boss 第二階段）：失去支撐後前傾、手撐地
	var slump := {}
	if root_id != &"": slump[root_id] = Vector3(25.0, 10.0, 0)
	for h in heads: slump[h] = Vector3(20.0, 0, 15.0)
	for a in arms: slump[a] = Vector3(35.0, 25.0, 0)
	for c in cradles: slump[c] = Vector3(70.0, -10.0, 0)
	out.append([&"kneel", _clip(1.0, false, [[0.0, neutral], [0.25, shock], [0.6, slump], [1.0, slump]])])
	out.append_array(chase_clips(neutral))
	# 死亡：往後倒地（整個骨架旋轉，受擊區域與網格一起倒下），停在最後一格
	var fall := {}
	for h in heads: fall[h] = Vector3(-30.0, 0, 20.0)
	for a in arms: fall[a] = Vector3(-30.0, 60.0, 0)
	for l in legs: fall[l] = Vector3(15.0 if _is_left(l) else 5.0, 8.0, 0)
	if jaw != &"": fall[jaw] = Vector3(25.0, 0, 0)
	_sway(fall, 0.25, 20.0)
	var mid := fall.duplicate()
	mid["$rot"] = Vector3(35.0, 0, 0)
	mid["$pos"] = Vector3(0, -0.1, 0.1)
	var end := fall.duplicate()
	end["$rot"] = Vector3(84.0, 0, 6.0)
	end["$pos"] = Vector3(0, _height() * 0.08, 0.15)
	var start := {"$rot": Vector3.ZERO, "$pos": Vector3.ZERO}
	_add_clip(out, &"death", 1.0, false, [[0.0, start], [0.35, mid], [0.75, end], [1.0, end]])
	# 倒地中死亡：已經趴著，不會先站起來再往後倒 —— 抽搐一下後完全攤平
	var flat := {}
	for a in arms: flat[a] = Vector3(165.0, 50.0, 0)
	for h in heads: flat[h] = Vector3(10.0, 0, 30.0)
	for l in legs: flat[l] = Vector3(-8.0, 6.0, 0)
	if jaw != &"": flat[jaw] = Vector3(25.0, 0, 0)
	_sway(flat, 0.25, 20.0)
	flat["$rot"] = Vector3(-86.0, 0, 8.0)
	flat["$pos"] = _prone_offset() + Vector3(0, -_height() * 0.02, 0)
	var twitch := _prone_pose({}, false)
	for a in arms: twitch[a] = Vector3(120.0, 40.0, 0)
	for h in heads: twitch[h] = Vector3(-50.0, 0, 0)
	if jaw != &"": twitch[jaw] = Vector3(35.0, 0, 0)
	var prone_start := _prone_pose({}, false)
	for id in flat:
		if not prone_start.has(id): prone_start[id] = Vector3.ZERO
		if not twitch.has(id): twitch[id] = Vector3.ZERO
	out.append([posture_clip(&"death", PRONE), _clip(1.0, false, [[0.0, prone_start], [0.2, twitch], [0.6, flat], [1.0, flat]])])
	return out

## 追逐戰（MotherChase，劇本演出用 play_override）：
##   chase_run    前傾到幾乎四肢著地的狂奔，手臂輪流往前抓地，頭歪成不自然的角度（短循環，12fps 下很抽）
##   lunge_windup 往後仰、雙臂大張高舉、嘴張開（撲擊預備；也用於破牆的那一刻）
##   lunge        整個人往前撲出，雙臂直直伸向前方
##   grab_hold    彎身抓住獵物，手臂收在身前，頭左右抽動
func chase_clips(neutral: Dictionary) -> Array:
	var out := []
	var h := _height()
	out.append([&"chase_run", _cycle(0.5, 6, func(t):
		var p := {}
		if root_id != &"": p[root_id] = Vector3(52.0, sin(TAU * t) * 6.0, sin(TAU * t) * 10.0)
		if abdomen != &"": p[abdomen] = Vector3(-20.0, 0, -sin(TAU * t) * 8.0)
		for hd in heads: p[hd] = Vector3(-42.0, 18.0, 62.0 + sin(TAU * t * 2.0) * 14.0)
		for a in arms:
			var ph := 0.5 if _is_left(a) else 0.0
			p[a] = Vector3(118.0 + sin(TAU * (t + ph)) * 48.0, 22.0, 0)
		for c in cradles: p[c] = Vector3(55.0, -15.0, 0)
		for l in legs: p[l] = Vector3(sin(TAU * (t + _leg_phase(l))) * 36.0, 0, 0)
		if jaw != &"": p[jaw] = Vector3(25.0 + maxf(0.0, sin(TAU * t)) * 20.0, 0, 0)
		_sway(p, t, 22.0)
		p["$pos"] = Vector3(0, -h * 0.12 + absf(sin(TAU * t)) * 0.06, 0)
		return p)])
	var rear := {"$pos": Vector3(0, 0.08, 0.2)}
	if root_id != &"": rear[root_id] = Vector3(-22.0, 0, 0)
	for hd in heads: rear[hd] = Vector3(-50.0, 0, 38.0)
	for a in arms: rear[a] = Vector3(150.0, 70.0, 0)
	for c in cradles: rear[c] = Vector3(20.0, 30.0, 0)
	if jaw != &"": rear[jaw] = Vector3(60.0, 0, 0)
	_sway(rear, 0.3, 20.0)
	out.append([&"lunge_windup", _clip(0.5, false, [[0.0, neutral], [0.3, rear], [0.5, rear]])])
	var throw := {"$pos": Vector3(0, -h * 0.15, -0.4)}
	if root_id != &"": throw[root_id] = Vector3(70.0, 0, 0)
	for hd in heads: throw[hd] = Vector3(-60.0, 0, 20.0)
	for a in arms: throw[a] = Vector3(95.0, 10.0, 0)
	for c in cradles: throw[c] = Vector3(80.0, 10.0, 0)
	if jaw != &"": throw[jaw] = Vector3(70.0, 0, 0)
	_sway(throw, 0.7, 25.0)
	out.append([&"lunge", _clip(0.35, false, [[0.0, rear], [0.12, throw], [0.35, throw]])])
	out.append([&"grab_hold", _cycle(0.8, 4, func(t):
		var p := {"$pos": Vector3(0, -0.1, 0)}
		if root_id != &"": p[root_id] = Vector3(45.0, 0, sin(TAU * t) * 6.0)
		for hd in heads: p[hd] = Vector3(-30.0, 0, sin(TAU * t * 2.0) * 25.0)
		for a in arms: p[a] = Vector3(80.0, -15.0, 0)
		for c in cradles: p[c] = Vector3(60.0, -25.0, 0)
		if jaw != &"": p[jaw] = Vector3(40.0 + sin(TAU * t) * 20.0, 0, 0)
		_sway(p, t, 10.0)
		return p)])
	return out

func _block_pose() -> Dictionary:
	var p := {}
	for a in arms: p[a] = Vector3(85.0, -25.0, 0)
	for c in cradles: p[c] = Vector3(60.0, -30.0, 0)
	if root_id != &"": p[root_id] = Vector3(8.0, 0, 0)
	for h in heads: p[h] = Vector3(15.0, 0, 0)
	p["$pos"] = Vector3(0, -0.05, 0)
	return p

func _height() -> float:
	var top := 0.0
	for id in frames:
		top = maxf(top, (frames[id]["center"] as Vector3).y)
	return top

## 趴下後讓身體大致位於原本站立的位置（而不是整個往前伸出去）。
func _prone_offset() -> Vector3:
	var h := _height()
	return Vector3(0, -h * 0.05, h * 0.5)

# ---------- 攻擊 ----------

## 回傳 [[name, Animation] x3]；這個身體做不到該風格時回傳空陣列。
func attack_clips(style: StringName, arm_id: StringName, posture: StringName = &"") -> Array:
	var poses := _attack_poses(style, arm_id)
	if poses.is_empty():
		return []
	var ready: Dictionary = poses[0]
	var strike: Dictionary = poses[1]
	var neutral := {}
	# 每個姿勢都要列出相同的骨骼，否則沒列到的骨骼在片段之間會跳回靜止姿勢
	for k in ready.keys() + strike.keys():
		neutral[k] = Vector3.ZERO
	var r := _merge(neutral, ready)
	var s := _merge(neutral, strike)
	var over := _merge(r, {})
	for k in r:
		over[k] = (r[k] as Vector3) * 1.08  # 前搖最後再多拉一點（蓄力感）
	if posture != &"":
		neutral = _posture_pose(neutral, posture, false)
		r = _posture_pose(r, posture, true)
		over = _posture_pose(over, posture, true)
		s = _posture_pose(s, posture, true)
	# 出手：前 25% 就打到定位（快、狠），停在出手姿勢讓命中那一刻看得清楚
	return [
		[attack_clip_name(style, arm_id, "windup", posture), _clip(1.0, false, [[0.0, neutral], [0.6, r], [1.0, over]])],
		[attack_clip_name(style, arm_id, "active", posture), _clip(1.0, false, [[0.0, over], [0.25, s], [1.0, s]])],
		[attack_clip_name(style, arm_id, "recovery", posture), _clip(1.0, false, [[0.0, s], [0.3, s], [1.0, neutral]])],
	]

## [蓄力姿勢, 出手姿勢]
func _attack_poses(style: StringName, arm_id: StringName) -> Array:
	var r := {}
	var s := {}
	var tw := 1.0  # 轉身方向：右手出手時軀幹往右轉（負值）
	if arm_id != &"":
		if not frames.has(arm_id):
			return []
		tw = 1.0 if _is_left(arm_id) else -1.0
	match style:
		&"slash":
			r = {arm_id: Vector3(95.0, 70.0, 0), root_id: Vector3(0, 0, 30.0 * tw)}
			s = {arm_id: Vector3(75.0, -45.0, 0), root_id: Vector3(10.0, 0, -35.0 * tw)}
		&"overhead":
			r = {arm_id: Vector3(170.0, 10.0, 0), root_id: Vector3(-12.0, 0, 10.0 * tw)}
			s = {arm_id: Vector3(55.0, 0, 0), root_id: Vector3(22.0, 0, -5.0 * tw)}
			_add_heads(r, -10.0); _add_heads(s, 15.0)
		&"thrust":
			r = {arm_id: Vector3(35.0, 10.0, 0), root_id: Vector3(-5.0, 0, 25.0 * tw)}
			s = {arm_id: Vector3(90.0, -8.0, 0), root_id: Vector3(15.0, 0, -20.0 * tw)}
		&"punch":
			r = {arm_id: Vector3(40.0, 25.0, 0), root_id: Vector3(0, 0, 25.0 * tw)}
			s = {arm_id: Vector3(92.0, -5.0, 0), root_id: Vector3(10.0, 0, -25.0 * tw)}
		&"claw":
			r = {arm_id: Vector3(150.0, 40.0, 0), root_id: Vector3(-8.0, 0, 20.0 * tw)}
			s = {arm_id: Vector3(45.0, -30.0, 0), root_id: Vector3(20.0, 0, -25.0 * tw)}
		&"lash":
			r = {arm_id: Vector3(-40.0, 60.0, 0), root_id: Vector3(-5.0, 0, 35.0 * tw)}
			s = {arm_id: Vector3(80.0, -30.0, 0), root_id: Vector3(15.0, 0, -35.0 * tw)}
		&"grasp":
			r = {arm_id: Vector3(110.0, 15.0, 0)}
			s = {arm_id: Vector3(70.0, -10.0, 0)}
		&"overhead_two", &"grab", &"flurry":
			if arms.is_empty():
				return []
			for a in arms:
				var i := arms.find(a)
				match style:
					&"overhead_two":
						r[a] = Vector3(165.0, -15.0, 0)
						s[a] = Vector3(50.0, -20.0, 0)
					&"grab":
						r[a] = Vector3(85.0, 45.0, 0)
						s[a] = Vector3(85.0, -20.0, 0)
					_:
						# 多手亂擊：手臂交錯，一半往上一半往前
						r[a] = Vector3(150.0 if i % 2 == 0 else 30.0, 30.0, 0)
						s[a] = Vector3(40.0 if i % 2 == 0 else 120.0, -20.0, 0)
			r[root_id] = Vector3(-10.0, 0, 0)
			s[root_id] = Vector3(20.0, 0, 0)
		&"thrust_lunge", &"lunge", &"pounce":
			for a in arms:
				r[a] = Vector3(30.0, 30.0, 0)
				s[a] = Vector3(100.0, 5.0, 0)
			for l in legs:
				r[l] = Vector3(35.0 if _is_left(l) else -20.0, 0, 0)
				s[l] = Vector3(-30.0 if _is_left(l) else 40.0, 0, 0)
			r[root_id] = Vector3(25.0, 0, 0)
			s[root_id] = Vector3(30.0, 0, 0)
			r["$pos"] = Vector3(0, -0.25, 0.1)
			s["$pos"] = Vector3(0, 0.05, -0.35)
			s["$rot"] = Vector3(-18.0, 0, 0)
			if style == &"pounce" and jaw != &"":
				s[jaw] = Vector3(45.0, 0, 0)
				_add_heads(s, -20.0)
		&"kick", &"leap_kick", &"stomp":
			if legs.is_empty():
				return []
			var kicker := legs[0]
			for l in legs:
				if not _is_left(l):
					kicker = l
					break
			if style == &"stomp":
				r[kicker] = Vector3(55.0, 10.0, 0)
				s[kicker] = Vector3(-5.0, 0, 0)
				r[root_id] = Vector3(-6.0, 6.0, 0)
				s[root_id] = Vector3(10.0, 0, 0)
				s["$pos"] = Vector3(0, -0.12, 0)
			else:
				r[kicker] = Vector3(-30.0, 0, 0)
				s[kicker] = Vector3(85.0, 0, 0)
				r[root_id] = Vector3(10.0, 0, 0)
				s[root_id] = Vector3(-15.0, 0, 0)
				for a in arms:
					r[a] = Vector3(10.0, 30.0, 0)
					s[a] = Vector3(-15.0, 45.0, 0)
				if style == &"leap_kick":
					r["$pos"] = Vector3(0, -0.2, 0)
					s["$pos"] = Vector3(0, 0.5, -0.4)
		&"bite":
			if jaw == &"" and heads.is_empty():
				return []
			_add_heads(r, -20.0); _add_heads(s, 30.0)
			if jaw != &"":
				r[jaw] = Vector3(50.0, 0, 0)
				s[jaw] = Vector3(0, 0, 0)
			r[root_id] = Vector3(-5.0, 0, 0)
			s[root_id] = Vector3(25.0, 0, 0)
			s["$pos"] = Vector3(0, 0, -0.15)
		&"scream":
			_add_heads(r, 15.0); _add_heads(s, -40.0)
			if jaw != &"":
				s[jaw] = Vector3(60.0, 0, 0)
			for a in arms + cradles:
				r[a] = Vector3(20.0, 10.0, 0)
				s[a] = Vector3(30.0, 75.0, 0)
			r[root_id] = Vector3(15.0, 0, 0)
			s[root_id] = Vector3(-20.0, 0, 0)
		&"cradle":
			if cradles.is_empty():
				return []
			for c in cradles:
				r[c] = Vector3(70.0, 70.0, 0)
				s[c] = Vector3(75.0, -35.0, 0)
			r[root_id] = Vector3(-8.0, 0, 0)
			s[root_id] = Vector3(18.0, 0, 0)
		&"gaze":
			_add_heads(r, -8.0); _add_heads(s, 12.0)
			for i in stalks.size():
				r[stalks[i]] = Vector3(-15.0, (float(i) - 1.5) * 10.0, 0)
				s[stalks[i]] = Vector3(55.0, (float(i) - 1.5) * -6.0, 0)
			r[root_id] = Vector3(-6.0, 0, 0)
			s[root_id] = Vector3(14.0, 0, 0)
		&"spur":
			# 骨刺爆出：全身縮起再猛然張開
			for a in arms:
				r[a] = Vector3(40.0, -20.0, 0)
				s[a] = Vector3(10.0, 80.0, 0)
			r[root_id] = Vector3(30.0, 0, 0)
			s[root_id] = Vector3(-15.0, 0, 0)
			r["$pos"] = Vector3(0, -0.15, 0)
		_:
			# strike：通用的前撲動作
			r[root_id] = Vector3(-10.0, 0, 0)
			s[root_id] = Vector3(25.0, 0, 0)
			s["$pos"] = Vector3(0, 0, -0.2)
	r.erase(&"")
	s.erase(&"")
	return [r, s]

func _add_heads(p: Dictionary, pitch: float) -> void:
	for h in heads:
		p[h] = Vector3(pitch, 0, 0)
	for n in necks:
		p[n] = Vector3(pitch * 0.5, 0, 0)
