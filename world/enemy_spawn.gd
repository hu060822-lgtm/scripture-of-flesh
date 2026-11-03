class_name EnemySpawn
extends Marker3D
## 敵人生成點。被擊殺的敵人記錄在 GameState.killed，讀檔後不再出現（序章不重生）。

const GROUP := &"enemy_spawns"

@export var spawn_id: StringName = &""
@export_file("*.tres") var enemy_path: String = ""
## 生成時面向的角度（度）。
@export var facing_degrees: float = 0.0
## alive：一般敵人；dormant：躺著裝死，靠近或被打才爬起來；corpse：真的屍體（布景，不能摘器官）。
@export_enum("alive", "dormant", "corpse") var mode: String = "alive"

func _ready() -> void:
	add_to_group(GROUP)

func should_spawn() -> bool:
	return enemy_path != "" and not GameState.killed.has(spawn_id)

const CORPSE_META := &"decor_corpse"

func spawn(parent: Node) -> CharacterBody3D:
	if not should_spawn():
		return null
	# 新手難度曲線：越前面的敵人越溫和
	var progress := DifficultyCurve.progress_for(spawn_id, global_position)
	var e := EnemyFactory.create(DifficultyCurve.apply(load(enemy_path), progress), spawn_id)
	e.set_meta(&"difficulty_progress", progress)
	e.position = global_position
	e.rotation.y = deg_to_rad(facing_degrees)
	if mode == "corpse":
		e.set_meta(CORPSE_META, true)
		e.set_meta(&"harvestable", [])
	else:
		e.set_meta(&"spawn_id", spawn_id)
	parent.add_child(e)
	match mode:
		"dormant":
			(e.get_node("EnemyAI") as EnemyAI).set_dormant(true)
		"corpse":
			# 布景屍體：一生成就死去（不給經驗、不記錄擊殺、不播死亡音效），躺在原地
			var c: CombatComponent = e.get_node("CombatComponent")
			c.last_attacker = null
			c._die("decor")
	return e
