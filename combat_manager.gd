extends Node
class_name CombatManager

signal changed
signal combat_finished(result: Dictionary)

const W := 8
const H := 8
const CELL_SIZE := 64

enum Phase { PLAYER_TURN, ENEMY_TURN, RESOLVE, END }
var phase: Phase = Phase.PLAYER_TURN

var player_grid_pos := Vector2i(3, 3)
var enemy_grid_pos := Vector2i(5, 3)

var enemy_hp := 3
var active := false

# EncounterData текущего боя + hp на старте (для CombatResult)
var _current_encounter: Dictionary = {}
var _hp_at_start: int = 0

@onready var combat_layer := get_parent() # CombatLayer (Node2D)

# ------------------------------------------------------------
# Fog-of-war по врагу
# ------------------------------------------------------------
var enemy_candidates: Array[Vector2i] = []   # клетки, где враг МОЖЕТ быть
var enemy_revealed: bool = false             # если захочешь позже: показывать точную позицию
var last_combat_sense_type: String = ""      # для UI/отладки

func handle_player_input(event: InputEvent) -> void:
	if not active:
		return
	if phase != Phase.PLAYER_TURN:
		return

	var dir := _dir_from_input(event)
	if dir != Vector2i.ZERO:
		_try_player_move(dir)
		return
		
	if event.is_action_pressed("sense_hearing"):
		_use_combat_sense("hearing")
		return

	if event.is_action_pressed("sense_smell"):
		_use_combat_sense("smell")
		return

	if event.is_action_pressed("sense_touch"):
		_use_combat_sense("touch")
		return

	if event.is_action_pressed("attack"):
		_try_player_attack()
		return

