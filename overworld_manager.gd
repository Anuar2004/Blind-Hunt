extends Node
class_name OverworldManager

signal encounter_requested(data: Dictionary)
signal run_returned_home(data: Dictionary)
signal world_changed

const CELL_SIZE := 64
const CONTENT_DB_PATH := "res://data/overworld_content.json"

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

var content_db: Dictionary = {}
var spawn_table: Array = []
var signal_spawn_table: Dictionary = {}

var signal_profiles: Dictionary = {}
var reaction_profiles: Dictionary = {}
var effect_presets: Dictionary = {}


func _ready():
	randomize()
	_load_content_db()
	_normalize_existing_world()
	ensure_ring_with_minimum_signals(Session.player_pos)

# ------------------------------------------------------------
# CONTENT DB
# ------------------------------------------------------------

func _load_content_db() -> void:
	content_db.clear()
	spawn_table.clear()
	signal_spawn_table.clear()
	signal_profiles.clear()
	reaction_profiles.clear()
	effect_presets.clear()

	if not FileAccess.file_exists(CONTENT_DB_PATH):
		push_warning("Content DB not found: " + CONTENT_DB_PATH + ". Using built-in fallback content.")
		_build_default_spawn_tables_if_needed()
		return

	var file := FileAccess.open(CONTENT_DB_PATH, FileAccess.READ)
	if file == null:
		push_warning("Cannot open content DB: " + CONTENT_DB_PATH + ". Using built-in fallback content.")
		_build_default_spawn_tables_if_needed()
		return

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid content DB JSON: " + CONTENT_DB_PATH + ". Using built-in fallback content.")
		_build_default_spawn_tables_if_needed()
		return

	var root: Dictionary = parsed

	if root.has("signal_profiles") and root["signal_profiles"] is Dictionary:
		signal_profiles = (root["signal_profiles"] as Dictionary).duplicate(true)

	if root.has("reaction_profiles") and root["reaction_profiles"] is Dictionary:
		reaction_profiles = (root["reaction_profiles"] as Dictionary).duplicate(true)

	if root.has("effect_presets") and root["effect_presets"] is Dictionary:
		effect_presets = (root["effect_presets"] as Dictionary).duplicate(true)

	if root.has("content_types"):
		var raw_content_types = root.get("content_types", {})
		if raw_content_types is Dictionary:
			content_db = (raw_content_types as Dictionary).duplicate(true)

		var raw_spawn = root.get("spawn_table", [])
		if raw_spawn is Array:
			spawn_table = (raw_spawn as Array).duplicate(true)

		var raw_signal_table = root.get("signal_spawn_table", {})
		if raw_signal_table is Dictionary:
			signal_spawn_table = (raw_signal_table as Dictionary).duplicate(true)
	else:
		content_db = root.duplicate(true)

	_build_default_spawn_tables_if_needed()

func _build_default_spawn_tables_if_needed() -> void:
	if spawn_table.is_empty():
		spawn_table = [
			{"type": "fungus_patch", "weight": 16},
			{"type": "traders", "weight": 14},
			{"type": "wolf_pack", "weight": 14},
			{"type": "large_enemy", "weight": 10},
			{"type": "campfire", "weight": 15},
			{"type": "blood_stain", "weight": 13},
			{"type": "pit", "weight": 10},
			{"type": "ruins", "weight": 8}
		]

	if signal_spawn_table.is_empty():
		signal_spawn_table = {
			SIGNAL_SOUND: ["traders", "wolf_pack", "large_enemy", "campfire"],
			SIGNAL_SMELL: ["fungus_patch", "blood_stain", "wolf_pack", "large_enemy", "campfire"],
			SIGNAL_ECHO: ["ruins", "pit", "traders", "wolf_pack", "campfire", "fungus_patch"]
		}

func _get_content_payload(content_type: String) -> Dictionary:
	if content_db.has(content_type):
		var data = content_db[content_type]
		if data is Dictionary:
			return (data as Dictionary).duplicate(true)

	return _make_fallback_content_data(content_type)

