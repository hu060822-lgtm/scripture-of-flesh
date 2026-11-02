class_name AttackStyles
extends RefCounted
## 攻擊 → 動作風格。動作片段依「風格」產生，而不是每個攻擊一套，
## 新攻擊只要對應到既有風格（或在 AttackDefinition.anim_style 指定）就有動畫。
##
## 風格分兩類：
##   單臂風格（ARM_STYLES）：每隻手臂各一組片段，由實際出手的手臂決定（持武器的手或剩下的手）。
##   全身風格：所有相關部位一起動（雙手抓、踢、咬、尖叫…）。

const ARM_STYLES := [&"slash", &"overhead", &"thrust", &"punch", &"claw", &"lash", &"grasp"]

const BY_ID := {
	# 武器
	&"cleaver_light": &"slash", &"cleaver_heavy": &"overhead",
	&"rapier_light": &"thrust", &"rapier_heavy": &"thrust_lunge",
	&"hammer_light": &"slash", &"hammer_heavy": &"overhead_two",
	# 天生攻擊
	&"punch": &"punch", &"claw": &"claw", &"swipe": &"claw", &"lash": &"lash", &"mother_lash": &"lash",
	&"crawl_grasp": &"grasp", &"double_grab": &"grab", &"grab_tear": &"grab", &"flurry": &"flurry",
	&"kick": &"kick", &"spur_kick": &"kick", &"leap_kick": &"leap_kick",
	&"lunge": &"lunge", &"pounce_bite": &"pounce", &"bite": &"bite",
	&"birth_scream": &"scream", &"cradle_crush": &"cradle", &"gaze": &"gaze",
	&"stilt_stomp": &"stomp", &"bone_spur": &"spur",
}

## 所有風格（測試用來確認每種都能產生片段）。
const ALL := [&"slash", &"overhead", &"thrust", &"punch", &"claw", &"lash", &"grasp",
	&"overhead_two", &"thrust_lunge", &"grab", &"flurry", &"kick", &"leap_kick", &"lunge",
	&"pounce", &"bite", &"scream", &"cradle", &"gaze", &"stomp", &"spur", &"strike"]

static func style_for(attack: AttackDefinition) -> StringName:
	if attack == null:
		return &"strike"
	if attack.anim_style != &"":
		return attack.anim_style
	if BY_ID.has(attack.id):
		return BY_ID[attack.id]
	# 推論：沒有登記的新攻擊依標籤與能力需求選一個合理的風格
	if attack.tags.has("lunge"):
		return &"lunge"
	var req := attack.required_capabilities
	if attack.requires_weapon or req.has("grip"):
		return &"grab" if int(req.get("grip", 1)) >= 2 else &"slash"
	if req.has("bite"):
		return &"bite"
	if req.has("leg") or req.has("locomotion"):
		return &"kick"
	return &"strike"

static func is_arm_style(style: StringName) -> bool:
	return style in ARM_STYLES
