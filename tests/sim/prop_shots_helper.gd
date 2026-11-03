extends RefCounted
## 道具與 NPC 模型截圖（PropModels、NpcFigure），用美術測試場景的燈光與 360p 畫面。
var tree: SceneTree
var out := "user://prop_shots"
var scene: Node
var placed := []

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	scene = load("res://scenes/art_test/art_test.tscn").instantiate()
	tree.root.add_child(scene)

func _cam(pos: Vector3, at: Vector3) -> void:
	var cam: Camera3D = scene.camera
	cam.max_track_degrees = 0.0
	cam.position = pos
	cam.look_at(at)

func _add(n: Node3D, pos: Vector3, rot_y: float = 0.0) -> void:
	n.position = pos
	n.rotation_degrees.y = rot_y
	scene.screen.world.add_child(n)
	placed.append(n)

func _clear() -> void:
	for n in placed:
		n.queue_free()
	placed.clear()

func _item(id: String, pos: Vector3, count: int = 1) -> void:
	var it := ItemPickup.new()
	it.item_id = id
	it.count = count
	_add(it, pos)

func step(f: int) -> bool:
	match f:
		5:
			for e in scene.enemies:
				e.queue_free()
			scene.enemies.clear()
			scene.player.position = Vector3(-4.0, 0, -2.0)
			scene.player.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
			var ids := ["suture_kit", "blood_vial", "umbilical_key", "first_suture", "organ:watcher_eye", "organ:agnes_arm", "organ:iron_arm"]
			for i in ids.size():
				_item(ids[i], Vector3(-2.1 + (i % 4) * 1.4, 0, 1.2 + (i / 4) * 1.1), 2)
			_cam(Vector3(0, 2.3, 4.6), Vector3(0, 0.1, 1.7))
		20: _shot("p01_floor_items")
		22: _cam(Vector3(-1.4, 1.0, 2.6), Vector3(-1.4, 0.1, 1.4))
		26: _shot("p02_closeup_suture_vials")
		28: _cam(Vector3(1.4, 1.0, 2.6), Vector3(1.4, 0.1, 1.4))
		32: _shot("p03_closeup_key_first_suture")
		34:
			_clear()
			var pd := WeaponPedestal.new()
			pd.weapon_path = "res://content/weapons/bone_saw_cleaver.tres"
			_add(pd, Vector3(-1.8, 0, 1.0))
			var n := DialogueInteractable.new()
			n.kind = "note"
			_add(n, Vector3(-0.4, 0, 1.6))
			var s := ScripturePage.new()
			_add(s, Vector3(0.6, 0, 1.6))
			var ins := DialogueInteractable.new()
			_add(ins, Vector3(1.9, 0, 0.8), 180.0)
			_cam(Vector3(0, 2.0, 4.6), Vector3(0, 0.6, 1.2))
		44: _shot("p04_pedestal_note_page_inscription")
		46:
			_clear()
			var a := DialogueInteractable.new()
			a.kind = "npc"
			a.object_id = &"npc_agnes"
			_add(a, Vector3(-0.9, 0, 1.0), 180.0)
			var g := DialogueInteractable.new()
			g.kind = "npc"
			g.object_id = &"npc_ignatius"
			_add(g, Vector3(1.0, 0, 1.0), 200.0)
			_cam(Vector3(0, 1.8, 4.4), Vector3(0, 0.8, 1.0))
		60: _shot("p05_npcs_agnes_ignatius")
		62: _cam(Vector3(-0.9, 1.7, 2.6), Vector3(-0.9, 1.3, 1.0))
		66: _shot("p06_closeup_agnes")
		68: _cam(Vector3(1.0, 1.2, 2.8), Vector3(1.0, 0.4, 1.0))
		72:
			_shot("p07_closeup_ignatius")
			return true
	return false

func _shot(name: String) -> void:
	tree.root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
