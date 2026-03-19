extends Node
class_name GameSession

signal log_changed
signal session_loaded

# --- Player ---
var player_max_hp: int = 200
var player_hp: int = 200

var skills := {
	"hearing": 1,
	"smell": 1,
	"echo": 1
}

# --- Overworld ---
var world: Dictionary = {}         # Vector2i -> cell dict
var player_pos: Vector2i = Vector2i.ZERO
var observations: Array = []       # sensory memory entries
var exploration_turn_phase: String = "sense"   # "sense" | "move"

# Seed (опционально)
var seed_value: int = 0

# --- Log ---
var log: Array[String] = []
const LOG_MAX := 30
const SAVE_PATH := "user://save.json"

func new_game(new_seed: int = 0) -> void:
	if new_seed == 0:
		seed_value = randi()
	else:
		seed_value = new_seed

	seed(seed_value)

	player_max_hp = 3
	player_hp = player_max_hp
	skills = {"hearing": 1, "smell": 1, "echo": 1}

	world.clear()
	observations.clear()
	player_pos = Vector2i.ZERO
	exploration_turn_phase = "sense"

	log.clear()
	emit_signal("log_changed")

func add_log(msg: String) -> void:
	log.append(msg)
	if log.size() > LOG_MAX:
		log.pop_front()
	emit_signal("log_changed")

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

	return {
		"seed_value": seed_value,
		"player_max_hp": player_max_hp,
		"player_hp": player_hp,
		"skills": skills,
		"player_pos": [player_pos.x, player_pos.y],
		"world_list": world_list,
		"observations": obs_list,
		"exploration_turn_phase": exploration_turn_phase,
		"log": log
	}

func from_dict(data: Dictionary) -> void:
	seed_value = int(data.get("seed_value", 0))
	player_max_hp = int(data.get("player_max_hp", 200))
	player_hp = int(data.get("player_hp", player_max_hp))
	skills = data.get("skills", {"hearing": 1, "smell": 1, "echo": 1})

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
	emit_signal("session_loaded")

func save_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open save file for writing: " + SAVE_PATH)
		return false

	var json_text := JSON.stringify(to_dict())
	file.store_string(json_text)
	file.close()
	add_log("Игра сохранена.")
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		add_log("Сейв не найден.")
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open save file for reading: " + SAVE_PATH)
		return false

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file corrupted or invalid JSON.")
		return false

	from_dict(parsed)
	add_log("Сейв загружен.")
	return true
