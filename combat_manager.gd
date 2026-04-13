extends Node
class_name CombatManager

signal changed
signal combat_finished(result: Dictionary)

@onready var player := get_tree().get_first_node_in_group("player")

const W := 8
const H := 8
const BASE_UNCERTAINTY_CELLS := 10
const MAX_ENEMIES := 3

# Terrain
const TERRAIN_TREES_MIN := 6
const TERRAIN_TREES_MAX := 12
const TERRAIN_RISE_MIN := 2
const TERRAIN_RISE_MAX := 5

enum Phase { PLAYER_TURN, ENEMY_TURN, RESOLVE, END }
var phase: Phase = Phase.PLAYER_TURN

var player_grid_pos := Vector2i(3, 3)

# несколько врагов
var enemy_positions: Array[Vector2i] = []
var enemy_hps: Array[int] = []

# для совместимости/отладки
var enemy_grid_pos := Vector2i(5, 3)
var enemy_hp := 3

var active := false

# EncounterData текущего боя + hp на старте (для CombatResult)
var _current_encounter: Dictionary = {}
var _hp_at_start: int = 0
var _total_enemies_spawned: int = 0

# ------------------------------------------------------------
# Fog-of-war: отдельные кляксы по врагам
# ------------------------------------------------------------
var enemy_candidates_by_enemy: Array[Array] = [] # Array[Array[Vector2i]]
var hidden_hearing_blobs_by_enemy: Array[Array] = [] # реальные скрытые зоны по врагам
var last_combat_sense_type: String = ""
var debug_show_real_enemies := false

# ------------------------------------------------------------
# Terrain data (синий слой)
# terrain[pos] = "tree" | "rise"
# known_terrain[pos] = true  (что игрок "ощутил" touch)
# ------------------------------------------------------------
var terrain: Dictionary = {}
var known_terrain: Dictionary = {}

# ------------------------------------------------------------
# Smell layer (жёлтый)
# scent[pos] = {"kind": "blood", "intensity": int}
# known_scent[pos] = true
# ------------------------------------------------------------
var scent: Dictionary = {}
var known_scent: Dictionary = {}

# ------------------------------------------------------------
# PUBLIC API (вызывается из CombatState)
# ------------------------------------------------------------
func try_move(dir: Vector2i) -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return
	_try_player_move(dir)
	emit_signal("changed")
	Session.request_autosave()

func try_attack() -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return
	_try_player_attack()
	emit_signal("changed")
	if active:
		Session.request_autosave()

func use_sense(sense_type: String) -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return
	_use_combat_sense(sense_type)
	emit_signal("changed")
	if active:
		Session.request_autosave()

func toggle_debug_show_enemies() -> void:
	debug_show_real_enemies = not debug_show_real_enemies
	Session.add_log("DEBUG враги: " + ("ON" if debug_show_real_enemies else "OFF"))
	emit_signal("changed")

# ------------------------------------------------------------
# START / END
# ------------------------------------------------------------
func start_combat(encounter: Dictionary = {}) -> void:
	_current_encounter = encounter
	_hp_at_start = int(Session.player_hp)

	active = true
	phase = Phase.PLAYER_TURN
	last_combat_sense_type = ""

	var danger: int = int(encounter.get("danger", 1))
	var enemy_pack: String = str(encounter.get("enemy_pack", "large_enemy"))
	var base_seed: int = int(encounter.get("seed", 0))

	var rng := RandomNumberGenerator.new()
	if base_seed != 0:
		rng.seed = base_seed + int(hash(encounter.get("encounter_id", "")))
	else:
		rng.randomize()

	player_grid_pos = Vector2i(W / 2, H / 2)

	# 1) Генерим ландшафт (пока игрок один на поле)
	_generate_terrain(rng)
	
	scent.clear()
	known_scent.clear()

	# 2) Спавним врагов с учётом деревьев
	_spawn_enemies(rng, danger)
	_total_enemies_spawned = enemy_positions.size()

	# совместимость
	if not enemy_positions.is_empty():
		enemy_grid_pos = enemy_positions[0]

	match enemy_pack:
		"large_enemy":
			enemy_hp = 2 + danger
		"dogs":
			enemy_hp = 1 + danger
		_:
			enemy_hp = 2 + danger

	enemy_candidates_by_enemy.clear()
	hidden_hearing_blobs_by_enemy.clear()

	for enemy_pos in enemy_positions:
		enemy_candidates_by_enemy.append([])

		var hidden_blob := _make_hidden_hearing_blob(enemy_pos, rng)
		hidden_hearing_blobs_by_enemy.append(hidden_blob)

	# 4) В начале боя автоматически "ощутим" только ближайший ландшафт
	var touch_level := int(Session.skills.get("touch", Session.skills.get("echo", 1)))
	_reveal_terrain_by_touch(touch_level)

	Session.add_log("Начался бой.")
	emit_signal("changed")

