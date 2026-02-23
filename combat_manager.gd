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

@onready var combat_layer := get_parent() # CombatLayer

func handle_player_input(event: InputEvent) -> void:
	if not active:
		return
	if phase != Phase.PLAYER_TURN:
		return

	var dir := _dir_from_input(event)
	if dir != Vector2i.ZERO:
		_try_player_move(dir)
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

	_place_player()

	Session.add_log("Начался бой.")
	print("Combat started:",
		"id=", encounter.get("encounter_id", ""),
		" pack=", enemy_pack,
		" danger=", danger,
		" playerHP=", Session.player_hp,
		" enemyHP=", enemy_hp
	)

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
	if np == enemy_grid_pos:
		return

	player_grid_pos = np
	_place_player()
	Session.add_log("Ты переместился.")
	_end_player_turn()
	emit_signal("changed")

func _try_player_attack() -> void:
	var dist = (enemy_grid_pos - player_grid_pos).abs()
	var is_adjacent = (dist.x + dist.y) == 1
	if not is_adjacent:
		Session.add_log("Враг слишком далеко.")
		print("No enemy in range")
		return

	enemy_hp -= 1
	Session.add_log("Ты ударил врага.")
	print("Hit! Enemy HP:", enemy_hp)

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
		print("Enemy hits! Player HP:", Session.player_hp)
		if Session.player_hp <= 0:
			end_combat(false)
			return
	else:
		var step = _step_towards(enemy_grid_pos, player_grid_pos)
		var np = enemy_grid_pos + step
		if np != player_grid_pos and _in_bounds(np):
			enemy_grid_pos = np
			Session.add_log("Враг приблизился.")
			print("Enemy moves to:", enemy_grid_pos)

	phase = Phase.PLAYER_TURN
	print("PLAYER TURN")
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

func _place_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.position = combat_layer.position + Vector2(
			player_grid_pos.x * CELL_SIZE + CELL_SIZE/2,
			player_grid_pos.y * CELL_SIZE + CELL_SIZE/2
		)
