extends Node
class_name CombatManager

signal changed
signal combat_finished(result: Dictionary)

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

# ------------------------------------------------------------
# Fog-of-war: отдельные кляксы по врагам
# ------------------------------------------------------------
var enemy_candidates_by_enemy: Array[Array] = [] # Array[Array[Vector2i]]
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
# PUBLIC API (вызывается из CombatState)
# ------------------------------------------------------------
func try_move(dir: Vector2i) -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return
	_try_player_move(dir)
	emit_signal("changed")

func try_attack() -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return
	_try_player_attack()
	emit_signal("changed")

func use_sense(sense_type: String) -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return
	_use_combat_sense(sense_type)
	emit_signal("changed")

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

	# 2) Спавним врагов с учётом деревьев
	_spawn_enemies(rng, danger)

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

	# 3) Инициализируем кляксы врагов
	_reset_all_enemy_candidates_with_rng(rng)

	# 4) В начале боя автоматически "ощутим" ландшафт touch-ом
	var touch_level := int(Session.skills.get("touch", Session.skills.get("echo", 1)))
	_reveal_terrain_by_touch(touch_level)

	Session.add_log("Начался бой.")
	emit_signal("changed")

func end_combat(victory: bool) -> void:
	active = false
	phase = Phase.END

	if victory:
		Session.add_log("Ты победил в бою.")
	else:
		Session.add_log("Ты проиграл бой.")

	var result := {
		"encounter_id": str(_current_encounter.get("encounter_id", "")),
		"source_cell": _current_encounter.get("source_cell", Vector2i.ZERO),
		"victory": victory,
		"player_hp_delta": int(Session.player_hp) - _hp_at_start,
		"world_effects": [],
		"loot": []
	}

	emit_signal("combat_finished", result)

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
			# Touch сейчас = ландшафт (синий слой)
			_reveal_terrain_by_touch(level)
		"hearing", "smell":
			# пока оставим их на угрозу (кляксы)
			_apply_sense_to_all_enemies(sense_type, level)
		_:
			_apply_sense_to_all_enemies(sense_type, level)

	_end_player_turn()

func _reveal_terrain_by_touch(level: int) -> void:
	last_combat_sense_type = "touch"

	# радиус по уровню
	var r := 2
	match level:
		1: r = 2
		2: r = 3
		3: r = 4
		_: r = 4

	for y in range(max(0, player_grid_pos.y - r), min(H, player_grid_pos.y + r + 1)):
		for x in range(max(0, player_grid_pos.x - r), min(W, player_grid_pos.x + r + 1)):
			var p := Vector2i(x, y)
			if terrain.has(p):
				known_terrain[p] = true

	Session.add_log("Ты ощущаешь пространство вокруг. (радиус " + str(r) + ")")

# ------------------------------------------------------------
# SENSES -> threat blobs
# ------------------------------------------------------------
func _apply_sense_to_all_enemies(sense_type: String, level: int) -> void:
	last_combat_sense_type = sense_type

	for i in range(enemy_positions.size()):
		if i >= enemy_candidates_by_enemy.size():
			continue

		var sense_candidates_for_enemy: Array[Vector2i] = _get_candidates_for_sense_from_enemy(
			sense_type, level, enemy_positions[i]
		)

		var old_blob: Array = enemy_candidates_by_enemy[i]
		var filtered: Array[Vector2i] = []
		for p in old_blob:
			if sense_candidates_for_enemy.has(p):
				filtered.append(p)

		filtered = _keep_only_connected_from_center(enemy_positions[i], filtered)
		if not filtered.has(enemy_positions[i]):
			filtered.append(enemy_positions[i])

		enemy_candidates_by_enemy[i] = filtered

	match sense_type:
		"hearing":
			Session.add_log("Слух уточняет направление. (точность " + str(level) + ")")
		"smell":
			Session.add_log("Нюх уточняет положение. (точность " + str(level) + ")")
		_:
			Session.add_log("Чувство уточняет позицию. (точность " + str(level) + ")")

func _get_candidates_for_sense_from_enemy(sense_type: String, level: int, enemy_pos: Vector2i) -> Array[Vector2i]:
	var delta := enemy_pos - player_grid_pos
	var real_dir := Vector2i(sign(delta.x), sign(delta.y))
	if real_dir == Vector2i.ZERO:
		real_dir = Vector2i(1, 0)

	var spread := 3
	match level:
		1: spread = 3
		2: spread = 2
		3: spread = 0
		_: spread = 0

	var dirs := _get_blurred_dirs(real_dir, spread)

	match sense_type:
		"hearing":
			return _cone_from_dirs(player_grid_pos, dirs, 5)
		"smell":
			return _cone_from_dirs(player_grid_pos, dirs, 4)
		_:
			return _cone_from_dirs(player_grid_pos, dirs, 4)

func _cone_from_dirs(origin: Vector2i, dirs: Array, max_range: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in dirs:
		for y in range(H):
			for x in range(W):
				var p := Vector2i(x, y)
				if p == origin:
					continue
				if origin.distance_to(p) > float(max_range):
					continue

				var dd := p - origin
				var sd := Vector2i(sign(dd.x), sign(dd.y))
				if sd == d:
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

func _end_player_turn() -> void:
	phase = Phase.ENEMY_TURN
	_enemy_turn()

func _enemy_turn() -> void:
	if not active:
		return

	var hits := 0
	var any_moved := false

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
			any_moved = true

	if hits > 0:
		Session.player_hp -= hits
		Session.add_log("Враги ударили тебя: -" + str(hits) + " HP.")
		if Session.player_hp <= 0:
			end_combat(false)
			return
	else:
		Session.add_log("Враги перемещаются по полю.")

	if not enemy_positions.is_empty():
		enemy_grid_pos = enemy_positions[0]

	phase = Phase.PLAYER_TURN

	if any_moved:
		_expand_uncertainty()

	emit_signal("changed")

func _expand_uncertainty() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_reset_all_enemy_candidates_with_rng(rng)

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