func _make_hidden_hearing_blob(enemy_pos: Vector2i, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var target_size := rng.randi_range(10, 13)
	var blob: Array[Vector2i] = _sample_uncertainty_area(enemy_pos, target_size, rng)
	blob = _keep_only_connected_from_center(enemy_pos, blob)
	return blob

func end_combat(victory: bool) -> void:
	active = false
	phase = Phase.END

	if victory:
		Session.add_log("Ты победил в бою.")
	else:
		Session.add_log("Ты проиграл бой.")

	var loot: Array = _build_loot_for_victory() if victory else []
	var result := {
		"encounter_id": str(_current_encounter.get("encounter_id", "")),
		"source_cell": _current_encounter.get("source_cell", Vector2i.ZERO),
		"victory": victory,
		"player_hp_delta": int(Session.player_hp) - _hp_at_start,
		"world_effects": [],
		"loot": loot,
		"enemy_pack": str(_current_encounter.get("enemy_pack", "")),
		"defeated_count": _total_enemies_spawned if victory else 0
	}

	emit_signal("combat_finished", result)

func _build_loot_for_victory() -> Array:
	var loot: Array = []
	var pack := str(_current_encounter.get("enemy_pack", ""))
	var danger := int(_current_encounter.get("danger", 1))

	match pack:
		"dogs":
			for _i in range(max(1, _total_enemies_spawned)):
				loot.append({
					"id": "wolf_fang",
					"name": "Волчий клык",
					"category": "trophy",
					"value": 2,
					"slots": 1,
					"source": "dogs",
					"quality": "normal"
				})
			if _total_enemies_spawned >= 2:
				loot.append({
					"id": "wolf_pelt",
					"name": "Волчья шкура",
					"category": "trophy",
					"value": 5,
					"slots": 2,
					"source": "dogs",
					"quality": "normal"
				})
		"large_enemy":
			loot.append({
				"id": "monster_hide",
				"name": "Шкура чудовища",
				"category": "trophy",
				"value": 12,
				"slots": 4,
				"source": "large_enemy",
				"quality": "normal"
			})
			loot.append({
				"id": "monster_fang",
				"name": "Клык чудовища",
				"category": "trophy",
				"value": 5,
				"slots": 1,
				"source": "large_enemy",
				"quality": "normal"
			})
			if danger >= 3:
				loot.append({
					"id": "predator_gland",
					"name": "Хищная железа",
					"category": "rare_sample",
					"value": 7,
					"slots": 2,
					"source": "large_enemy",
					"quality": "rare"
				})
		_:
			pass

	return loot

# ------------------------------------------------------------
# SENSES
# ------------------------------------------------------------
func _use_combat_sense(sense_type: String) -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return

	var level: int
	if sense_type == "touch":
		level = int(Session.skills.get("touch", Session.skills.get("echo", 1)))
	else:
		level = int(Session.skills.get(sense_type, 1))

	Session.add_log("Ты используешь " + sense_type + ".")

	match sense_type:
		"touch":
			_reveal_terrain_by_touch(level)
		"smell":
			_reveal_scent_by_smell(level)
		"hearing":
			_apply_sense_to_all_enemies("hearing", level)
		_:
			_apply_sense_to_all_enemies(sense_type, level)

	_end_player_turn()

func _reveal_terrain_by_touch(level: int) -> void:
	last_combat_sense_type = "touch"

	var r := 1
	match level:
		1: r = 1
		2: r = 2
		3: r = 2
		_: r = 2

	for y in range(max(0, player_grid_pos.y - r), min(H, player_grid_pos.y + r + 1)):
		for x in range(max(0, player_grid_pos.x - r), min(W, player_grid_pos.x + r + 1)):
			var p := Vector2i(x, y)
			if terrain.has(p):
				known_terrain[p] = true

	Session.add_log("Ты ощупываешь пространство рядом. (радиус " + str(r) + ")")
	
func _reveal_scent_by_smell(level: int) -> void:
	last_combat_sense_type = "smell"

	if scent.is_empty():
		Session.add_log("Нюх не уловил заметного следа.")
		return

	var best_pos := Vector2i.ZERO
	var best_score := -999999
	var found := false

	for pos in scent.keys():
		if typeof(pos) != TYPE_VECTOR2I:
			continue

		var entry: Dictionary = scent[pos]
		var kind := str(entry.get("kind", ""))
		if kind != "blood":
			continue

		var intensity := int(entry.get("intensity", 1))
		var dist := int(player_grid_pos.distance_to(pos))
		var score := intensity * 10 - dist

		if not found or score > best_score:
			found = true
			best_score = score
			best_pos = pos

	if not found:
		Session.add_log("Нюх не уловил крови.")
		return

	var trail_len := 2
	match level:
		1: trail_len = 2
		2: trail_len = 3
		3: trail_len = 4
		_: trail_len = 4
	
	var trail := _build_smell_trail(player_grid_pos, best_pos, trail_len)
	for p in trail:
		known_scent[p] = true

	Session.add_log("Нюх уловил след. (длина следа " + str(trail.size()) + ")")

func _build_smell_trail(from: Vector2i, to: Vector2i, max_steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cur := from

	for _i in range(max_steps):
		if cur == to:
			break

		var step := _step_towards(cur, to)
		if step == Vector2i.ZERO:
			break

		cur += step

		if not _in_bounds(cur):
			break

		out.append(cur)

	return out

# ------------------------------------------------------------
# SENSES -> threat blobs
# ------------------------------------------------------------
func _apply_sense_to_all_enemies(sense_type: String, level: int) -> void:
	last_combat_sense_type = sense_type

	if sense_type != "hearing":
		match sense_type:
			"smell":
				Session.add_log("Нюх помогает найти след.")
			"touch":
				Session.add_log("Осязание уточняет пространство рядом.")
			_:
				Session.add_log("Чувство ничего не сообщило о зонах врагов.")
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(enemy_positions.size()):
		if i >= enemy_candidates_by_enemy.size():
			continue
		if i >= hidden_hearing_blobs_by_enemy.size():
			continue

		var enemy_pos: Vector2i = enemy_positions[i]
		var visible_blob: Array = enemy_candidates_by_enemy[i]
		var hidden_blob: Array = hidden_hearing_blobs_by_enemy[i]

		# Первый hearing — просто показываем скрытую зону
		if visible_blob.is_empty():
			enemy_candidates_by_enemy[i] = hidden_blob.duplicate()
			continue

		# Следующий hearing — новая зона на 1 клетку меньше, но всё ещё не точная
		var next_size = max(2, visible_blob.size() - 1)
		var next_blob := _sample_uncertainty_area(enemy_pos, next_size, rng)
		next_blob = _keep_only_connected_from_center(enemy_pos, next_blob)

		# не даём схлопнуться в точную клетку слишком рано
		if next_blob.size() < 2:
			next_blob = visible_blob

		enemy_candidates_by_enemy[i] = next_blob
		hidden_hearing_blobs_by_enemy[i] = next_blob.duplicate()

	Session.add_log("Слух сужает текущие зоны врагов.")

func _local_area_around_player(r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	for y in range(max(0, player_grid_pos.y - r), min(H, player_grid_pos.y + r + 1)):
		for x in range(max(0, player_grid_pos.x - r), min(W, player_grid_pos.x + r + 1)):
			var p := Vector2i(x, y)
			if p == player_grid_pos:
				continue
			out.append(p)

	return out

func _get_blurred_dirs(real_dir: Vector2i, spread: int) -> Array:
	if spread <= 0:
		return [real_dir]

	var dirs: Array[Vector2i] = [real_dir]
	var possible: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0),                 Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1)
	]

	possible.erase(real_dir)
	possible.shuffle()

	for i in range(min(spread, possible.size())):
		dirs.append(possible[i])

	return dirs

