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
var player_hp := 3

var active := false

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

func start_combat(data := {}):
	active = true
	phase = Phase.PLAYER_TURN
	# Можно использовать data для сложности/seed и т.п.
	player_grid_pos = Vector2i(W/2, H/2)
	enemy_grid_pos = Vector2i(W/2 + 2, H/2)

	_place_player()
	# (позже) создадим Enemy-node; пока просто логика позиции
	print("Combat started. PLAYER TURN")

func end_combat(victory: bool):
	active = false
	emit_signal("combat_finished", {"victory": victory})

func _dir_from_input(event: InputEvent) -> Vector2i:
	# Важно: диагонали лучше вынести в отдельные действия позже.
	# MVP: стрелки/wasd + q/e/z/c как диагонали (по желанию).
	if event.is_action_pressed("ui_up"): return Vector2i(0, -1)
	if event.is_action_pressed("ui_down"): return Vector2i(0, 1)
	if event.is_action_pressed("ui_left"): return Vector2i(-1, 0)
	if event.is_action_pressed("ui_right"): return Vector2i(1, 0)
	return Vector2i.ZERO

func _try_player_move(dir: Vector2i):
	var np = player_grid_pos + dir
	if not _in_bounds(np):
		return
	# запрет встать на врага
	if np == enemy_grid_pos:
		return

	player_grid_pos = np
	_place_player()
	_end_player_turn()
	emit_signal("changed")

func _try_player_attack():
	# атака если враг рядом (8 направлений можно, но пока 4)
	var dist = (enemy_grid_pos - player_grid_pos).abs()
	var is_adjacent = (dist.x + dist.y) == 1  # 4-соседство
	if not is_adjacent:
		print("No enemy in range")
		return

	enemy_hp -= 1
	print("Hit! Enemy HP:", enemy_hp)
	if enemy_hp <= 0:
		end_combat(true)
		return

	_end_player_turn()
	emit_signal("changed")

func _end_player_turn():
	phase = Phase.ENEMY_TURN
	_enemy_turn()

func _enemy_turn():
	# Простейший AI: если рядом — бьёт, иначе шаг к игроку
	if not active:
		return

	var dist = (player_grid_pos - enemy_grid_pos).abs()
	var is_adjacent = (dist.x + dist.y) == 1
	if is_adjacent:
		player_hp -= 1
		print("Enemy hits! Player HP:", player_hp)
		if player_hp <= 0:
			end_combat(false)
			return
	else:
		var step = _step_towards(enemy_grid_pos, player_grid_pos)
		var np = enemy_grid_pos + step
		# запрет на игрока
		if np != player_grid_pos and _in_bounds(np):
			enemy_grid_pos = np
			print("Enemy moves to:", enemy_grid_pos)

	# конец хода врага
	phase = Phase.PLAYER_TURN
	print("PLAYER TURN")
	emit_signal("changed")

func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx = to.x - from.x
	var dy = to.y - from.y
	# приоритет по большей разнице
	if abs(dx) > abs(dy):
		return Vector2i(sign(dx), 0)
	else:
		return Vector2i(0, sign(dy))

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < W and p.y >= 0 and p.y < H

func _place_player():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		# ставим игрока относительно CombatLayer
		player.position = combat_layer.position + Vector2(
			player_grid_pos.x * CELL_SIZE + CELL_SIZE/2,
			player_grid_pos.y * CELL_SIZE + CELL_SIZE/2
		)
