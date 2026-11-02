class_name DialogueRunner
extends RefCounted
## 對話執行器（純邏輯，不依賴 UI）。對話以 JSON 撰寫，放在 content/dialogue/<id>.json。
##
## 格式：
## {
##   "id": "agnes_intro", "start": "n1",
##   "nodes": {
##     "n1": {"speaker": "阿格妮絲", "text": "……", "next": "n2",
##            "set": {"met_agnes": true}, "action": "heal"},
##     "n2": {"speaker": "…", "text": "…", "choices": [
##        {"text": "選項", "next": "n3", "if": {"mutation_gte": 50}, "set": {...}, "action": "choose_class:anatomist"}
##     ]},
##     "n3": {"text": "…", "next": ""}       # next 為空字串或省略 = 結束
##   }
## }
## 節點也可以有 "branches": [{"if": {...}, "next": "x"}, ..., {"next": "fallback"}]，
## 進入時立即依條件跳轉（不顯示文字），用來做異化度或旗標分支。
##
## 條件（全部須成立）：flag、not_flag、mutation_gte、mutation_lt、class、has_item。
## 動作字串 "名稱:參數" 透過 action_requested 交給遊戲控制器處理，執行器本身不改變遊戲。

signal node_entered(node: Dictionary)
signal action_requested(action: StringName, arg: String)
signal finished(dialogue_id: StringName)

const DIR := "res://content/dialogue"
const MAX_BRANCH_HOPS := 32

var data := {}
var node_id := ""
## 條件查詢的對象（通常是玩家節點）。null 時異化度視為 0。
var player: Node = null
var active := false

static func load_dialogue(id: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, id]
	if not FileAccess.file_exists(path):
		push_error("找不到對話：%s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	ids.sort()
	return ids

## 驗證對話資料：start 與所有 next 指向存在的節點、每個節點有文字或分支。回傳錯誤訊息陣列。
static func validate(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var nodes: Dictionary = d.get("nodes", {})
	if nodes.is_empty():
		errors.append("沒有節點")
		return errors
	if not nodes.has(d.get("start", "")):
		errors.append("start 指向不存在的節點：%s" % d.get("start", ""))
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		var targets := []
		if n.has("branches"):
			for b in n["branches"]:
				targets.append(b.get("next", ""))
			if not (n["branches"] as Array).any(func(b): return not b.has("if")):
				errors.append("%s：branches 缺少無條件的預設分支" % nid)
		elif not n.has("text"):
			errors.append("%s：沒有 text" % nid)
		targets.append(n.get("next", ""))
		for c in n.get("choices", []):
			if not c.has("text"):
				errors.append("%s：選項沒有 text" % nid)
			targets.append(c.get("next", ""))
		for t in targets:
			if String(t) != "" and not nodes.has(t):
				errors.append("%s：指向不存在的節點 %s" % [nid, t])
	return errors

func start(dialogue, p: Node = null) -> bool:
	data = dialogue if dialogue is Dictionary else load_dialogue(String(dialogue))
	player = p
	if data.is_empty():
		return false
	active = true
	_enter(String(data.get("start", "")))
	return active

func current() -> Dictionary:
	return data.get("nodes", {}).get(node_id, {})

func speaker() -> String:
	return String(current().get("speaker", ""))

func text() -> String:
	return String(current().get("text", ""))

## 目前可選的選項（已依條件過濾）。每個元素為原始選項 Dictionary。
func choices() -> Array:
	return current().get("choices", []).filter(func(c): return check(c.get("if", {})))

## 無選項節點：前往 next。有選項節點時呼叫無效（回傳 false）。
func advance() -> bool:
	if not active or not choices().is_empty():
		return false
	_enter(String(current().get("next", "")))
	return true

func choose(index: int) -> bool:
	var cs := choices()
	if not active or index < 0 or index >= cs.size():
		return false
	var c: Dictionary = cs[index]
	_apply_effects(c)
	_enter(String(c.get("next", "")))
	return true

func _enter(id: String) -> void:
	var hops := 0
	var nodes: Dictionary = data.get("nodes", {})
	while id != "" and nodes.has(id) and nodes[id].has("branches") and hops < MAX_BRANCH_HOPS:
		hops += 1
		var target := ""
		for b in nodes[id]["branches"]:
			if check(b.get("if", {})):
				target = String(b.get("next", ""))
				break
		id = target
	if id == "" or not nodes.has(id):
		node_id = ""
		active = false
		finished.emit(StringName(data.get("id", "")))
		return
	node_id = id
	_apply_effects(nodes[id])
	node_entered.emit(nodes[id])

func _apply_effects(d: Dictionary) -> void:
	var sets: Dictionary = d.get("set", {})
	for k in sets:
		GameState.set_flag(StringName(k), sets[k])
	var action := String(d.get("action", ""))
	if action != "":
		var parts := action.split(":", true, 1)
		action_requested.emit(StringName(parts[0]), parts[1] if parts.size() > 1 else "")

func mutation_value() -> float:
	if player != null and player.has_node("MutationComponent"):
		return (player.get_node("MutationComponent") as MutationComponent).value
	return 0.0

func check(cond: Dictionary) -> bool:
	for key in cond:
		var v = cond[key]
		match String(key):
			"flag":
				if not GameState.has_flag(StringName(v)):
					return false
			"not_flag":
				if GameState.has_flag(StringName(v)):
					return false
			"mutation_gte":
				if mutation_value() < float(v):
					return false
			"mutation_lt":
				if mutation_value() >= float(v):
					return false
			"class":
				if String(GameState.class_id) != String(v):
					return false
			"has_item":
				if player == null or not player.has_node("PlayerData") \
						or (player.get_node("PlayerData") as PlayerData).inventory.count(String(v)) <= 0:
					return false
			_:
				push_warning("未知的對話條件：%s" % key)
				return false
	return true