# ------------------------------------------------------------
# START COMBAT (пункт 4: принимает EncounterData)
# ------------------------------------------------------------
func start_combat(encounter: Dictionary = {}) -> void:
	_current_encounter = encounter
	_hp_at_start = int(Session.player_hp)

	active = true
	phase = Phase.PLAYER_TURN
	enemy_revealed = false
	last_combat_sense_type = ""

	var danger: int = int(encounter.get("danger", 1))
	var enemy_pack: String = str(encounter.get("enemy_pack", "large_enemy"))
	var base_seed: int = int(encounter.get("seed", 0))

	# (опционально) детерминированный RNG
	var rng := RandomNumberGenerator.new()
	if base_seed != 0:
		rng.seed = base_seed + int(hash(encounter.get("encounter_id", "")))
	else:
		rng.randomize()

	# Стартовые позиции
	player_grid_pos = Vector2i(W / 2, H / 2)

	var spawn_offsets := [
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	var offset = spawn_offsets[rng.randi_range(0, spawn_offsets.size() - 1)]
	enemy_grid_pos = player_grid_pos + offset
	if not _in_bounds(enemy_grid_pos) or enemy_grid_pos == player_grid_pos:
		enemy_grid_pos = Vector2i(W/2 + 2, H/2)

	# Настройка врага (MVP)
	match enemy_pack:
		"large_enemy":
			enemy_hp = 2 + danger
		"dogs":
			enemy_hp = 1 + danger
		_:
			enemy_hp = 2 + danger

	# Инициализируем “неопределённость”
	_reset_enemy_candidates()

	Session.add_log("Начался бой.")
	emit_signal("changed")

# ------------------------------------------------------------
# END COMBAT (пункт 4: возвращает CombatResult)
# ------------------------------------------------------------
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
# Сенсы в бою (MVP)
# ------------------------------------------------------------
func _apply_initial_combat_senses() -> void:
	var hearing_level := int(Session.skills.get("hearing", 1))
	var smell_level := int(Session.skills.get("smell", 1))
	# touch пока берём из "touch" (если появится) иначе fallback на "echo"
	var touch_level := int(Session.skills.get("touch", Session.skills.get("echo", 1)))

	Session.add_log("В бою ты пытаешься понять, где враг…")

	_apply_sense("hearing", hearing_level)
	_apply_sense("smell", smell_level)
	_apply_sense("touch", touch_level)

func _reset_enemy_candidates() -> void:
	enemy_candidates.clear()
	for y in range(H):
		for x in range(W):
			var p := Vector2i(x, y)
			if p == player_grid_pos:
				continue
			enemy_candidates.append(p)

func _apply_sense(sense_type: String, level: int) -> void:
	last_combat_sense_type = sense_type

	var sense_candidates := _get_candidates_for_sense(sense_type, level)

	# Пересечение: оставляем только те клетки, которые согласуются с сенсом
	var filtered: Array[Vector2i] = []
	for p in enemy_candidates:
		if sense_candidates.has(p):
			filtered.append(p)

	enemy_candidates = filtered

	# гарантируем что настоящая позиция не исчезла из кандидатов (на случай краевых условий)
	if not enemy_candidates.has(enemy_grid_pos):
		enemy_candidates.append(enemy_grid_pos)

	match sense_type:
		"hearing":
			Session.add_log("Слух подсказывает направление врага. (точность " + str(level) + ")")
		"smell":
			Session.add_log("Запах даёт примерное направление. (точность " + str(level) + ")")
		"touch":
			Session.add_log("Осязание/вибрации дают понимание дистанции. (точность " + str(level) + ")")
		_:
			Session.add_log("Чувство уточняет позицию врага.")

func _get_candidates_for_sense(sense_type: String, level: int) -> Array[Vector2i]:
	# Реальная “квантизованная” direction от игрока до врага (одна из 8)
	var delta := enemy_grid_pos - player_grid_pos
	var real_dir := Vector2i(sign(delta.x), sign(delta.y))
	if real_dir == Vector2i.ZERO:
		real_dir = Vector2i(1, 0) # теоретически не должно случиться

	# level -> blur (как у тебя в overworld)
	var spread := 3
	match level:
		1: spread = 3
		2: spread = 2
		3: spread = 0
		_: spread = 0

	var dirs := _get_blurred_dirs(real_dir, spread)

	match sense_type:
		"hearing":
			# слух: “конус” по направлениям, дальность больше
			return _cone_from_dirs(player_grid_pos, dirs, 5)
		"smell":
			# нюх: конус по направлениям, дальность меньше
			return _cone_from_dirs(player_grid_pos, dirs, 4)
		"touch":
			# осязание: не направление, а “примерная дистанция”
			# MVP: по уровню уточняем, близко ли враг
			return _touch_band_candidates(player_grid_pos, enemy_grid_pos, level)
		_:
			return _cone_from_dirs(player_grid_pos, dirs, 4)

func _cone_from_dirs(origin: Vector2i, dirs: Array, max_range: int) -> Array[Vector2i]:
	# “Конус”: все клетки в указанных направлениях в пределах max_range
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

func _touch_band_candidates(origin: Vector2i, enemy_pos: Vector2i, level: int) -> Array[Vector2i]:
	# Осязание = “вибрации/шаги по полу” -> лучше даёт дистанцию, чем направление.
	# MVP-идея:
	# level 1: только "далеко/не очень" -> Chebyshev <= 3 или > 3
	# level 2: Chebyshev <= 2 или > 2
	# level 3+: почти точно: Chebyshev == реальная дистанция (в пределах 1-3), иначе >=4
	var dist = max(abs(enemy_pos.x - origin.x), abs(enemy_pos.y - origin.y)) # Chebyshev

	var candidates: Array[Vector2i] = []

	var band_min := 1
	var band_max := 3

	if level <= 1:
		# грубо: "в пределах 3" vs "дальше 3"
		if dist <= 3:
			band_min = 1
			band_max = 3
		else:
			band_min = 4
			band_max = 99
	elif level == 2:
		if dist <= 2:
			band_min = 1
			band_max = 2
		else:
			band_min = 3
			band_max = 99
	else:
		# почти точно (в разумных пределах)
		if dist <= 3:
			band_min = dist
			band_max = dist
		else:
			band_min = 4
			band_max = 99

	for y in range(H):
		for x in range(W):
			var p := Vector2i(x, y)
			if p == origin:
				continue
			var d = max(abs(p.x - origin.x), abs(p.y - origin.y))
			if d >= band_min and d <= band_max:
				candidates.append(p)

	return candidates

func _get_blurred_dirs(real_dir: Vector2i, spread: int) -> Array:
	if spread <= 0:
		return [real_dir]

	var dirs := [real_dir]
	var possible := [
		Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
		Vector2i(-1, 0),               Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	].duplicate()

	possible.erase(real_dir)
	possible.shuffle()

	for i in range(min(spread, possible.size())):
		dirs.append(possible[i])

	return dirs

# ------------------------------------------------------------
# Бой
# ------------------------------------------------------------
func _dir_from_input(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_up"): return Vector2i(0, -1)
	if event.is_action_pressed("ui_down"): return Vector2i(0, 1)
	if event.is_action_pressed("ui_left"): return Vector2i(-1, 0)
	if event.is_action_pressed("ui_right"): return Vector2i(1, 0)
	return Vector2i.ZERO

func _try_player_move(dir: Vector2i) -> void:
	var np = player_grid_pos + dir
	if not _in_bounds(np):
		return
	# запрет встать на врага (даже если игрок его “не видит”)
	if np == enemy_grid_pos:
		return

	player_grid_pos = np
	Session.add_log("Ты переместился.")
	_end_player_turn()
	emit_signal("changed")

func _try_player_attack() -> void:
	# атака если враг рядом (MVP 4-соседство)
	var dist = (enemy_grid_pos - player_grid_pos).abs()
	var is_adjacent = (dist.x + dist.y) == 1
	if not is_adjacent:
		Session.add_log("Удар прошёл в пустоту.")
		return

	enemy_hp -= 1
	Session.add_log("Ты попал по врагу!")

	if enemy_hp <= 0:
		Session.add_log("Враг повержен.")
		end_combat(true)
		return

	_end_player_turn()
	emit_signal("changed")

func _end_player_turn() -> void:
	phase = Phase.ENEMY_TURN
	_enemy_turn()

func _enemy_turn() -> void:
	if not active:
		return

	var dist = (player_grid_pos - enemy_grid_pos).abs()
	var is_adjacent = (dist.x + dist.y) == 1
	if is_adjacent:
		Session.player_hp -= 1
		Session.add_log("Враг ударил тебя: -1 HP.")
		if Session.player_hp <= 0:
			end_combat(false)
			return
	else:
		var step = _step_towards(enemy_grid_pos, player_grid_pos)
		var np = enemy_grid_pos + step
		if np != player_grid_pos and _in_bounds(np):
			enemy_grid_pos = np
			Session.add_log("Враг приблизился.")

	# Важно: враг двинулся -> обновляем “кандидатов” грубо:
	# MVP: просто оставим как есть. (Позже можно расширить: “движение расширяет неопределённость”.)

	phase = Phase.PLAYER_TURN
	_expand_uncertainty()
	emit_signal("changed")

func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx = to.x - from.x
	var dy = to.y - from.y
	if abs(dx) > abs(dy):
		return Vector2i(sign(dx), 0)
	else:
		return Vector2i(0, sign(dy))

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < W and p.y >= 0 and p.y < H
	
func _use_combat_sense(sense_type: String) -> void:
	if not active or phase != Phase.PLAYER_TURN:
		return

	var level := int(Session.skills.get(sense_type, 1))

	Session.add_log("Ты используешь " + sense_type + ".")

	_apply_sense(sense_type, level)

	# Сенс тратит ход
	_end_player_turn()

	emit_signal("changed")
	
func _expand_uncertainty() -> void:
	var expanded: Array[Vector2i] = []

	for p in enemy_candidates:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var np = Vector2i(p.x + dx, p.y + dy)
				if _in_bounds(np) and not expanded.has(np):
					expanded.append(np)

	enemy_candidates = expanded
