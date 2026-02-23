extends Node
class_name OverworldManager

signal encounter_requested(data: Dictionary)

const CELL_SIZE := 64

const DIRECTIONS := [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1, 0),               Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var world: Dictionary = {}        # Vector2i -> Dictionary (данные клетки)
var player_pos: Vector2i = Vector2i.ZERO
var observations: Array = []
var last_sense_result: Array = []
var last_sense_type: String = ""

func _ready():
	randomize()
	ensure_ring_with_minimum_senses(player_pos)

# ------------------------------------------------------------
# ДВИЖЕНИЕ
# ------------------------------------------------------------

func try_move(dir: Vector2i) -> void:
	player_pos += dir
	ensure_ring_with_minimum_senses(player_pos)
	resolve_current_cell()

# ------------------------------------------------------------
# ГЕНЕРАЦИЯ
# ------------------------------------------------------------

func ensure_ring_with_minimum_senses(center: Vector2i) -> void:
	var missing := {
		"hearing": true,
		"smell": true,
		"echo": true
	}

	var new_cells: Array = []

	for d in DIRECTIONS:
		var pos = center + d

		if world.has(pos):
			missing[world[pos]["sense_type"]] = false
		else:
			var cell := generate_cell(pos)
			world[pos] = cell
			new_cells.append(cell)
			missing[cell["sense_type"]] = false

	# Проверяем, хватает ли всех типов
	var need: Array = []
	for k in missing.keys():
		if missing[k]:
			need.append(k)

	# Если не хватает — принудительно меняем sense_type у новых клеток
	for i in range(min(need.size(), new_cells.size())):
		new_cells[i]["sense_type"] = need[i]
		new_cells[i]["content_type"] = _random_content_for(need[i])

func generate_cell(pos: Vector2i) -> Dictionary:
	var senses = ["hearing", "smell", "echo"]

	var sense = senses.pick_random()

	return {
		"pos": pos,
		"sense_type": sense,
		"content_type": _random_content_for(sense),
		"intensity": randi_range(1, 5),
		"resolved": false,
		"revealed": {
			"hearing": false,
			"smell": false,
			"echo": false
		}
	}

func _random_content_for(sense_type: String) -> String:
	match sense_type:
		"hearing":
			return ["dogs", "help", "steps"].pick_random()
		"smell":
			return ["blood", "fire", "food"].pick_random()
		"echo":
			return ["wall", "pit", "large_enemy"].pick_random()
		_:
			return "unknown"

# ------------------------------------------------------------
# СЕНСОРИКА
# ------------------------------------------------------------

func use_sense(sense_type: String, level: int) -> Array:
	last_sense_type = sense_type
	last_sense_result = []

	var result := []
	var origin := player_pos

	for d in DIRECTIONS:
		var pos = origin + d
		if not world.has(pos):
			continue

		var cell = world[pos]
		if cell["sense_type"] != sense_type:
			continue

		var dirs: Array
		match level:
			1: dirs = _get_blurred_dirs(d, 3)
			2: dirs = _get_blurred_dirs(d, 2)
			3: dirs = [d]
			_: dirs = [d]

		var content = cell["content_type"]

		var entry = {"content": content, "dirs": dirs}
		result.append(entry)
		last_sense_result.append(entry)

		_store_observation(origin, sense_type, content, dirs)

	return result

func _get_blurred_dirs(real_dir: Vector2i, spread: int) -> Array:
	var dirs := [real_dir]

	var possible := DIRECTIONS.duplicate()
	possible.erase(real_dir)
	possible.shuffle()

	for i in range(min(spread, possible.size())):
		dirs.append(possible[i])

	return dirs

# ------------------------------------------------------------
# ВХОД В КЛЕТКУ
# ------------------------------------------------------------

func resolve_current_cell() -> void:
	if not world.has(player_pos):
		return

	var cell = world[player_pos]

	if cell["content_type"] == "large_enemy" and not cell["resolved"]:
		cell["resolved"] = true

		emit_signal("encounter_requested", {
			"world_cell": player_pos,
			"danger": cell["intensity"]
		})

func _store_observation(origin: Vector2i, sense_type: String, content: String, dirs: Array) -> void:
	# Если уже есть такая запись (тот же origin + sense + content) — обновим dirs
	for obs in observations:
		if obs["origin"] == origin and obs["sense_type"] == sense_type and obs["content"] == content:
			obs["dirs"] = dirs
			return

	observations.append({
		"origin": origin,
		"sense_type": sense_type,
		"content": content,
		"dirs": dirs
	})
	
func clear_last_sense() -> void:
	last_sense_type = ""
	last_sense_result.clear()