func _pick_weighted_content_type(table: Array) -> String:
	var total_weight := 0

	for entry in table:
		if entry is Dictionary:
			total_weight += max(0, int(entry.get("weight", 0)))

	if total_weight <= 0:
		return "ruins"

	var roll := randi() % total_weight
	var acc := 0

	for entry in table:
		if not (entry is Dictionary):
			continue

		var weight = max(0, int(entry.get("weight", 0)))
		if weight <= 0:
			continue

		acc += weight
		if roll < acc:
			return str(entry.get("type", "ruins"))

	return "ruins"

# ------------------------------------------------------------
# MOVEMENT
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
	if not Session.run_active:
		Session.add_log("Сначала начни забег из деревни.")
		return

	if not can_move():
		Session.add_log("Сначала используй одно чувство, затем двигайся.")
		return

	Session.player_pos += dir
	Session.add_log("Ты сделал шаг.")

	if Session.player_pos != Session.home_pos:
		Session.has_left_home_this_run = true

	exploration_turn_phase_after_move()

	if Session.has_left_home_this_run and Session.player_pos == Session.home_pos:
		var summary := Session.finish_successful_return()
		emit_signal("world_changed")
		emit_signal("run_returned_home", summary)
		return

	ensure_ring_with_minimum_signals(Session.player_pos)
	_mark_current_cell_visited()
	resolve_current_cell()
	emit_signal("world_changed")
	Session.request_autosave()

func return_to_village_now() -> void:
	if not Session.run_active:
		Session.add_log("Сейчас нет активной вылазки.")
		return

	var summary := Session.force_return_to_village()
	emit_signal("world_changed")
	emit_signal("run_returned_home", summary)

# ------------------------------------------------------------
# GENERATION / NORMALIZATION
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
		"visited": false,
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
		if bool(missing.get(signal_name, false)) and _cell_has_signal(cell, signal_name):
			missing[signal_name] = false

func _apply_content_type(cell: Dictionary, content_type: String) -> void:
	cell["content_type"] = content_type
	cell["content"] = _make_content_data(content_type)

func _random_content_type() -> String:
	return _pick_weighted_content_type(spawn_table)

func _random_content_type_for_signal(signal_name: String) -> String:
	if signal_spawn_table.has(signal_name):
		var candidates = signal_spawn_table[signal_name]
		if candidates is Array and not (candidates as Array).is_empty():
			return str((candidates as Array).pick_random())
	return _random_content_type()

func _make_content_data(content_type: String) -> Dictionary:
	var raw := _get_content_payload(content_type)

	var out := {
		"id": content_type,
		"name": str(raw.get("name", content_type)),
		"category": str(raw.get("category", "generic")),
		"tags": [],
		"signals": {},
		"reactions": {},
		"enter_effects": []
	}

	var raw_tags = raw.get("tags", [])
	if raw_tags is Array:
		for tag in raw_tags:
			out["tags"].append(str(tag))

	out["signals"] = _resolve_signals(raw)
	out["reactions"] = _resolve_reactions(raw)
	out["enter_effects"] = _resolve_enter_effects(raw)

	if raw.has("encounter_pack"):
		var encounter_pack := str(raw.get("encounter_pack", ""))
		if encounter_pack != "":
			out["enter_effects"].append({
				"type": "start_encounter",
				"enemy_pack": encounter_pack
			})

	return out

func _resolve_signals(raw: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}

	var inline_signals = raw.get("signals", {})
	if inline_signals is Dictionary:
		for signal_name in (inline_signals as Dictionary).keys():
			var entry = inline_signals[signal_name]
			if entry is Dictionary:
				resolved[signal_name] = (entry as Dictionary).duplicate(true)

	var signal_refs = raw.get("signal_refs", {})
	if signal_refs is Dictionary:
		for signal_name in (signal_refs as Dictionary).keys():
			var ref_name := str(signal_refs[signal_name])
			var profile := _get_signal_profile(ref_name)
			if not profile.is_empty():
				resolved[signal_name] = profile

	return resolved

