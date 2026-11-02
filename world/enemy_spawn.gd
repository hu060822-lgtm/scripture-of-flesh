class_name EnemySpawn
extends Marker3D
## 敵人生成點。被擊殺的敵人記錄在 GameState.killed，讀檔後不再出現（序章不重生）。

const GROUP := &"enemy_spawns"

@export var spawn_id: StringName = &""
@export_file("*.tres") var enemy_path: String = ""
## 生成時面向的角度（度）。
@export var facing_degrees: float = 0.0

func _ready() -> void:
	add_to_group(GROUP)

func should_spawn() -> bool:
	return enemy_path != "" and not GameState.killed.has(spawn_id)

func spawn(parent: Node) -> CharacterBody3D:
	if not should_spawn():
		return null
	var e := EnemyFactory.create(load(enemy_path), spawn_id)
	e.position = global_position
	e.rotation.y = deg_to_rad(facing_degrees)
	e.set_meta(&"spawn_id", spawn_id)
	parent.add_child(e)
	return e
