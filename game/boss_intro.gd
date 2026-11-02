class_name BossIntro
extends Node
## Boss 登場演出（取代純文字標題卡）。約 4 秒，E／Esc 可跳過。
##   0.0–1.0  戰鬥暫停，鏡頭從 Boss 腳邊的低角度開始
##   1.0–2.6  鏡頭沿著高蹺往上搖到面具，Boss 從蜷伏中站起、仰頭尖叫（intro 片段）
##   1.8–      名稱標題淡入（BossBar 的標題）
##   3.6–4.2  鏡頭回到玩家，恢復戰鬥
## 以真實時間推進；期間 CameraRig 停止跟隨，Boss 的 CreatureAnimator 由這裡手動推進。

signal finished

const DURATION := 4.2

var boss: Node3D
var rig: CameraRig
var title_label: Label
var time := 0.0
var playing := false
var _saved_camera: Transform3D
var _anim: CreatureAnimator

## rig 可為 null（測試）；title_label 可為 null。
func start(boss_body: Node3D, camera_rig: CameraRig, title: Label = null) -> void:
	boss = boss_body
	rig = camera_rig
	title_label = title
	time = 0.0
	playing = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	TimeScale.set_mode(TimeScale.Mode.PAUSE)
	_anim = boss.get_node_or_null("CreatureAnimator")
	if _anim != null:
		_anim.play_override(&"intro")
	if rig != null:
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		_saved_camera = rig.camera.global_transform
	if title_label != null:
		title_label.modulate.a = 0.0
		title_label.visible = true
	_apply(0.0)

func _process(delta: float) -> void:
	if playing:
		advance(delta)

func advance(dt: float) -> void:
	time += dt
	if _anim != null:
		_anim.tick(dt)
	_apply(dt)
	if time >= DURATION:
		stop()

func stop() -> void:
	if not playing:
		return
	playing = false
	if _anim != null and _anim.override_clip == &"intro":
		_anim.play_override(&"")
	if rig != null:
		rig.process_mode = Node.PROCESS_MODE_INHERIT
	if title_label != null:
		title_label.modulate.a = 1.0
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	finished.emit()

func _apply(_dt: float) -> void:
	if title_label != null:
		title_label.modulate.a = clampf((time - 1.8) / 0.8, 0.0, 1.0)
	if rig == null or boss == null or not is_instance_valid(boss):
		return
	var cam := rig.camera
	var base := boss.global_position
	var fwd := -boss.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	if time < 3.6:
		# 鏡頭在 Boss 前方，從低處往上搖
		var k := clampf((time - 1.0) / 1.6, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var pos := base + fwd * lerpf(4.2, 5.2, e) + side * 1.2 + Vector3.UP * lerpf(0.4, 2.6, e)
		var look := base + Vector3.UP * lerpf(0.8, 3.4, e)
		cam.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	else:
		var k := clampf((time - 3.6) / 0.6, 0.0, 1.0)
		cam.global_transform = cam.global_transform.interpolate_with(_saved_camera, k)

func _unhandled_input(event: InputEvent) -> void:
	if playing and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		stop()
		get_viewport().set_input_as_handled()
