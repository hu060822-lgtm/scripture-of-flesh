class_name WeaponPedestal
extends Interactable
## 武器台：拿取後加入玩家的武器欄（1/2/3 切換）。

@export_file("*.tres") var weapon_path: String = ""

func _init() -> void:
	once = true
	prompt_text = "E：拿取武器"

func weapon() -> WeaponDefinition:
	return load(weapon_path) if weapon_path != "" else null

func prompt() -> String:
	var w := weapon()
	return "E：拿取%s" % w.display_name if w != null else prompt_text

func _do(player: Node3D) -> bool:
	var w := weapon()
	var ctrl: PlayerController = player.get_node_or_null("PlayerController")
	if w == null or ctrl == null:
		return false
	if not ctrl.weapons.has(w):
		ctrl.weapons.append(w)
	if ctrl.equipment.weapon_part() == &"":
		ctrl.switch_weapon(ctrl.weapons.find(w))
	return true

func _on_used() -> void:
	var shown := find_child("Weapon", true, false)
	if shown != null:
		shown.visible = false

func _build_placeholder() -> void:
	# 哥德式石座＋實際的武器模型（拿走後只剩台座）
	add_child(PropModels.pedestal(weapon()))
	_shown = find_child("Weapon", true, false)

## 武器在台上緩慢旋轉（PS1 式的展示品），從斜俯視鏡頭也看得出刀身形狀。
const SPIN_SPEED := 0.7
var _shown: Node3D

func _process(delta: float) -> void:
	if _shown != null and _shown.visible:
		_shown.rotation.y = wrapf(_shown.rotation.y + delta * SPIN_SPEED, 0.0, TAU)
