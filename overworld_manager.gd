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

const SIGNAL_SOUND := "sound"
const SIGNAL_SMELL := "smell"
const SIGNAL_ECHO := "echo"

var last_sense_result: Array = []
var last_sense_type: String = ""


func _ready():
	randomize()
	_normalize_existing_world()
	ensure_ring_with_minimum_signals(Session.player_pos)

# ------------------------------------------------------------
# ДВИЖЕНИЕ
# ------------------------------------------------------------

func can_use_sense() -> bool:
	return Session.exploration_turn_phase == "sense"

func can_move() -> bool:
	return Session.exploration_turn_phase == "move"

func exploration_turn_phase_after_move() -> void:
	Session.exploration_turn_phase = "sense"
	last_sense_type = ""
	last_sense_result.clear()

func try_move(dir: Vector2i) -> void:
	if not can_move():
		Session.add_log("Сначала используй одно чувство, затем двигайся.")
		return

	Session.player_pos += dir
	Session.add_log("Ты сделал шаг.")

	exploration_turn_phase_after_move()

	ensure_ring_with_minimum_signals(Session.player_pos)
	resolve_current_cell()
	emit_signal("world_changed")

# ------------------------------------------------------------
# ГЕНЕРАЦИЯ / НОРМАЛИЗАЦИЯ
# ------------------------------------------------------------

func ensure_ring_with_minimum_signals(center: Vector2i) -> void:
	var missing := {
		SIGNAL_SOUND: true,
		SIGNAL_SMELL: true,
		SIGNAL_ECHO: true
	}

	var new_positions: Array[Vector2i] = []

	for d in DIRECTIONS:
		var pos = center + d

		if Session.world.has(pos):
			_normalize_cell(Session.world[pos])
			_mark_signals_present(Session.world[pos], missing)
		else:
			var cell := generate_cell(pos)
			Session.world[pos] = cell
			new_positions.append(pos)
			_mark_signals_present(cell, missing)

	for signal_name in missing.keys():
		if not missing[signal_name]:
			continue
		for pos in new_positions:
			var candidate: Dictionary = Session.world[pos]
			if _cell_has_signal(candidate, signal_name):
				missing[signal_name] = false
				break

			var forced_type := _random_content_type_for_signal(signal_name)
			_apply_content_type(candidate, forced_type)
			missing[signal_name] = false
			break

func generate_cell(pos: Vector2i) -> Dictionary:
	var content_type := _random_content_type()
	var cell := {
		"pos": pos,
		"content_type": content_type,
		"intensity": randi_range(1, 5),
		"resolved": false,
		"alerted": false,
		"revealed": {
			"hearing": false,
			"smell": false,
			"echo": false
		}
	}
	_apply_content_type(cell, content_type)
	return cell

func _normalize_existing_world() -> void:
	for pos in Session.world.keys():
		var cell: Dictionary = Session.world[pos]
		cell["pos"] = pos
		_normalize_cell(cell)

func _normalize_cell(cell: Dictionary) -> void:
	var content_type := str(cell.get("content_type", ""))
	if content_type == "":
		content_type = _upgrade_legacy_content_type(cell)
		cell["content_type"] = content_type

	if not cell.has("revealed"):
		cell["revealed"] = {"hearing": false, "smell": false, "echo": false}
	if not cell.has("resolved"):
		cell["resolved"] = false
	if not cell.has("alerted"):
		cell["alerted"] = false
	if not cell.has("intensity"):
		cell["intensity"] = randi_range(1, 5)

	var content: Dictionary = cell.get("content", {})
	if content.is_empty():
		cell["content"] = _make_content_data(content_type)
		return

	if not content.has("signals"):
		cell["content"] = _make_content_data(content_type)

