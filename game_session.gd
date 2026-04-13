extends Node
class_name GameSession

signal log_changed
signal session_loaded
signal contract_changed
signal village_updated
signal run_inventory_changed

const LOG_MAX := 30
const AUTOSAVE_PATH := "user://autosave.json"

# --- Player ---
var player_max_hp: int = 50
var player_hp: int = 50

var skills := {
	"hearing": 1,
	"smell": 1,
	"echo": 1
}

# --- Meta / Village ---
var home_pos: Vector2i = Vector2i.ZERO
var in_village: bool = true
var gold: int = 0
var backpack_level: int = 0
var backpack_capacity: int = 8
var last_run_summary: Dictionary = {}
var selected_contract: Dictionary = {}

# --- Run ---
var run_active: bool = false
var has_left_home_this_run: bool = false
var current_contract: Dictionary = {}
var contract_progress := {
	"kills_by_pack": {},
	"tracks": {}
}
var carried_loot: Array = []
var current_state_name: String = "VillageState"

# --- Overworld ---
var world: Dictionary = {}
var player_pos: Vector2i = Vector2i.ZERO
var observations: Array = []
var exploration_turn_phase: String = "sense"

# --- Combat snapshot ---
var combat_snapshot: Dictionary = {}

# Seed
var seed_value: int = 0

# --- Log ---
var log: Array[String] = []

var _autosave_dirty: bool = false

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if _autosave_dirty:
		_autosave_dirty = false
		autosave_now()

func new_game(new_seed: int = 0) -> void:
	if new_seed == 0:
		seed_value = randi()
	else:
		seed_value = new_seed

	seed(seed_value)

	player_max_hp = 50
	player_hp = player_max_hp
	skills = {"hearing": 1, "smell": 1, "echo": 1}

	home_pos = Vector2i.ZERO
	in_village = true
	gold = 0
	backpack_level = 0
	backpack_capacity = 8
	last_run_summary = {}
	selected_contract = {}

	run_active = false
	has_left_home_this_run = false
	current_contract = {}
	contract_progress = {"kills_by_pack": {}, "tracks": {}}
	carried_loot.clear()
	current_state_name = "VillageState"
	combat_snapshot.clear()

	world.clear()
	observations.clear()
	player_pos = home_pos
	exploration_turn_phase = "sense"

	log.clear()
	add_log("Новая игра начата.")
	emit_signal("contract_changed")
	emit_signal("village_updated")
	emit_signal("run_inventory_changed")
	emit_signal("session_loaded")
	request_autosave()

func add_log(msg: String) -> void:
	log.append(msg)
	if log.size() > LOG_MAX:
		log.pop_front()
	emit_signal("log_changed")

func get_available_contracts() -> Array:
	return [
		{
			"id": "trophy_1",
			"type": "trophy_value",
			"title": "Контракт: Набрать трофеев",
			"description": "Вернись с добычей общей ценностью не ниже 12.",
			"required_value": 12,
			"reward_gold": 10
		},
		{
			"id": "wolves_1",
			"type": "kill_count",
			"title": "Контракт: Одинокая стая",
			"description": "Уничтожь 1 стаю волков и вернись в деревню.",
			"target_enemy_pack": "dogs",
			"required_kills": 1,
			"reward_gold": 12
		},
		{
			"id": "large_enemy_1",
			"type": "kill_count",
			"title": "Контракт: Большая добыча",
			"description": "Найди и убей одного крупного монстра.",
			"target_enemy_pack": "large_enemy",
			"required_kills": 1,
			"reward_gold": 20
		}
	]

func select_contract_by_index(index: int) -> bool:
	var contracts := get_available_contracts()
	if index < 0 or index >= contracts.size():
		return false

	selected_contract = (contracts[index] as Dictionary).duplicate(true)
	add_log("Выбран контракт: %s" % str(selected_contract.get("title", "Без названия")))
	emit_signal("contract_changed")
	emit_signal("village_updated")
	request_autosave()
	return true

func is_ready_to_start_run() -> bool:
	return in_village and not selected_contract.is_empty()

func begin_selected_run() -> bool:
	if not is_ready_to_start_run():
		return false

	run_active = true
	in_village = false
	has_left_home_this_run = false
	current_contract = selected_contract.duplicate(true)
	contract_progress = {"kills_by_pack": {}, "tracks": {}}
	carried_loot.clear()
	combat_snapshot.clear()
	world.clear()
	observations.clear()
	player_pos = home_pos
	exploration_turn_phase = "sense"
	player_hp = player_max_hp
	add_log("Ты покидаешь деревню и начинаешь вылазку.")
	emit_signal("contract_changed")
	emit_signal("village_updated")
	emit_signal("run_inventory_changed")
	request_autosave()
	return true

