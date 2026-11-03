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
## 動畫以 linear 內插，播放端（CreatureAnimator）以 12fps 逐格推進，保留 PS1 低幀數的頓挫感。

const SKELETON_PATH := "Body/Skeleton"
const PHASES := ["windup", "active", "recovery"]

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

## 攻擊片段名稱。arm_id 為空代表全身風格。
static func attack_clip_name(style: StringName, arm_id: StringName, phase: String) -> StringName:
	if arm_id == &"":
		return StringName("%s_%s" % [style, phase])
	return StringName("%s@%s_%s" % [style, arm_id, phase])

## 確保攻擊片段存在（三個階段）。回傳 false 代表這個身體無法產生該風格（例如沒有手臂的單臂風格）。
static func ensure_attack(profile: AnatomyProfile, style: StringName, arm_id: StringName) -> bool:
	var lib := for_profile(profile)
	if lib.has_animation(attack_clip_name(style, arm_id, "windup")):
		return true
	var b := new(profile)
	var clips := b.attack_clips(style, arm_id)
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
	var keys := []
	for i in n + 1:
		var t := float(i) / float(n)
		keys.append([t * length, f.call(t)])
	return _clip(length, true, keys)

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
	out.append([&"idle", _cycle(2.0, 8, func(t):
		var p := {}
		if root_id != &"": p[root_id] = Vector3(sin(TAU * t) * 2.0, 0, 0)
		for h in heads: p[h] = Vector3(-sin(TAU * t) * 2.0, 0, sin(TAU * t * 0.5) * 3.0)
		for a in arms: p[a] = Vector3(sin(TAU * t) * 2.0, 4.0 + sin(TAU * t) * 1.5, 0)
		for c in cradles: p[c] = Vector3(35.0 + sin(TAU * t) * 3.0, -10.0, 0)
		if jaw != &"": p[jaw] = Vector3(maxf(0.0, sin(TAU * t)) * 4.0, 0, 0)
		_sway(p, t, 4.0)
		return p)])
	out.append([&"walk", _cycle(1.0, 8, func(t):
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
		return p)])
	# 單腳：拖行跛步，身體往剩下的腿傾斜並上下頓挫
	out.append([&"limp", _cycle(1.3, 8, func(t):
		var p := {}
		var hop := maxf(0.0, sin(TAU * t))
		if root_id != &"": p[root_id] = Vector3(10.0, sin(TAU * t) * 8.0, 0)
		for l in legs: p[l] = Vector3(sin(TAU * t) * 18.0, 0, 0)
		for a in arms: p[a] = Vector3(10.0 + hop * 15.0, 20.0 * hop, 0)
		for h in heads: p[h] = Vector3(8.0, 0, sin(TAU * t) * 6.0)
		_sway(p, t, 12.0)
		p["$pos"] = Vector3(0, -0.04 - hop * 0.06, 0)
		return p)])
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
	out.append([&"block", _clip(0.5, true, [[0.0, _block_pose()], [0.5, _block_pose()]])])
	var neutral := {}
	var flinch := {}
	if root_id != &"": flinch[root_id] = Vector3(-10.0, 0, 6.0)
	for h in heads: flinch[h] = Vector3(-18.0, 0, 0)
	for a in arms: flinch[a] = Vector3(-10.0, 18.0, 0)
	out.append([&"hit", _clip(0.3, false, [[0.0, neutral], [0.08, flinch], [0.3, neutral]])])
	var reel := flinch.duplicate()
	if root_id != &"": reel[root_id] = Vector3(-18.0, 8.0, 10.0)
	for a in arms: reel[a] = Vector3(-25.0, 40.0, 0)
	for l in legs: reel[l] = Vector3(-12.0 if _is_left(l) else 10.0, 0, 0)
	reel["$pos"] = Vector3(0, -0.05, 0.12)
	out.append([&"stagger", _clip(1.0, false, [[0.0, neutral], [0.2, reel], [0.75, reel], [1.0, neutral]])])
	# 斷肢：劇烈後仰、手臂亂揮（失去的部位骨骼已縮為零，不受影響）
	var shock := {}
	if root_id != &"": shock[root_id] = Vector3(-25.0, 12.0, -20.0)
	for h in heads: shock[h] = Vector3(-35.0, 0, 15.0)
	for a in arms: shock[a] = Vector3(40.0, 55.0, 0)
	if jaw != &"": shock[jaw] = Vector3(30.0, 0, 0)
	shock["$pos"] = Vector3(0, -0.08, 0.15)
	var shock2 := shock.duplicate()
	for a in arms: shock2[a] = Vector3(-20.0, 30.0, 0)
	out.append([&"sever", _clip(0.6, false, [[0.0, neutral], [0.1, shock], [0.3, shock2], [0.6, neutral]])])
	var duck := {}
	if root_id != &"": duck[root_id] = Vector3(30.0, 0, 0)
	for l in legs: duck[l] = Vector3(45.0 if _is_left(l) else -25.0, 0, 0)
	for a in arms: duck[a] = Vector3(30.0, 25.0, 0)
	for h in heads: duck[h] = Vector3(15.0, 0, 0)
	duck["$pos"] = Vector3(0, -0.3, 0)
	out.append([&"dodge", _clip(1.0, false, [[0.0, neutral], [0.2, duck], [0.7, duck], [1.0, neutral]])])
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
	out.append([&"death", _clip(1.0, false, [[0.0, start], [0.35, mid], [0.75, end], [1.0, end]])])
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
func attack_clips(style: StringName, arm_id: StringName) -> Array:
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
	return [
		[attack_clip_name(style, arm_id, "windup"), _clip(1.0, false, [[0.0, neutral], [0.6, r], [1.0, over]])],
		[attack_clip_name(style, arm_id, "active"), _clip(1.0, false, [[0.0, over], [0.45, s], [1.0, s]])],
		[attack_clip_name(style, arm_id, "recovery"), _clip(1.0, false, [[0.0, s], [0.3, s], [1.0, neutral]])],
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
