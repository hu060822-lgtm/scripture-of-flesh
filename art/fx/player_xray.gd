class_name PlayerXray
extends Node
## 牆後透視（luz 2026-11-03）：玩家被牆或柱子擋住時，在牆上畫出奶油黃的半透明剪影，看得到自己在哪。
## 做法：把身上每個 PS1 材質網格的材質換成「專屬副本 + next_pass 透視層」（ps1_xray.gdshader）。
## 材質是全域共用快取（PS1Style.material），不能直接改原件，否則敵人也會透視。
## 不用 material_overlay：那一層留給受擊閃白（ImpactFeedback）。
## 定期掃描：移植、突變、武器更換後新增的網格也會套上；被砍下來掉到地上的部位會還原成原本材質。

const SHADER := preload("res://art/ps1/ps1_xray.gdshader")
const SCAN_INTERVAL := 0.25

var enabled := true
## GeometryInstance3D -> 原本的材質（還原用）
var _applied := {}
var _scan_left := 0.0
static var _xray_mat: ShaderMaterial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh()

func _process(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_INTERVAL
		refresh()

func body() -> Node3D:
	return get_parent() as Node3D

static func xray_material() -> ShaderMaterial:
	if _xray_mat == null:
		_xray_mat = ShaderMaterial.new()
		_xray_mat.shader = SHADER
	_xray_mat.set_shader_parameter("snap_resolution", PS1Style.snap_resolution)
	_xray_mat.set_shader_parameter("jitter_enabled", PS1Style.jitter_enabled)
	return _xray_mat

## 目前套著透視層的網格數（測試用）。
func applied_count() -> int:
	return _applied.size()

func is_applied(gi: GeometryInstance3D) -> bool:
	return _applied.has(gi)

func set_enabled(on: bool) -> void:
	enabled = on
	refresh()

func refresh() -> void:
	var b := body()
	if b == null:
		return
	var xm := xray_material()
	# 還原：已經不在身上（被砍掉的肢段）、被別的系統換掉材質、或關閉透視
	for gi in _applied.keys():
		var g := gi as GeometryInstance3D
		if not is_instance_valid(g):
			_applied.erase(gi)
			continue
		var mine := g.material_override as ShaderMaterial
		var still_mine := mine != null and mine.next_pass == xm
		if not enabled or not b.is_ancestor_of(g) or not still_mine:
			if still_mine:
				g.material_override = _applied[gi]
			_applied.erase(gi)
		else:
			mine.set_shader_parameter("snap_resolution", PS1Style.snap_resolution)
			mine.set_shader_parameter("jitter_enabled", PS1Style.jitter_enabled)
	if not enabled:
		return
	for n in b.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if _applied.has(g):
			continue
		var mat := g.material_override as ShaderMaterial
		if mat == null or mat.shader != PS1Style.SHADER or mat.next_pass != null:
			continue
		var copy := mat.duplicate() as ShaderMaterial
		copy.next_pass = xm
		_applied[g] = mat
		g.material_override = copy
