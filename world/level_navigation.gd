class_name LevelNavigation
extends RefCounted
## 在執行期為關卡烘焙導航網格（敵人跨房間尋路）。
## 只從 source 節點下的靜態碰撞體烘焙（灰盒的地板、牆、道具），不包含 Boss 大門等可動物件，
## 因此美術執行緒替換關卡幾何後不需要重新產生 .tscn，只要碰撞體還在 source 下即可。
## 小型關卡烘焙只需幾毫秒，所以採同步烘焙。

const AGENT_RADIUS := 0.5  # 必須是 cell_size（0.25）的倍數
const AGENT_HEIGHT := 1.75
const MAX_CLIMB := 0.25
const MAX_SLOPE := 40.0

static func bake(level: Node3D, source: Node3D) -> NavigationRegion3D:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = PlaceholderBodyBuilder.WORLD_LAYER
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = AGENT_HEIGHT
	nm.agent_max_climb = MAX_CLIMB
	nm.agent_max_slope = MAX_SLOPE
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, source)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nm
	level.add_child(region)
	# 立即同步導航地圖，讓同一個 frame 生成的敵人就能查詢路徑。
	NavigationServer3D.map_force_update(level.get_world_3d().navigation_map)
	return region