func _resolve_reactions(raw: Dictionary) -> Dictionary:
	var resolved := {}

	var reactions = raw.get("reactions", {})
	if reactions is Dictionary:
		for key in (reactions as Dictionary).keys():
			var value = reactions[key]
			if value is String:
				resolved[key] = _get_reaction_profile(str(value))
			elif value is Dictionary:
				resolved[key] = (value as Dictionary).duplicate(true)

	if resolved.is_empty() and raw.has("echo_reaction"):
		var legacy_reaction := str(raw.get("echo_reaction", "none"))
		resolved["echo"] = _get_reaction_profile(legacy_reaction)

	if not resolved.has("echo"):
		resolved["echo"] = _get_reaction_profile("none")

	return resolved

func _resolve_enter_effects(raw: Dictionary) -> Array:
	var result: Array = []

	var effects = raw.get("enter_effects", [])
	if effects is Array:
		for effect in effects:
			if effect is String:
				var preset := _get_effect_preset(str(effect))
				if not preset.is_empty():
					result.append(preset)
			elif effect is Dictionary:
				result.append((effect as Dictionary).duplicate(true))

	return result

func _get_signal_profile(profile_name: String) -> Dictionary:
	if signal_profiles.has(profile_name):
		var data = signal_profiles[profile_name]
		if data is Dictionary:
			return (data as Dictionary).duplicate(true)
	return {}

func _get_reaction_profile(profile_name: String) -> Dictionary:
	if reaction_profiles.has(profile_name):
		var data = reaction_profiles[profile_name]
		if data is Dictionary:
			return (data as Dictionary).duplicate(true)

	match profile_name:
		"flee":
			return {
				"type": "replace_self",
				"new_content_type": "blood_stain",
				"set_resolved": true,
				"clear_alerted": true,
				"log": "Голоса в панике стихли: кто-то бросился прочь от твоего крика."
			}
		"investigate":
			return {
				"type": "alert",
				"log": "Где-то рядом что-то насторожилось от твоего крика.",
				"intensity_delta": 1
			}
		"aggressive":
			return {
				"type": "alert",
				"log": "Твой крик мог привлечь что-то крупное и опасное.",
				"intensity_delta": 1
			}
		_:
			return {"type": "none"}

func _get_effect_preset(preset_name: String) -> Dictionary:
	if effect_presets.has(preset_name):
		var data = effect_presets[preset_name]
		if data is Dictionary:
			return (data as Dictionary).duplicate(true)
	return {}

func _make_fallback_content_data(content_type: String) -> Dictionary:
	match content_type:
		"fungus_patch":
			return {
				"id": "fungus_patch",
				"name": "грибная рассада",
				"category": "resource",
				"tags": ["nature", "food"],
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
				"reactions": { "echo": {"type": "none"} },
				"enter_effects": []
			}
		"traders":
			return {
				"id": "traders",
				"name": "группа торговцев",
				"category": "npc",
				"tags": ["human", "social"],
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
				"reactions": {
					"echo": {
						"type": "replace_self",
						"new_content_type": "blood_stain",
						"set_resolved": true,
						"clear_alerted": true,
						"log": "Голоса в панике стихли: кто-то бросился прочь от твоего крика."
					}
				},
				"enter_effects": []
			}
		"wolf_pack":
			return {
				"id": "wolf_pack",
				"name": "стая волков",
				"category": "enemy",
				"tags": ["beast", "danger"],
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
				"reactions": {
					"echo": {
						"type": "alert",
						"log": "Где-то рядом что-то насторожилось от твоего крика.",
						"intensity_delta": 1
					}
				},
				"enter_effects": [
					{"type": "start_encounter", "enemy_pack": "dogs"}
				]
			}
		"large_enemy":
			return {
				"id": "large_enemy",
				"name": "крупный монстр",
				"category": "boss_enemy",
				"tags": ["monster", "danger"],
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
				"reactions": {
					"echo": {
						"type": "alert",
						"log": "Твой крик мог привлечь что-то крупное и опасное.",
						"intensity_delta": 1
					}
				},
				"enter_effects": [
					{"type": "start_encounter", "enemy_pack": "large_enemy"}
				]
			}
		"campfire":
			return {
				"id": "campfire",
				"name": "потухающий костёр",
				"category": "world_object",
				"tags": ["fire"],
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
				"reactions": { "echo": {"type": "none"} },
				"enter_effects": []
			}
		"blood_stain":
			return {
				"id": "blood_stain",
				"name": "след крови",
				"category": "trace",
				"tags": ["blood", "trail"],
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
				"reactions": { "echo": {"type": "none"} },
				"enter_effects": []
			}
		"pit":
			return {
				"id": "pit",
				"name": "яма",
				"category": "hazard",
				"tags": ["terrain", "danger"],
				"signals": {
					SIGNAL_ECHO: {
						"shape": "pit",
						"brief": "пустой провал",
						"mid": "углубление в земле",
						"detail": "резкий провал рельефа с пустым центром"
					}
				},
				"reactions": { "echo": {"type": "none"} },
				"enter_effects": []
			}
		"empty":
			return {
				"id": "empty",
				"name": "пустая клетка",
				"category": "empty",
				"tags": ["neutral"],
				"signals": {},
				"reactions": { "echo": {"type": "none"} },
				"enter_effects": []
			}
		_:
			return {
				"id": "ruins",
				"name": "развалины",
				"category": "terrain",
				"tags": ["stone", "obstacle"],
				"signals": {
					SIGNAL_ECHO: {
						"shape": "wall",
						"brief": "высокий контур",
						"mid": "жёсткая преграда",
						"detail": "ровный высокий силуэт, похожий на стену или камень"
					}
				},
				"reactions": { "echo": {"type": "none"} },
				"enter_effects": []
			}

