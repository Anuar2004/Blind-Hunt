extends Node
class_name OverworldManager

const CELL_SIZE := 64

const DIRECTIONS := [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1, 0),               Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var world: Dictionary = {}        # Vector2i -> Dictionary (данные клетки)
var player_pos: Vector2i = Vector2i.ZERO
var observations: Array = []

@onready var gsm := get_tree().get_first_node_in_group("gsm")
@onready var overworld_layer := get_tree().get_first_node_in_group("overworld_layer")

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
	overworld_layer.queue_redraw()

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
			1:
				dirs = _get_blurred_dirs(d, 3)
			2:
				dirs = _get_blurred_dirs(d, 2)
			3:
				dirs = [d]
			_:
				dirs = [d]

		var content = cell["content_type"]

		# 1) Возвращаем для мгновенного отображения (как сейчас)
		result.append({
			"content": content,
			"dirs": dirs
		})

		# 2) Сохраняем именно РАЗМЫТУЮ информацию в память игрока
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
		gsm.change_state("CombatState", {
			"world_cell": player_pos,
			"danger": cell["intensity"]
		})
		cell["resolved"] = true

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
