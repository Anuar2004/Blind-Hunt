extends Node
class_name GameSession

signal log_changed
signal session_loaded

# --- Player ---
var player_hp_max: int = 3
var player_hp: int = 3

var skills := {
	"hearing": 1,
	"smell": 1,
	"echo": 1
}

# --- Overworld ---
var world: Dictionary = {}         # Vector2i -> cell dict
var player_pos: Vector2i = Vector2i.ZERO
var observations: Array = []       # blurred memory entries

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

	player_hp_max = 3
	player_hp = player_hp_max
	skills = {"hearing": 1, "smell": 1, "echo": 1}

	world.clear()
	observations.clear()
	player_pos = Vector2i.ZERO

	log.clear()
	emit_signal("log_changed")

func add_log(msg: String) -> void:
	log.append(msg)
	if log.size() > LOG_MAX:
		log.pop_front()
	emit_signal("log_changed")

func _vec2i_to_str(v: Vector2i) -> String:
	return str(v.x) + "," + str(v.y)

func _str_to_vec2i(s: String) -> Vector2i:
	var parts := s.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func to_dict() -> Dictionary:
	# --- world ---
	# Dictionary<Vector2i, Dictionary> -> Array
	var world_list: Array = []

	for pos in world.keys():
		var cell: Dictionary = world[pos]

		world_list.append({
			"pos": [pos.x, pos.y],
			"cell": cell
		})

	# --- observations ---
	var obs_list: Array = []

	for obs in observations:
		var origin: Vector2i = obs["origin"]

		var dirs_serialized: Array = []
		for d in obs["dirs"]:
			dirs_serialized.append([d.x, d.y])

		obs_list.append({
			"origin": [origin.x, origin.y],
			"sense_type": obs["sense_type"],
			"content": obs["content"],
			"dirs": dirs_serialized
		})

	return {
		"seed_value": seed_value,
		"player_hp_max": player_hp_max,
		"player_hp": player_hp,
		"skills": skills,
		"player_pos": [player_pos.x, player_pos.y],
		"world_list": world_list,
		"observations": obs_list,
		"log": log
	}

func from_dict(data: Dictionary) -> void:
	# --- базовые параметры ---
	seed_value = int(data.get("seed_value", 0))
	player_hp_max = int(data.get("player_hp_max", 3))
	player_hp = int(data.get("player_hp", player_hp_max))
	skills = data.get("skills", {"hearing": 1, "smell": 1, "echo": 1})

	# --- player_pos ---
	var pp = data.get("player_pos", [0, 0])
	player_pos = Vector2i(int(pp[0]), int(pp[1]))

	# --- world ---
	world.clear()

	var world_list: Array = data.get("world_list", [])
	if world_list is Array:
		for entry in world_list:
			var p = entry.get("pos", [0, 0])
			var pos := Vector2i(int(p[0]), int(p[1]))

			var cell: Dictionary = entry.get("cell", {})
			world[pos] = cell

	# --- observations ---
	observations.clear()

	var raw_obs = data.get("observations", [])
	if raw_obs is Array:
		for obs in raw_obs:
			var origin_arr = obs.get("origin", [0, 0])
			var origin := Vector2i(int(origin_arr[0]), int(origin_arr[1]))

			var dirs_arr: Array = obs.get("dirs", [])
			var dirs: Array = []
			for d in dirs_arr:
				dirs.append(Vector2i(int(d[0]), int(d[1])))

			observations.append({
				"origin": origin,
				"sense_type": obs.get("sense_type", ""),
				"content": obs.get("content", ""),
				"dirs": dirs
			})

	# --- log (Array[String] безопасно) ---
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
