class_name AiState
extends RefCounted
## AI 狀態基底。每個狀態一個腳本，update 回傳下一個狀態名稱（&"" 代表維持）。

func enter(_ai: EnemyAI) -> void:
	pass

func exit(_ai: EnemyAI) -> void:
	pass

func update(_ai: EnemyAI, _delta: float) -> StringName:
	return &""