# ------------------------------------------------------------
# CORE COMBAT LOGIC
# ------------------------------------------------------------
func _try_player_move(dir: Vector2i) -> void:
	var np := player_grid_pos + dir
	if not _in_bounds(np):
		return
	if _is_blocked(np):
		Session.add_log("Там препятствие.")
		return
	if enemy_positions.has(np):
		return

	player_grid_pos = np
	Session.add_log("Ты переместился.")

func _try_player_attack() -> void:
	var target_idx := _get_adjacent_enemy_index()
	if target_idx == -1:
		Session.add_log("Удар прошёл в пустоту.")
		return

	enemy_hps[target_idx] -= 1
	_add_blood(enemy_positions[target_idx], 1)
	Session.add_log("Ты попал по врагу!")

	if enemy_hps[target_idx] <= 0:
		enemy_positions.remove_at(target_idx)
		enemy_hps.remove_at(target_idx)
		enemy_candidates_by_enemy.remove_at(target_idx)

		Session.add_log("Один из врагов повержен.")

		if enemy_positions.is_empty():
			Session.add_log("Все враги повержены.")
			end_combat(true)
			return

		enemy_grid_pos = enemy_positions[0]

	_end_player_turn()

func _add_blood(pos: Vector2i, amount: int = 1) -> void:
	var entry = scent.get(pos, {"kind": "blood", "intensity": 0})
	entry["kind"] = "blood"
	entry["intensity"] = int(entry.get("intensity", 0)) + amount
	scent[pos] = entry

