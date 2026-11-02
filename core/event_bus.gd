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