func register_kill(enemy_pack: String, count: int = 1) -> void:
	if not run_active or enemy_pack == "":
		return

	var kills: Dictionary = contract_progress.get("kills_by_pack", {})
	kills[enemy_pack] = int(kills.get(enemy_pack, 0)) + count
	contract_progress["kills_by_pack"] = kills
	request_autosave()

func register_track(track_id: String, count: int = 1) -> void:
	if not run_active or track_id == "":
		return

	var tracks: Dictionary = contract_progress.get("tracks", {})
	tracks[track_id] = int(tracks.get(track_id, 0)) + count
	contract_progress["tracks"] = tracks
	request_autosave()

func add_loot(item: Dictionary) -> bool:
	if not run_active:
		return false
	if item.is_empty():
		return false

	var normalized := _normalize_loot_item(item)
	var slots := int(normalized.get("slots", 1))
	if get_backpack_used() + slots > backpack_capacity:
		add_log("Рюкзак полон: %s не помещается." % str(normalized.get("name", "добыча")))
		emit_signal("run_inventory_changed")
		return false

	carried_loot.append(normalized)
	add_log("Получена добыча: %s." % str(normalized.get("name", "добыча")))
	emit_signal("run_inventory_changed")
	request_autosave()
	return true

func get_backpack_used() -> int:
	var used := 0
	for item_value in carried_loot:
		if item_value is Dictionary:
			used += max(1, int((item_value as Dictionary).get("slots", 1)))
	return used

func get_backpack_free_slots() -> int:
	return max(0, backpack_capacity - get_backpack_used())

func get_carried_loot_value() -> int:
	var total := 0
	for item_value in carried_loot:
		if item_value is Dictionary:
			total += max(0, int((item_value as Dictionary).get("value", 0)))
	return total

func get_carried_loot_count() -> int:
	return carried_loot.size()

func get_loot_preview_lines(max_lines: int = 4) -> Array[String]:
	var out: Array[String] = []
	var count = min(max_lines, carried_loot.size())
	for i in range(count):
		var idx := carried_loot.size() - 1 - i
		var item_value = carried_loot[idx]
		if item_value is Dictionary:
			var item: Dictionary = item_value
			out.append("%s (%dс / %dз)" % [str(item.get("name", "добыча")), int(item.get("slots", 1)), int(item.get("value", 0))])
	return out

func get_contract_progress_text() -> String:
	if current_contract.is_empty():
		return "Контракт не активен"

	match str(current_contract.get("type", "")):
		"kill_count":
			var pack := str(current_contract.get("target_enemy_pack", ""))
			var need := int(current_contract.get("required_kills", 0))
			var kills: Dictionary = contract_progress.get("kills_by_pack", {})
			var have := int(kills.get(pack, 0))
			return "%s: %d / %d" % [_pack_label(pack), have, need]
		"trophy_value":
			var need_value := int(current_contract.get("required_value", 0))
			var have_value := get_carried_loot_value()
			return "Ценность добычи: %d / %d" % [have_value, need_value]
		_:
			return "Прогресс пока не поддерживается"

func is_contract_completed() -> bool:
	if current_contract.is_empty():
		return false

	match str(current_contract.get("type", "")):
		"kill_count":
			var pack := str(current_contract.get("target_enemy_pack", ""))
			var need := int(current_contract.get("required_kills", 0))
			var kills: Dictionary = contract_progress.get("kills_by_pack", {})
			return int(kills.get(pack, 0)) >= need
		"trophy_value":
			return get_carried_loot_value() >= int(current_contract.get("required_value", 0))
		_:
			return false

func finish_successful_return() -> Dictionary:
	var completed := is_contract_completed()
	var contract_reward := int(current_contract.get("reward_gold", 0)) if completed else 0
	var sold_loot_value := get_carried_loot_value()
	var sold_loot_count := get_carried_loot_count()
	var total_gold := sold_loot_value + contract_reward
	gold += total_gold

	last_run_summary = {
		"status": "success" if completed else "partial",
		"title": str(current_contract.get("title", "Без контракта")),
		"contract_completed": completed,
		"reward_gold": contract_reward,
		"sold_loot_value": sold_loot_value,
		"sold_loot_count": sold_loot_count,
		"total_gold_earned": total_gold,
		"progress_text": get_contract_progress_text()
	}

	if completed:
		add_log("Ты вернулся домой. Контракт закрыт, добыча сдана. +%d золота." % total_gold)
	else:
		add_log("Ты вернулся домой и продал добычу. +%d золота." % total_gold)

	_reset_run_state_after_resolution()
	return last_run_summary.duplicate(true)