func _end_player_turn() -> void:
	phase = Phase.ENEMY_TURN
	_enemy_turn()

func _enemy_turn() -> void:
	if not active:
		return

	var hits := 0

	for i in range(enemy_positions.size()):
		var epos := enemy_positions[i]
		var dist := (player_grid_pos - epos).abs()
		var is_adjacent := (dist.x + dist.y) == 1

		if is_adjacent:
			hits += 1
			continue

		var step := _step_towards(epos, player_grid_pos)
		var np := epos + step

		# если упёрся в дерево/занято — попробуем альтернативу
		if (not _in_bounds(np)) or _is_blocked(np) or enemy_positions.has(np) or np == player_grid_pos:
			var alt := _fallback_step(epos, player_grid_pos)
			np = epos + alt

		if _in_bounds(np) and (not _is_blocked(np)) and (not enemy_positions.has(np)) and np != player_grid_pos:
			enemy_positions[i] = np

	if hits > 0:
		if player and player.has_method("take_damage"):
			player.take_damage(hits)
		else:
			Session.player_hp = max(0, int(Session.player_hp) - hits)
			Session.add_log("Враги ударили тебя: -" + str(hits) + " HP.")

		if int(Session.player_hp) <= 0:
			end_combat(false)
			return
	else:
		Session.add_log("Враги перемещаются по полю.")

	if not enemy_positions.is_empty():
		enemy_grid_pos = enemy_positions[0]

	phase = Phase.PLAYER_TURN

	emit_signal("changed")

