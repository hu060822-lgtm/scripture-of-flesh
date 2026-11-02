class_name Greybox
extends RefCounted
## 【暫代】場景灰盒工具：地板、牆、燈光、環境。正式關卡美術完成前使用。

const FLOOR_COLOR := Color("3a3532")
const WALL_COLOR := Color("cfc8b8")

static func environment(parent: Node, ambient: Color = Color("8a8070")) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.8
	parent.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("141211")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = ambient
	env.environment.ambient_light_energy = 0.5
	parent.add_child(env)

static func box(parent: Node, center: Vector3, size: Vector3, color: Color = WALL_COLOR, collide: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PlaceholderBodyBuilder.WORLD_LAYER
	body.position = center
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body

static func floor_plane(parent: Node, center: Vector3, size: Vector2) -> StaticBody3D:
	return box(parent, center - Vector3(0, 0.1, 0), Vector3(size.x, 0.2, size.y), FLOOR_COLOR)