func _upgrade_legacy_content_type(cell: Dictionary) -> String:
	var legacy := str(cell.get("content_type", "unknown"))
	match legacy:
		"dogs":
			return "wolf_pack"
		"help":
			return "traders"
		"steps":
			return "traders"
		"blood":
			return "blood_stain"
		"fire":
			return "campfire"
		"food":
			return "fungus_patch"
		"wall":
			return "ruins"
		"pit":
			return "pit"
		"large_enemy":
			return "large_enemy"
		_:
			var sense_type := str(cell.get("sense_type", ""))
			match sense_type:
				"hearing":
					return "traders"
				"smell":
					return "fungus_patch"
				"echo":
					return "ruins"
				_:
					return "ruins"

func _mark_signals_present(cell: Dictionary, missing: Dictionary) -> void:
	for signal_name in [SIGNAL_SOUND, SIGNAL_SMELL, SIGNAL_ECHO]:
		if missing.get(signal_name, false) and _cell_has_signal(cell, signal_name):
			missing[signal_name] = false

func _apply_content_type(cell: Dictionary, content_type: String) -> void:
	cell["content_type"] = content_type
	cell["content"] = _make_content_data(content_type)

func _random_content_type() -> String:
	var roll := randi() % 100
	if roll < 16:
		return "fungus_patch"
	elif roll < 30:
		return "traders"
	elif roll < 44:
		return "wolf_pack"
	elif roll < 54:
		return "large_enemy"
	elif roll < 69:
		return "campfire"
	elif roll < 82:
		return "blood_stain"
	elif roll < 92:
		return "pit"
	return "ruins"

func _random_content_type_for_signal(signal_name: String) -> String:
	match signal_name:
		SIGNAL_SOUND:
			return ["traders", "wolf_pack", "large_enemy", "campfire"].pick_random()
		SIGNAL_SMELL:
			return ["fungus_patch", "blood_stain", "wolf_pack", "large_enemy", "campfire"].pick_random()
		SIGNAL_ECHO:
			return ["ruins", "pit", "traders", "wolf_pack", "campfire", "fungus_patch"].pick_random()
		_:
			return _random_content_type()

