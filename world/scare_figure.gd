class_name ScareFigure
extends Node3D
## 驚嚇用的人影（序章恐怖橋段 C1、異化幻覺 C3）。沒有碰撞、沒有 AI，只是一個幾乎全黑的剪影。
## kind：girl（小女孩，伊蓮）、tall（披頭紗的高大修女）、hanging（吊在天花板上的屍體）、corpse（躺著的屍體）。
## 【暫代】低多邊形程序模型。

const SILHOUETTE := Color("140d0d")

@export_enum("girl", "tall", "hanging", "corpse") var kind: String = "girl"
## 是否一直轉向玩家（吊屍慢慢轉過來）。
@export var face_player := false
@export var turn_speed := 0.6

var player: Node3D

func _ready() -> void:
	if get_child_count() == 0:
		build()

func build() -> void:
	var mat := PS1Style.material(SILHOUETTE, "cloth")
	var k := MeshKit.new()
	match kind:
		"girl":
			# 裙子、細手臂、頭與垂下的長髮，約 1.15m
			k.lathe([Vector2(0.05, 0.75), Vector2(0.11, 0.6), Vector2(0.2, 0.25), Vector2(0.24, 0.12)], 7)
			k.lathe([Vector2(0.012, 0.12), Vector2(0.012, 0.0)], 4, MeshKit.at(Vector3(-0.06, 0, 0)))
			k.lathe([Vector2(0.012, 0.12), Vector2(0.012, 0.0)], 4, MeshKit.at(Vector3(0.06, 0, 0)))
			k.lathe([Vector2(0.015, 0.72), Vector2(0.015, 0.4)], 4, MeshKit.at(Vector3(-0.13, 0, 0), Vector3(0, 0, -8)))
			k.lathe([Vector2(0.015, 0.72), Vector2(0.015, 0.4)], 4, MeshKit.at(Vector3(0.13, 0, 0), Vector3(0, 0, 8)))
			k.lathe([Vector2(0.0, 1.13), Vector2(0.08, 1.06), Vector2(0.09, 0.96), Vector2(0.06, 0.86), Vector2(0.0, 0.8)], 7)
			k.lathe([Vector2(0.09, 1.04), Vector2(0.1, 0.8), Vector2(0.07, 0.62)], 7, MeshKit.at(Vector3(0, 0, 0.03)), Vector2(1.0, 0.6))
		"tall":
			# 披頭紗、拖地長袍，約 2.3m，手臂過長
			k.lathe([Vector2(0.1, 1.95), Vector2(0.22, 1.7), Vector2(0.3, 1.0), Vector2(0.42, 0.0)], 7)
			k.lathe([Vector2(0.0, 2.32), Vector2(0.14, 2.2), Vector2(0.16, 2.0), Vector2(0.3, 1.6)], 7)
			k.lathe([Vector2(0.03, 1.7), Vector2(0.025, 0.55)], 4, MeshKit.at(Vector3(-0.3, 0, 0), Vector3(0, 0, -6)))
			k.lathe([Vector2(0.03, 1.7), Vector2(0.025, 0.55)], 4, MeshKit.at(Vector3(0.3, 0, 0), Vector3(0, 0, 6)))
		"hanging":
			# 繩子＋垂吊的身體（原點在天花板，身體往下）
			k.lathe([Vector2(0.015, 0.0), Vector2(0.015, -1.2)], 4)
			k.lathe([Vector2(0.0, -1.2), Vector2(0.11, -1.28), Vector2(0.1, -1.45), Vector2(0.06, -1.52)], 6)
			k.lathe([Vector2(0.16, -1.55), Vector2(0.2, -1.8), Vector2(0.16, -2.25)], 6, Transform3D.IDENTITY, Vector2(1.0, 0.7))
			k.lathe([Vector2(0.05, -2.25), Vector2(0.04, -3.0)], 4, MeshKit.at(Vector3(-0.08, 0, 0)))
			k.lathe([Vector2(0.05, -2.25), Vector2(0.04, -3.0)], 4, MeshKit.at(Vector3(0.08, 0, 0)))
			k.lathe([Vector2(0.035, -1.6), Vector2(0.03, -2.4)], 4, MeshKit.at(Vector3(-0.24, 0, 0)))
			k.lathe([Vector2(0.035, -1.6), Vector2(0.03, -2.4)], 4, MeshKit.at(Vector3(0.24, 0, 0)))
		"corpse":
			# 仰躺的身體（沿 -Z 方向）
			var lie := MeshKit.at(Vector3.ZERO, Vector3(-90, 0, 0))
			k.lathe([Vector2(0.16, 0.2), Vector2(0.2, 0.5), Vector2(0.16, 0.9)], 6, lie, Vector2(1.0, 0.6))
			k.lathe([Vector2(0.0, 1.15), Vector2(0.11, 1.05), Vector2(0.1, 0.92)], 6, lie)
			k.lathe([Vector2(0.05, 0.2), Vector2(0.04, -0.6)], 4, lie * MeshKit.at(Vector3(-0.09, 0, 0)))
			k.lathe([Vector2(0.05, 0.2), Vector2(0.04, -0.6)], 4, lie * MeshKit.at(Vector3(0.09, 0, 0)))
	var mi := MeshInstance3D.new()
	mi.name = "Silhouette"
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _process(delta: float) -> void:
	if not face_player or player == null or not is_instance_valid(player) or not visible:
		return
	var to := player.global_position - global_position
	var want := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, want, turn_speed * delta)

## 閃一下後消失（燈光閃爍般的兩三格）。
func vanish() -> void:
	if not is_inside_tree():
		visible = false
		return
	var tw := create_tween()
	for i in 3:
		tw.tween_callback(func(): visible = not visible).set_delay(0.05)
	tw.tween_callback(func(): visible = false)
