class_name SilenceZone
extends Node3D
## 靜默區（序章恐怖橋段 C6）：玩家在矩形範圍內、而且附近沒有敵人察覺時，音樂與環境音完全消失，
## 只剩自己的腳步聲（與瀕死時的心跳）。一旦有敵人察覺，音樂照常進入緊張／戰鬥。
## 以距離判定（不依賴物理）。

const GROUP := &"silence_zones"

## 半寬（x）與半長（z），以節點位置為中心。
@export var half_extents: Vector2 = Vector2(4, 4)

func _ready() -> void:
	add_to_group(GROUP)

func contains(p: Vector3) -> bool:
	var d := p - global_position
	return absf(d.x) <= half_extents.x and absf(d.z) <= half_extents.y
