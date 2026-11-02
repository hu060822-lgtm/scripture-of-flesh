extends Node3D
## 【測試場景】斷肢沙盒：用滑鼠點擊暫代人形的部位，套用所選武器的命中。
## 操作：1 斧（切割）／2 錘（粉碎＋骨折）／3 刺劍（穿刺）
##       左鍵 攻擊點到的部位　Shift+左鍵 必定斷肢（處決測試）　R 重置
## 這不是遊戲內容，只用來在編輯器中目視確認斷肢表現。

const T := DamageTypes.Type
const WEAPONS := [
	{"name": "斧（切割）", "amounts": {T.CUT: 18.0}, "sever_power": 1.5},
	{"name": "錘（粉碎＋骨折）", "amounts": {T.CRUSH: 14.0, T.FRACTURE: 8.0}, "sever_power": 0.6},
	{"name": "刺劍（穿刺）", "amounts": {T.PIERCE: 14.0, T.CUT: 4.0}, "sever_power": 0.4},
]

var _weapon := 0
var _camera: Camera3D
var _label: Label
var _creatures: Array[Node3D] = []
var _log: PackedStringArray = []

func _ready() -> void:
	_build_environment()
	_spawn_creatures()

func _build_environment() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	# 固定斜俯視角
	_camera.position = Vector3(0, 4.5, 5.5)
	_camera.look_at(Vector3(0, 1.0, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1b1918")
	env.environment.ambient_light_color = Color("8a8070")
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(20, 0.2, 20)
	shape.shape = box
	shape.position = Vector3(0, -0.1, 0)
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20)
	mesh.mesh = pm
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("3a3532")
	mesh.material_override = mat
	floor_body.add_child(mesh)
	add_child(floor_body)
	var ui := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16, 16)
	ui.add_child(_label)
	add_child(ui)

func _spawn_creatures() -> void:
	for c in _creatures:
		c.queue_free()
	_creatures.clear()
	for n in get_tree().get_nodes_in_group(SeveredPart.GROUP):
		n.queue_free()
	for n in get_children():
		if n is RigidBody3D and n.get_meta(&"pickup", false):
			n.queue_free()
	var specs := [
		["res://content/anatomy/humanoid.tres", &"stitcher", Vector3(-1.2, 0, 0)],
		["res://content/anatomy/multi_armed.tres", &"many_hands", Vector3(1.2, 0, 0)],
	]
	for s in specs:
		var c := PlaceholderBodyBuilder.build_creature(load(s[0]), s[1])
		c.position = s[2]
		add_child(c)
		_creatures.append(c)
		# 給右手（或第一條右臂）一把暫代武器，驗證斷臂時武器掉落
		var equip: EquipmentComponent = c.get_node("EquipmentComponent")
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.05, 0.05, 0.7)
		blade.mesh = bm
		blade.position = Vector3(0, 0, 0.3)
		var holder := Node3D.new(); holder.name = "PlaceholderBlade"
		holder.add_child(blade)
		equip.equip(&"arm_r" if equip.anchors.has(&"arm_r") else &"arm_r1", holder)
	_log.clear()
	_refresh_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				_weapon = event.keycode - KEY_1
				_refresh_label()
			KEY_R:
				_spawn_creatures()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_attack_at(event.position, event.shift_pressed)

func _attack_at(screen_pos: Vector2, execute: bool) -> void:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 50.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Hurtbox.LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is Hurtbox):
		return
	var hb: Hurtbox = hit["collider"]
	if not hb.active:
		return
	var creature := hb.get_parent()
	while creature != null and not creature.has_node("AnatomyComponent"):
		creature = creature.get_parent()
	if creature == null:
		return
	var anatomy: AnatomyComponent = creature.get_node("AnatomyComponent")
	if execute:
		var ok := anatomy.state.sever_part(hb.part_id)
		_log.append("處決 %s：%s" % [hb.part_id, "斷離" if ok else "此部位不可斷離"])
	else:
		var w: Dictionary = WEAPONS[_weapon]
		var pkt := DamagePacket.make(hb.part_id, w["amounts"])
		pkt.sever_power = w["sever_power"]
		var r := anatomy.receive(pkt)
		for h in r.hits:
			_log.append("%s %s：-%.1f HP，斷肢機率 %d%%%s" % [
				"└貫穿" if h.pass_through else creature.name, h.part_id, h.hp_loss,
				roundi(h.sever_chance * 100.0), "　★斷離" if h.severed else ""])
	while _log.size() > 8:
		_log.remove_at(0)
	_refresh_label()

func _refresh_label() -> void:
	var lines := PackedStringArray()
	lines.append("【斷肢沙盒｜暫代模型】武器：%s　(1/2/3 切換，Shift+點擊 處決，R 重置)" % WEAPONS[_weapon]["name"])
	for c in _creatures:
		if not is_instance_valid(c):
			continue
		var a: AnatomyComponent = c.get_node("AnatomyComponent")
		var ctrl: DismembermentController = c.get_node("DismembermentController")
		if a.state == null:
			continue
		var parts := PackedStringArray()
		for pid in a.state.part_ids():
			var st := a.state.status_of(pid)
			if st != AnatomyTypes.PartStatus.INTACT:
				parts.append("%s=%s" % [pid, AnatomyTypes.status_name(st)])
		lines.append("%s%s｜能力 %s｜動作組 %s｜失血 %.2f/s" % [
			c.name, "（死亡）" if a.state.is_dead else "", a.state.capabilities(),
			ctrl.animation_set.values(), a.state.total_bleed_rate()])
		if not parts.is_empty():
			lines.append("    " + ", ".join(parts))
	lines.append("")
	lines.append_array(_log)
	_label.text = "\n".join(lines)