func force_return_to_village() -> Dictionary:
	if not run_active:
		return {}
	add_log("Ты решаешь прервать вылазку и вернуться в деревню.")
	return finish_successful_return()

func finish_failed_run(reason: String) -> Dictionary:
	var lost_loot_value := get_carried_loot_value()
	var lost_loot_count := get_carried_loot_count()
	last_run_summary = {
		"status": "failure",
		"title": str(current_contract.get("title", "Без контракта")),
		"contract_completed": false,
		"reward_gold": 0,
		"lost_loot_value": lost_loot_value,
		"lost_loot_count": lost_loot_count,
		"failure_reason": reason,
		"progress_text": get_contract_progress_text()
	}

	add_log("Вылазка провалена: %s." % _failure_label(reason))
	_reset_run_state_after_resolution()
	return last_run_summary.duplicate(true)

func _reset_run_state_after_resolution() -> void:
	run_active = false
	in_village = true
	has_left_home_this_run = false
	current_contract.clear()
	selected_contract.clear()
	contract_progress = {"kills_by_pack": {}, "tracks": {}}
	carried_loot.clear()
	world.clear()
	observations.clear()
	combat_snapshot.clear()
	player_pos = home_pos
	exploration_turn_phase = "sense"
	player_hp = player_max_hp
	emit_signal("contract_changed")
	emit_signal("village_updated")
	emit_signal("run_inventory_changed")
	request_autosave()

func get_backpack_upgrade_cost() -> int:
	return 20 + backpack_level * 15

func buy_backpack_upgrade() -> bool:
	if not in_village:
		return false

	var cost := get_backpack_upgrade_cost()
	if gold < cost:
		add_log("Недостаточно золота для улучшения рюкзака.")
		return false

	gold -= cost
	backpack_level += 1
	backpack_capacity += 2
	add_log("Рюкзак улучшен до %d слотов." % backpack_capacity)
	emit_signal("village_updated")
	emit_signal("run_inventory_changed")
	request_autosave()
	return true

func mark_current_state(state_name: String) -> void:
	current_state_name = state_name
	request_autosave()

func request_autosave() -> void:
	_autosave_dirty = true

func has_autosave() -> bool:
	return FileAccess.file_exists(AUTOSAVE_PATH)

func try_resume_autosave() -> bool:
	if not has_autosave():
		return false

	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if file == null:
		return false

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	from_dict(parsed)
	add_log("Автосейв загружен.")
	return true

func autosave_now() -> bool:
	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open autosave file for writing: " + AUTOSAVE_PATH)
		return false

	file.store_string(JSON.stringify(to_dict()))
	file.close()
	return true

func clear_autosave() -> void:
	if FileAccess.file_exists(AUTOSAVE_PATH):
		DirAccess.remove_absolute(AUTOSAVE_PATH)
 
func to_dict() -> Dictionary:
	var world_list: Array = []
	for pos in world.keys():
		var cell: Dictionary = world[pos]
		world_list.append({
			"pos": [pos.x, pos.y],
			"cell": cell
		})

	var obs_list: Array = []
	for obs in observations:
		var entry: Dictionary = {
			"sense_type": obs.get("sense_type", ""),
			"kind": obs.get("kind", ""),
			"content": obs.get("content", ""),
			"text": obs.get("text", "")
		}

		var source_pos: Vector2i = obs.get("source_pos", Vector2i.ZERO)
		entry["source_pos"] = [source_pos.x, source_pos.y]

		if obs.has("shape"):
			entry["shape"] = obs.get("shape", "")
		if obs.has("intensity"):
			entry["intensity"] = int(obs.get("intensity", 1))

		var trail_cells: Array = []
		for p in obs.get("trail_cells", []):
			if typeof(p) == TYPE_VECTOR2I:
				trail_cells.append([p.x, p.y])
		entry["trail_cells"] = trail_cells
		obs_list.append(entry)

	var combat_data: Dictionary = combat_snapshot.duplicate(true)
	if current_state_name == "CombatState":
		var combat_manager = get_tree().get_first_node_in_group("combat_manager")
		if combat_manager and combat_manager.has_method("to_dict"):
			combat_data = combat_manager.to_dict()

	return {
		"seed_value": seed_value,
		"player_max_hp": player_max_hp,
		"player_hp": player_hp,
		"skills": skills,
		"home_pos": [home_pos.x, home_pos.y],
		"in_village": in_village,
		"gold": gold,
		"backpack_level": backpack_level,
		"backpack_capacity": backpack_capacity,
		"last_run_summary": last_run_summary,
		"selected_contract": selected_contract,
		"run_active": run_active,
		"has_left_home_this_run": has_left_home_this_run,
		"current_contract": current_contract,
		"contract_progress": contract_progress,
		"carried_loot": carried_loot,
		"current_state_name": current_state_name,
		"combat_snapshot": combat_data,
		"player_pos": [player_pos.x, player_pos.y],
		"world_list": world_list,
		"observations": obs_list,
		"exploration_turn_phase": exploration_turn_phase,
		"log": log
	}

