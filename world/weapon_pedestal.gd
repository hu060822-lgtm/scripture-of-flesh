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
	var shown := get_node_or_null("Weapon")
	if shown != null:
		shown.visible = false

func _build_placeholder() -> void:
	var base := BoxMesh.new()
	base.size = Vector3(0.7, 0.9, 0.7)
	Interactable.placeholder_mesh(self, base, Vector3(0, 0.45, 0), Color("cfc8b8"))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.08, 0.9, 0.18)
	Interactable.placeholder_mesh(self, blade, Vector3(0, 1.35, 0), Color("8a8070"), "Weapon")