func _make_content_data(content_type: String) -> Dictionary:
	match content_type:
		"fungus_patch":
			return {
				"name": "грибная рассада",
				"signals": {
					SIGNAL_SMELL: {
						"brief": "землистый запах",
						"mid": "грибной запах",
						"detail": "густой грибной запах влажной рассады"
					},
					SIGNAL_ECHO: {
						"shape": "roots",
						"brief": "низкий силуэт",
						"mid": "переплетение корней",
						"detail": "низкий силуэт с корневой сеткой"
					}
				},
				"echo_reaction": "none"
			}
		"traders":
			return {
				"name": "группа торговцев",
				"signals": {
					SIGNAL_SOUND: {
						"brief": "голоса",
						"mid": "разговор нескольких людей",
						"detail": "несколько людей переговариваются и переступают с ноги на ногу"
					},
					SIGNAL_ECHO: {
						"shape": "human",
						"brief": "высокий силуэт",
						"mid": "человеческий силуэт",
						"detail": "несколько человеческих силуэтов и лёгкие шаги по земле"
					}
				},
				"echo_reaction": "flee"
			}
		"wolf_pack":
			return {
				"name": "стаю волков",
				"signals": {
					SIGNAL_SOUND: {
						"brief": "рычание",
						"mid": "короткие рыки и быстрые шаги",
						"detail": "несколько зверей рычат и кружат неподалёку"
					},
					SIGNAL_SMELL: {
						"brief": "звериный запах",
						"mid": "хищный запах",
						"detail": "резкий звериный запах стаи хищников"
					},
					SIGNAL_ECHO: {
						"shape": "beast",
						"brief": "низкий силуэт",
						"mid": "несколько звериных силуэтов",
						"detail": "несколько приземистых силуэтов, быстро меняющих положение"
					}
				},
				"echo_reaction": "investigate",
				"encounter_pack": "dogs"
			}
		"large_enemy":
			return {
				"name": "крупного монстра",
				"signals": {
					SIGNAL_SOUND: {
						"brief": "тяжёлые шаги",
						"mid": "тяжёлые шаги и скрежет",
						"detail": "что-то большое и тяжёлое ломает под собой землю"
					},
					SIGNAL_SMELL: {
						"brief": "тяжёлый запах",
						"mid": "хищный запах",
						"detail": "густой хищный запах крупного зверя"
					},
					SIGNAL_ECHO: {
						"shape": "hulking",
						"brief": "массивный силуэт",
						"mid": "крупный силуэт",
						"detail": "массивный силуэт, занимающий почти всю клетку"
					}
				},
				"echo_reaction": "aggressive",
				"encounter_pack": "large_enemy"
			}
		"campfire":
			return {
				"name": "потухающий костёр",
				"signals": {
					SIGNAL_SOUND: {
						"brief": "потрескивание",
						"mid": "тихое потрескивание углей",
						"detail": "где-то рядом сухо потрескивают угли"
					},
					SIGNAL_SMELL: {
						"brief": "дым",
						"mid": "дым и гарь",
						"detail": "тянет дымом, золой и прогоревшим деревом"
					},
					SIGNAL_ECHO: {
						"shape": "low",
						"brief": "низкий силуэт",
						"mid": "низкая преграда",
						"detail": "низкий круглый силуэт вокруг углей"
					}
				},
				"echo_reaction": "none"
			}
		"blood_stain":
			return {
				"name": "след крови",
				"signals": {
					SIGNAL_SMELL: {
						"brief": "кровь",
						"mid": "свежая кровь",
						"detail": "сильный запах свежей крови"
					},
					SIGNAL_ECHO: {
						"shape": "tracks",
						"brief": "смазанный след",
						"mid": "рваный след на земле",
						"detail": "смазанный рельеф и сорванный верхний слой земли"
					}
				},
				"echo_reaction": "none"
			}
		"pit":
			return {
				"name": "яму",
				"signals": {
					SIGNAL_ECHO: {
						"shape": "pit",
						"brief": "пустой провал",
						"mid": "углубление в земле",
						"detail": "резкий провал рельефа с пустым центром"
					}
				},
				"echo_reaction": "none"
			}
		_:
			return {
				"name": "развалины",
				"signals": {
					SIGNAL_ECHO: {
						"shape": "wall",
						"brief": "высокий контур",
						"mid": "жёсткая преграда",
						"detail": "ровный высокий силуэт, похожий на стену или камень"
					}
				},
				"echo_reaction": "none"
			}

func _cell_has_signal(cell: Dictionary, signal_name: String) -> bool:
	var content: Dictionary = cell.get("content", {})
	var signals: Dictionary = content.get("signals", {})
	return signals.has(signal_name)

# ------------------------------------------------------------
# СЕНСОРИКА
# ------------------------------------------------------------

func use_sense(sense_type: String, level: int) -> Array:
	if not can_use_sense():
		Session.add_log("Ты уже использовал чувство в этом ходе. Теперь нужно двигаться.")
		return []

	last_sense_type = sense_type
	last_sense_result = []

	match sense_type:
		"hearing": Session.add_log("Ты прислушался.")
		"smell": Session.add_log("Ты принюхался.")
		"echo": Session.add_log("Ты издаёшь короткий крик и слушаешь отклик.")
		_: Session.add_log("Ты используешь чувство.")

	var result: Array = []
	var origin := Session.player_pos

	match sense_type:
		"hearing":
			result = _sense_hearing(origin, level)
		"smell":
			result = _sense_smell(origin, level)
		"echo":
			result = _sense_echo(origin, level)
		_:
			result = []

	last_sense_result = result.duplicate(true)
	for entry in result:
		_store_observation(entry)

	Session.exploration_turn_phase = "move"

	emit_signal("world_changed")
	return result

func _is_adjacent_cell(origin: Vector2i, pos: Vector2i) -> bool:
	var dx = abs(pos.x - origin.x)
	var dy = abs(pos.y - origin.y)
	return max(dx, dy) == 1