func from_dict(data: Dictionary) -> void:
	seed_value = int(data.get("seed_value", 0))
	player_max_hp = int(data.get("player_max_hp", 3))
	player_hp = int(data.get("player_hp", player_max_hp))
	skills = data.get("skills", {"hearing": 1, "smell": 1, "echo": 1})

	var home_arr = data.get("home_pos", [0, 0])
	home_pos = Vector2i(int(home_arr[0]), int(home_arr[1]))
	in_village = bool(data.get("in_village", true))
	gold = int(data.get("gold", 0))
	backpack_level = int(data.get("backpack_level", 0))
	backpack_capacity = int(data.get("backpack_capacity", 8))
	last_run_summary = data.get("last_run_summary", {})
	selected_contract = data.get("selected_contract", {})
	
	run_active = bool(data.get("run_active", false))
	has_left_home_this_run = bool(data.get("has_left_home_this_run", false))
	current_contract = data.get("current_contract", {})
	contract_progress = data.get("contract_progress", {"kills_by_pack": {}, "tracks": {}})
	carried_loot = data.get("carried_loot", [])
	current_state_name = str(data.get("current_state_name", "VillageState"))
	combat_snapshot = data.get("combat_snapshot", {})

	var pp = data.get("player_pos", [0, 0])
	player_pos = Vector2i(int(pp[0]), int(pp[1]))

	exploration_turn_phase = str(data.get("exploration_turn_phase", "sense"))
	if exploration_turn_phase != "sense" and exploration_turn_phase != "move":
		exploration_turn_phase = "sense"

	world.clear()
	var world_list: Array = data.get("world_list", [])
	if world_list is Array:
		for entry in world_list:
			var p = entry.get("pos", [0, 0])
			var pos := Vector2i(int(p[0]), int(p[1]))
			var cell: Dictionary = entry.get("cell", {})
			world[pos] = cell

	observations.clear()
	var raw_obs = data.get("observations", [])
	if raw_obs is Array:
		for obs in raw_obs:
			var sense_type := str(obs.get("sense_type", ""))
			var kind := str(obs.get("kind", ""))
			var entry := {
				"sense_type": sense_type,
				"kind": kind,
				"content": obs.get("content", ""),
				"text": obs.get("text", "")
			}

			var source_arr = obs.get("source_pos", [0, 0])
			entry["source_pos"] = Vector2i(int(source_arr[0]), int(source_arr[1]))

			if obs.has("shape"):
				entry["shape"] = obs.get("shape", "")
			if obs.has("intensity"):
				entry["intensity"] = int(obs.get("intensity", 1))

			var trail_cells: Array = []
			for p in obs.get("trail_cells", []):
				trail_cells.append(Vector2i(int(p[0]), int(p[1])))
			entry["trail_cells"] = trail_cells

			if sense_type != "" and kind != "":
				observations.append(entry)

	log.clear()
	var raw_log = data.get("log", [])
	if raw_log is Array:
		for entry in raw_log:
			log.append(str(entry))

	emit_signal("log_changed")
	emit_signal("contract_changed")
	emit_signal("village_updated")
	emit_signal("run_inventory_changed")
	emit_signal("session_loaded")

func _normalize_loot_item(item: Dictionary) -> Dictionary:
	return {
		"id": str(item.get("id", "loot_item")),
		"name": str(item.get("name", "Добыча")),
		"category": str(item.get("category", "trophy")),
		"value": max(0, int(item.get("value", 0))),
		"slots": max(1, int(item.get("slots", 1))),
		"source": str(item.get("source", "unknown")),
		"quality": str(item.get("quality", "normal"))
	}

func _pack_label(pack: String) -> String:
	match pack:
		"dogs":
			return "Волки"
		"large_enemy":
			return "Крупный монстр"
		_:
			return pack

func _failure_label(reason: String) -> String:
	match reason:
		"combat_defeat":
			return "охотник пал в бою"
		_:
			return reason