func _cell_has_signal(cell: Dictionary, signal_name: String) -> bool:
	var content: Dictionary = cell.get("content", {})
	var signals: Dictionary = content.get("signals", {})
	return signals.has(signal_name)

# ------------------------------------------------------------
# SENSES
# ------------------------------------------------------------

func use_sense(sense_type: String, level: int) -> Array:
	if not Session.run_active:
		Session.add_log("Сначала начни забег из деревни.")
		return []

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
	Session.request_autosave()
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
		if bool(cell.get("visited", false)):
			continue
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
		if bool(cell.get("visited", false)):
			continue
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
	return _sense_echo_internal(origin, level, true)

func _sense_echo_passive(origin: Vector2i, level: int) -> Array:
	return _sense_echo_internal(origin, level, false)

func _sense_echo_internal(origin: Vector2i, level: int, apply_reactions: bool) -> Array:
	var result: Array = []

	for pos in Session.world.keys():
		if not _is_adjacent_cell(origin, pos):
			continue

		var cell: Dictionary = Session.world[pos]
		_normalize_cell(cell)
		if bool(cell.get("visited", false)):
			continue
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

		if apply_reactions:
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
	var reactions: Dictionary = cell.get("content", {}).get("reactions", {})
	var reaction: Dictionary = reactions.get("echo", {"type": "none"})

	match str(reaction.get("type", "none")):
		"alert":
			_apply_alert_reaction(cell, reaction)
		"replace_self":
			_apply_replace_self_reaction(pos, cell, reaction)
		"none":
			pass
		_:
			pass

func _apply_alert_reaction(cell: Dictionary, reaction: Dictionary) -> void:
	if bool(cell.get("alerted", false)):
		return

	cell["alerted"] = true
	var delta := int(reaction.get("intensity_delta", 1))
	cell["intensity"] = min(5, int(cell.get("intensity", 1)) + delta)

	var msg := str(reaction.get("log", "Что-то насторожилось от твоего действия."))
	if msg != "":
		Session.add_log(msg)

func _apply_replace_self_reaction(pos: Vector2i, cell: Dictionary, reaction: Dictionary) -> void:
	if bool(cell.get("resolved", false)):
		return

	var new_content_type := str(reaction.get("new_content_type", "empty"))
	_apply_content_type(cell, new_content_type)

	if bool(reaction.get("set_resolved", true)):
		cell["resolved"] = true

	if bool(reaction.get("clear_alerted", false)):
		cell["alerted"] = false

	var msg := str(reaction.get("log", "Содержимое клетки изменилось."))
	if msg != "":
		Session.add_log(msg)

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
# ENTER CELL
# ------------------------------------------------------------

