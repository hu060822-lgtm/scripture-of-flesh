extends Node
## 全域事件匯流排（autoload: EventBus）。
## 只放「跨系統」事件：UI、音效、劇情旗標、存檔。
## 單一生物內部的事件請直接用該元件自己的 signal（例如 AnatomyState.part_severed）。

## 某個生物的部位被斷離。creature_id 為場景中的實體 ID，part_ids 包含連帶斷離的子部位。
signal creature_part_severed(creature_id: StringName, part_ids: PackedStringArray)
## 某個生物的部位功能失效（未斷離）。
signal creature_part_disabled(creature_id: StringName, part_id: StringName)
## 致命部位失效。rule 為 BodyPartDef.VitalRule。
signal creature_vital_failed(creature_id: StringName, part_id: StringName, rule: int)

## 生物死亡。killer 可能為 null（失血、窒息等）。
signal creature_killed(victim: Node, killer: Node)
## 異化到達新階段。
signal mutation_stage_reached(creature_id: StringName, stage_id: StringName)
## 劇情旗標改變。
signal flag_changed(flag: StringName, value: Variant)

## 聲響（敵人 AI 聽覺用）。position 為聲源、radius 為傳播半徑（隔牆減半）、
## source 為發出聲音的生物（可能為 null）、kind 例如 &"attack"、&"impact"、&"sever"、&"alarm"。
signal noise_emitted(position: Vector3, radius: float, source: Node, kind: StringName)

func emit_noise(position: Vector3, radius: float, source: Node = null, kind: StringName = &"generic") -> void:
	noise_emitted.emit(position, radius, source, kind)