func _sense_hearing(origin: Vector2i, level: int) -> Array:
	var result: Array = []

	for pos in Session.world.keys():
		if not _is_adjacent_cell(origin, pos):
			continue

		var cell: Dictionary = Session.world[pos]
		_normalize_cell(cell)
		if not _cell_has_signal(cell, SIGNAL_SOUND):
			continue

		var sg: Dictionary = cell["content"]["signals"][SIGNAL_SOUND]
		var text := _build_hearing_text(origin, pos, sg, level)
		result.append({
			"kind": "marker",
			"sense_type": "hearing",
			"source_pos": pos,
			"content": str(cell.get("content_type", "unknown")),
			"text": text,
			"intensity": int(cell.get("intensity", 1))
		})

	return result

func _sense_smell(origin: Vector2i, level: int) -> Array:
	var result: Array = []

	for pos in Session.world.keys():
		if not _is_adjacent_cell(origin, pos):
			continue

		var cell: Dictionary = Session.world[pos]
		_normalize_cell(cell)
		if not _cell_has_signal(cell, SIGNAL_SMELL):
			continue

		var sg: Dictionary = cell["content"]["signals"][SIGNAL_SMELL]
		var text := _build_smell_text(origin, pos, sg, level)
		var trail_cells := [pos]
		result.append({
			"kind": "trail",
			"sense_type": "smell",
			"source_pos": pos,
			"content": str(cell.get("content_type", "unknown")),
			"text": text,
			"trail_cells": trail_cells,
			"intensity": int(cell.get("intensity", 1))
		})

	return result

func _sense_echo(origin: Vector2i, level: int) -> Array:
	var result: Array = []

	for pos in Session.world.keys():
		if not _is_adjacent_cell(origin, pos):
			continue

		var cell: Dictionary = Session.world[pos]
		_normalize_cell(cell)
		if not _cell_has_signal(cell, SIGNAL_ECHO):
			continue

		var sg: Dictionary = cell["content"]["signals"][SIGNAL_ECHO]
		var text := _build_echo_text(sg, level)
		result.append({
			"kind": "echo",
			"sense_type": "echo",
			"source_pos": pos,
			"content": str(cell.get("content_type", "unknown")),
			"text": text,
			"shape": str(sg.get("shape", "unknown"))
		})

		_apply_echo_reaction(pos, cell, origin)

	return result

func _build_hearing_text(origin: Vector2i, pos: Vector2i, sg: Dictionary, level: int) -> String:
	var dir_text := _direction_text(pos - origin)
	match level:
		1:
			return "%s слышно: %s" % [dir_text, str(sg.get("brief", "звук"))]
		2:
			return "%s слышно %s" % [dir_text, str(sg.get("mid", sg.get("brief", "звук")))]
		_:
			var dist_text := _distance_text(origin.distance_to(pos))
			return "%s, %s: %s" % [dir_text, dist_text, str(sg.get("detail", sg.get("mid", sg.get("brief", "звук"))))]

func _build_smell_text(origin: Vector2i, pos: Vector2i, sg: Dictionary, level: int) -> String:
	var dir_text := _direction_text(pos - origin)
	match level:
		1:
			return "%s тянет: %s" % [dir_text, str(sg.get("brief", "запах"))]
		2:
			return "%s тянет %s" % [dir_text, str(sg.get("mid", sg.get("brief", "запах")))]
		_:
			var dist_text := _distance_text(origin.distance_to(pos))
			return "%s, %s: %s" % [dir_text, dist_text, str(sg.get("detail", sg.get("mid", sg.get("brief", "запах"))))]

func _build_echo_text(sg: Dictionary, level: int) -> String:
	match level:
		1:
			return str(sg.get("brief", "силуэт"))
		2:
			return str(sg.get("mid", sg.get("brief", "силуэт")))
		_:
			return str(sg.get("detail", sg.get("mid", sg.get("brief", "силуэт"))))

func _apply_echo_reaction(pos: Vector2i, cell: Dictionary, origin: Vector2i) -> void:
	var reaction := str(cell.get("content", {}).get("echo_reaction", "none"))
	match reaction:
		"flee":
			_apply_flee_reaction(pos, cell, origin)
		"investigate":
			_apply_alert_reaction(cell, "Где-то рядом что-то насторожилось от твоего крика.")
		"aggressive":
			_apply_alert_reaction(cell, "Твой крик мог привлечь что-то крупное и опасное.")
		_:
			pass