# ------------------------------------------------------------
# TERRAIN
# ------------------------------------------------------------
func _generate_terrain(rng: RandomNumberGenerator) -> void:
	terrain.clear()
	known_terrain.clear()

	# запретим препятствия рядом со стартом игрока, чтобы не зажать сразу
	var banned := {}
	banned[player_grid_pos] = true
	for d in [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
		Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)
	]:
		var p = player_grid_pos + d
		if _in_bounds(p):
			banned[p] = true

	var trees_to_place := rng.randi_range(TERRAIN_TREES_MIN, TERRAIN_TREES_MAX)
	var rises_to_place := rng.randi_range(TERRAIN_RISE_MIN, TERRAIN_RISE_MAX)

	_place_random_terrain("tree", trees_to_place, rng, banned)
	_place_random_terrain("rise", rises_to_place, rng, banned)

func _place_random_terrain(kind: String, count: int, rng: RandomNumberGenerator, banned: Dictionary) -> void:
	var guard := 0
	while count > 0 and guard < 2000:
		guard += 1
		var p := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))

		if banned.has(p):
			continue
		if terrain.has(p):
			continue

		terrain[p] = kind
		count -= 1

func _is_blocked(p: Vector2i) -> bool:
	# деревья блокируют; возвышенность пока НЕ блокирует (для будущих механик)
	return terrain.get(p, "") == "tree"

# ------------------------------------------------------------
# SPAWN / UNCERTAINTY
# ------------------------------------------------------------
func _reset_all_enemy_candidates_with_rng(rng: RandomNumberGenerator) -> void:
	enemy_candidates_by_enemy.clear()

	for enemy_pos in enemy_positions:
		var blob: Array[Vector2i] = _sample_uncertainty_area(enemy_pos, BASE_UNCERTAINTY_CELLS, rng)
		blob = _keep_only_connected_from_center(enemy_pos, blob)
		if not blob.has(enemy_pos):
			blob.append(enemy_pos)
		enemy_candidates_by_enemy.append(blob)

func _spawn_enemies(rng: RandomNumberGenerator, danger: int) -> void:
	enemy_positions.clear()
	enemy_hps.clear()
	enemy_candidates_by_enemy.clear()

	var enemy_count := rng.randi_range(1, MAX_ENEMIES)
	var spawn_offsets := [
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3),
	]

	spawn_offsets.shuffle()
	for offset in spawn_offsets:
		if enemy_positions.size() >= enemy_count:
			break
		var p = player_grid_pos + offset
		if not _in_bounds(p):
			continue
		if p == player_grid_pos:
			continue
		if _is_blocked(p):
			continue
		if enemy_positions.has(p):
			continue
		enemy_positions.append(p)
		enemy_hps.append(1 + danger)

	if enemy_positions.is_empty():
		var fallback := Vector2i(W / 2 + 2, H / 2)
		if _is_blocked(fallback):
			fallback = Vector2i(W / 2, H / 2 + 2)
		enemy_positions.append(fallback)
		enemy_hps.append(1 + danger)