func resolve_current_cell() -> void:
	var cell = Session.world.get(Session.player_pos, null)
	if cell == null:
		return

	_normalize_cell(cell)

	if bool(cell.get("resolved", false)):
		return

	var content: Dictionary = cell.get("content", {})
	var effects: Array = content.get("enter_effects", [])
	if effects.is_empty():
		return

	for effect in effects:
		if effect is Dictionary:
			var should_stop := _apply_cell_effect(cell, effect)
			if should_stop:
				break

	emit_signal("world_changed")

func _apply_cell_effect(cell: Dictionary, effect: Dictionary) -> bool:
	match str(effect.get("type", "")):
		"start_encounter":
			cell["resolved"] = true
			Session.add_log("Опасность совсем рядом!")

			var encounter := {
				"encounter_id": str(Time.get_unix_time_from_system()),
				"source_cell": Session.player_pos,
				"kind": "combat",
				"enemy_pack": str(effect.get("enemy_pack", "large_enemy")),
				"danger": int(cell.get("intensity", 1)),
				"seed": int(Session.seed_value)
			}

			emit_signal("encounter_requested", encounter)
			return true

		"log":
			var text := str(effect.get("text", ""))
			if text != "":
				Session.add_log(text)

		"heal":
			var amount := int(effect.get("amount", 0))
			var player := get_tree().get_first_node_in_group("player")
			if player and player.has_method("heal"):
				player.heal(amount)

		"damage":
			var dmg := int(effect.get("amount", 0))
			var player2 := get_tree().get_first_node_in_group("player")
			if player2 and player2.has_method("take_damage"):
				player2.take_damage(dmg)

		"grant_loot":
			var loot_item = effect.get("item", {})
			if loot_item is Dictionary:
				Session.add_loot((loot_item as Dictionary).duplicate(true))

		"register_track":
			Session.register_track(str(effect.get("track_id", "")), int(effect.get("count", 1)))

		"replace_content":
			var new_type := str(effect.get("new_content_type", "empty"))
			_apply_content_type(cell, new_type)
			if bool(effect.get("set_resolved", true)):
				cell["resolved"] = true

		"set_resolved":
			cell["resolved"] = bool(effect.get("value", true))

		"reveal_adjacent":
			var sense_type := str(effect.get("sense_type", ""))
			var level := int(effect.get("level", 1))
			var apply_reactions := bool(effect.get("apply_reactions", true))
			_apply_reveal_adjacent_effect(Session.player_pos, sense_type, level, apply_reactions)

	return false

func _apply_reveal_adjacent_effect(origin: Vector2i, sense_type: String, level: int, apply_reactions: bool = true) -> void:
	var result: Array = []

	match sense_type:
		"hearing":
			result = _sense_hearing(origin, level)
		"smell":
			result = _sense_smell(origin, level)
		"echo":
			result = _sense_echo(origin, level) if apply_reactions else _sense_echo_passive(origin, level)
		_:
			return

	for entry in result:
		_store_observation(entry)

	if not result.is_empty():
		Session.add_log("Ты получаешь дополнительную подсказку через %s." % _sense_label(sense_type))

func _sense_label(sense_type: String) -> String:
	match sense_type:
		"hearing":
			return "слух"
		"smell":
			return "нюх"
		"echo":
			return "эхо"
		_:
			return sense_type

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
	Session.request_autosave()

func use_sense_by_skill(sense_type: String) -> Array:
	var level := int(Session.skills.get(sense_type, 1))
	return use_sense(sense_type, level)

func _mark_current_cell_visited() -> void:
	if not Session.world.has(Session.player_pos):
		return

	var cell: Dictionary = Session.world[Session.player_pos]
	cell["visited"] = true

	var filtered_observations: Array = []
	for entry_value in Session.observations:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_value
		var source_pos = entry.get("source_pos", Vector2i.ZERO)

		if typeof(source_pos) == TYPE_VECTOR2I and source_pos == Session.player_pos:
			continue

		filtered_observations.append(entry)

	Session.observations = filtered_observations