func _apply_alert_reaction(cell: Dictionary, msg: String) -> void:
	if bool(cell.get("alerted", false)):
		return
	cell["alerted"] = true
	cell["intensity"] = min(5, int(cell.get("intensity", 1)) + 1)
	Session.add_log(msg)

func _apply_flee_reaction(pos: Vector2i, cell: Dictionary, origin: Vector2i) -> void:
	if bool(cell.get("resolved", false)):
		return
	cell["resolved"] = true
	_apply_content_type(cell, "blood_stain")
	cell["alerted"] = false
	Session.add_log("Голоса в панике стихли: кто-то бросился прочь от твоего крика.")

func _build_trail_cells(origin: Vector2i, target: Vector2i, length: int) -> Array:
	var cells: Array = []
	var current := origin

	for _i in range(length):
		if current == target:
			break
		var step := _step_towards(current, target)
		if step == Vector2i.ZERO:
			break
		current += step
		cells.append(current)
		if current == target:
			break

	return cells

func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx = sign(to.x - from.x)
	var dy = sign(to.y - from.y)
	return Vector2i(dx, dy)

func _direction_text(delta: Vector2i) -> String:
	var sx = sign(delta.x)
	var sy = sign(delta.y)
	if sx == 0 and sy == -1:
		return "С севера"
	if sx == 1 and sy == -1:
		return "С северо-востока"
	if sx == 1 and sy == 0:
		return "С востока"
	if sx == 1 and sy == 1:
		return "С юго-востока"
	if sx == 0 and sy == 1:
		return "С юга"
	if sx == -1 and sy == 1:
		return "С юго-запада"
	if sx == -1 and sy == 0:
		return "С запада"
	if sx == -1 and sy == -1:
		return "С северо-запада"
	return "Совсем рядом"

func _distance_text(dist: float) -> String:
	if dist <= 1.5:
		return "совсем рядом"
	if dist <= 3.0:
		return "недалеко"
	return "дальше"

# ------------------------------------------------------------
# ВХОД В КЛЕТКУ
# ------------------------------------------------------------

func resolve_current_cell() -> void:
	var cell = Session.world.get(Session.player_pos, null)
	if cell == null:
		return

	_normalize_cell(cell)

	var encounter_pack := str(cell.get("content", {}).get("encounter_pack", ""))
	if encounter_pack != "" and not cell.get("resolved", false):
		cell["resolved"] = true
		Session.add_log("Опасность совсем рядом!")

		var encounter := {
			"encounter_id": str(Time.get_unix_time_from_system()),
			"source_cell": Session.player_pos,
			"kind": "combat",
			"enemy_pack": encounter_pack,
			"danger": int(cell.get("intensity", 1)),
			"seed": int(Session.seed_value)
		}

		emit_signal("encounter_requested", encounter)

func _store_observation(entry: Dictionary) -> void:
	var source_pos: Vector2i = entry.get("source_pos", Vector2i.ZERO)
	var sense_type := str(entry.get("sense_type", ""))
	var kind := str(entry.get("kind", ""))

	for i in range(Session.observations.size()):
		var obs: Dictionary = Session.observations[i]
		var obs_source: Variant = obs.get("source_pos", Vector2i.ZERO)
		if typeof(obs_source) != TYPE_VECTOR2I:
			obs_source = Vector2i.ZERO
		if obs_source == source_pos and str(obs.get("sense_type", "")) == sense_type and str(obs.get("kind", "")) == kind:
			Session.observations[i] = entry.duplicate(true)
			return

	Session.observations.append(entry.duplicate(true))

func clear_last_sense() -> void:
	last_sense_type = ""
	last_sense_result.clear()
	Session.add_log("Ты даёшь миру снова затихнуть.")
	emit_signal("world_changed")

func use_sense_by_skill(sense_type: String) -> Array:
	var level := int(Session.skills.get(sense_type, 1))
	return use_sense(sense_type, level)