func _sample_uncertainty_area(center: Vector2i, target_size: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	# 4-связная клякса ростом от центра
	target_size = clamp(target_size, 1, W * H)

	var blob_set := {}
	blob_set[center] = true

	var frontier: Array[Vector2i] = [center]
	var neighbors4 := [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]

	var guard := 0
	while blob_set.size() < target_size and not frontier.is_empty():
		guard += 1
		if guard > 8000:
			break

		var base: Vector2i = frontier[rng.randi_range(0, frontier.size() - 1)]

		var added := false
		neighbors4.shuffle()
		for d in neighbors4:
			var np = base + d
			if not _in_bounds(np):
				continue
			if blob_set.has(np):
				continue

			blob_set[np] = true
			frontier.append(np)
			added = true
			break

		if not added:
			frontier.erase(base)

	var out: Array[Vector2i] = []
	for k in blob_set.keys():
		out.append(k)
	return out

func _keep_only_connected_from_center(center: Vector2i, cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for p in cells:
		set[p] = true

	if not set.has(center):
		set[center] = true

	var neighbors4 := [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]

	var visited := {}
	var queue: Array[Vector2i] = [center]
	visited[center] = true

	while not queue.is_empty():
		var cur = queue.pop_front()
		for d in neighbors4:
			var np = cur + d
			if not set.has(np):
				continue
			if visited.has(np):
				continue
			visited[np] = true
			queue.append(np)

	var out: Array[Vector2i] = []
	for k in visited.keys():
		out.append(k)
	return out

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------
func _get_adjacent_enemy_index() -> int:
	for i in range(enemy_positions.size()):
		var dist := (enemy_positions[i] - player_grid_pos).abs()
		if (dist.x + dist.y) == 1:
			return i
	return -1

func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx := to.x - from.x
	var dy := to.y - from.y
	if abs(dx) > abs(dy):
		return Vector2i(sign(dx), 0)
	return Vector2i(0, sign(dy))

func _fallback_step(from: Vector2i, to: Vector2i) -> Vector2i:
	# альтернатива: попробуем другой осевой шаг
	var dx := to.x - from.x
	var dy := to.y - from.y
	var options: Array[Vector2i] = []
	if dx != 0:
		options.append(Vector2i(sign(dx), 0))
	if dy != 0:
		options.append(Vector2i(0, sign(dy)))
	options.shuffle()
	if options.is_empty():
		return Vector2i.ZERO
	return options[0]

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < W and p.y >= 0 and p.y < H


func to_dict() -> Dictionary:
	var terrain_list: Array = []
	for pos in terrain.keys():
		if typeof(pos) != TYPE_VECTOR2I:
			continue
		terrain_list.append({"pos": [pos.x, pos.y], "kind": str(terrain[pos])})

	var known_terrain_list: Array = []
	for pos in known_terrain.keys():
		if typeof(pos) != TYPE_VECTOR2I:
			continue
		known_terrain_list.append([pos.x, pos.y])

	var scent_list: Array = []
	for pos in scent.keys():
		if typeof(pos) != TYPE_VECTOR2I:
			continue
		scent_list.append({"pos": [pos.x, pos.y], "entry": scent[pos]})

	var known_scent_list: Array = []
	for pos in known_scent.keys():
		if typeof(pos) != TYPE_VECTOR2I:
			continue
		known_scent_list.append([pos.x, pos.y])

	var visible_blobs: Array = []
	for blob in enemy_candidates_by_enemy:
		visible_blobs.append(_serialize_vec2i_array(blob))

	var hidden_blobs: Array = []
	for blob in hidden_hearing_blobs_by_enemy:
		hidden_blobs.append(_serialize_vec2i_array(blob))

	var encounter_data: Dictionary = _current_encounter.duplicate(true)
	var encounter_source = encounter_data.get("source_cell", Vector2i.ZERO)
	if typeof(encounter_source) == TYPE_VECTOR2I:
		var v: Vector2i = encounter_source
		encounter_data["source_cell"] = [v.x, v.y]
	elif encounter_source is Array and encounter_source.size() >= 2:
		encounter_data["source_cell"] = [int(encounter_source[0]), int(encounter_source[1])]
	else:
		encounter_data["source_cell"] = [0, 0]

	return {
		"active": active,
		"phase": int(phase),
		"player_grid_pos": [player_grid_pos.x, player_grid_pos.y],
		"enemy_positions": _serialize_vec2i_array(enemy_positions),
		"enemy_hps": enemy_hps.duplicate(),
		"enemy_grid_pos": [enemy_grid_pos.x, enemy_grid_pos.y],
		"enemy_hp": enemy_hp,
		"current_encounter": encounter_data,
		"hp_at_start": _hp_at_start,
		"total_enemies_spawned": _total_enemies_spawned,
		"last_combat_sense_type": last_combat_sense_type,
		"debug_show_real_enemies": debug_show_real_enemies,
		"terrain": terrain_list,
		"known_terrain": known_terrain_list,
		"scent": scent_list,
		"known_scent": known_scent_list,
		"enemy_candidates_by_enemy": visible_blobs,
		"hidden_hearing_blobs_by_enemy": hidden_blobs
	}

func restore_from_dict(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	phase = int(data.get("phase", int(Phase.PLAYER_TURN)))

	var player_arr = data.get("player_grid_pos", [W / 2, H / 2])
	player_grid_pos = Vector2i(int(player_arr[0]), int(player_arr[1]))

	enemy_positions = _deserialize_vec2i_array(data.get("enemy_positions", []))
	enemy_hps.clear()
	for hp in data.get("enemy_hps", []):
		enemy_hps.append(int(hp))

	var enemy_arr = data.get("enemy_grid_pos", [W / 2 + 2, H / 2])
	enemy_grid_pos = Vector2i(int(enemy_arr[0]), int(enemy_arr[1]))
	enemy_hp = int(data.get("enemy_hp", 0))
	_current_encounter = data.get("current_encounter", {})
	var source_cell_value = _current_encounter.get("source_cell", Vector2i.ZERO)
	if typeof(source_cell_value) == TYPE_VECTOR2I:
		pass
	elif source_cell_value is Array and source_cell_value.size() >= 2:
		_current_encounter["source_cell"] = Vector2i(int(source_cell_value[0]), int(source_cell_value[1]))
	else:
		_current_encounter["source_cell"] = Vector2i.ZERO
	_hp_at_start = int(data.get("hp_at_start", int(Session.player_hp)))
	_total_enemies_spawned = int(data.get("total_enemies_spawned", enemy_positions.size()))
	last_combat_sense_type = str(data.get("last_combat_sense_type", ""))
	debug_show_real_enemies = bool(data.get("debug_show_real_enemies", false))

	terrain.clear()
	for entry in data.get("terrain", []):
		var pos_arr = entry.get("pos", [0, 0])
		terrain[Vector2i(int(pos_arr[0]), int(pos_arr[1]))] = str(entry.get("kind", ""))

	known_terrain.clear()
	for pos_arr in data.get("known_terrain", []):
		known_terrain[Vector2i(int(pos_arr[0]), int(pos_arr[1]))] = true

	scent.clear()
	for entry in data.get("scent", []):
		var pos_arr = entry.get("pos", [0, 0])
		scent[Vector2i(int(pos_arr[0]), int(pos_arr[1]))] = entry.get("entry", {})

	known_scent.clear()
	for pos_arr in data.get("known_scent", []):
		known_scent[Vector2i(int(pos_arr[0]), int(pos_arr[1]))] = true

	enemy_candidates_by_enemy.clear()
	for blob in data.get("enemy_candidates_by_enemy", []):
		enemy_candidates_by_enemy.append(_deserialize_vec2i_array(blob))

	hidden_hearing_blobs_by_enemy.clear()
	for blob in data.get("hidden_hearing_blobs_by_enemy", []):
		hidden_hearing_blobs_by_enemy.append(_deserialize_vec2i_array(blob))

	emit_signal("changed")

func _serialize_vec2i_array(source: Array) -> Array:
	var out: Array = []
	for value in source:
		if typeof(value) == TYPE_VECTOR2I:
			out.append([value.x, value.y])
	return out

func _deserialize_vec2i_array(source: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if source is Array:
		for value in source:
			if value is Array and value.size() >= 2:
				out.append(Vector2i(int(value[0]), int(value[1])))
	return out
