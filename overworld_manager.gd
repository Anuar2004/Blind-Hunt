extends Node
class_name OverworldManager

signal encounter_requested(data: Dictionary)
signal world_changed

const CELL_SIZE := 64

const DIRECTIONS := [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1, 0),               Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var last_sense_result: Array = []
var last_sense_type: String = ""

func _ready():
	randomize()
	ensure_ring_with_minimum_senses(Session.player_pos)

# ------------------------------------------------------------
# ДВИЖЕНИЕ
# ------------------------------------------------------------

func try_move(dir: Vector2i) -> void:
	Session.player_pos += dir
	Session.add_log("Ты сделал шаг.")
	ensure_ring_with_minimum_senses(Session.player_pos)
	resolve_current_cell()
	emit_signal("world_changed")

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

		if Session.world.has(pos):
			var st = Session.world[pos].get("sense_type", "")
			if missing.has(st):
				missing[st] = false
		else:
			var cell := generate_cell(pos)
			Session.world[pos] = cell
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

	match sense_type:
		"hearing": Session.add_log("Ты прислушался.")
		"smell": Session.add_log("Ты принюхался.")
		"echo": Session.add_log("Ты прислушался к эху.")
		_: Session.add_log("Ты используешь чувство.")

	var result := []
	var origin := Session.player_pos

	for d in DIRECTIONS:
		var pos = origin + d
		if not Session.world.has(pos):
			continue

		var cell = Session.world[pos]
		if cell.get("sense_type", "") != sense_type:
			continue

		var dirs: Array
		match level:
			1: dirs = _get_blurred_dirs(d, 3)
			2: dirs = _get_blurred_dirs(d, 2)
			3: dirs = [d]
			_: dirs = [d]

		var content = str(cell.get("content_type", "unknown"))

		var entry = {"content": content, "dirs": dirs}
		result.append(entry)
		last_sense_result.append(entry)

		_store_observation(origin, sense_type, content, dirs)

	emit_signal("world_changed")
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
	var cell = Session.world.get(Session.player_pos, null)
	if cell == null:
		return

	if cell.get("content_type", "") == "large_enemy" and not cell.get("resolved", false):
		cell["resolved"] = true

		Session.add_log("Опасность совсем рядом!")

		# EncounterData (контракт на вход в бой)
		var encounter := {
			"encounter_id": str(Time.get_unix_time_from_system()),
			"source_cell": Session.player_pos,
			"kind": "combat",
			"enemy_pack": "large_enemy",
			"danger": int(cell.get("intensity", 1)),
			"seed": int(Session.seed_value)
		}

		emit_signal("encounter_requested", encounter)

func _store_observation(origin: Vector2i, sense_type: String, content: String, dirs: Array) -> void:
	for obs in Session.observations:
		if obs["origin"] == origin and obs["sense_type"] == sense_type and obs["content"] == content:
			obs["dirs"] = dirs
			return

	Session.observations.append({
		"origin": origin,
		"sense_type": sense_type,
		"content": content,
		"dirs": dirs
	})

func clear_last_sense() -> void:
	last_sense_type = ""
	last_sense_result.clear()
	Session.add_log("Ты прекращаешь прислушиваться.")
	emit_signal("world_changed")

func use_sense_by_skill(sense_type: String) -> Array:
	var level := int(Session.skills.get(sense_type, 1))
	return use_sense(sense_type, level)
