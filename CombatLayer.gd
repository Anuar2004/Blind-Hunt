extends Node2D

@export var cell_size := 64
@export var w := 8
@export var h := 8
#ВСЕ ДЛЯ ЧЕГО НУЖНА ТА НОДА - ОТРИСОВКА ПЕРСОНАЖА ПО ПОЗИЦИЯМ ИЗ МЕНЕДЖЕРА
var combat_manager: Node

func _ready():
	combat_manager = get_tree().get_first_node_in_group("combat_manager")
	if combat_manager and combat_manager.changed:
		if not combat_manager.changed.is_connected(queue_redraw):
			combat_manager.changed.connect(queue_redraw)
	queue_redraw()

func _draw():
	# Сетка
	for x in range(w + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, h * cell_size), Color.WHITE, 2.0)
	for y in range(h + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(w * cell_size, y * cell_size), Color.WHITE, 2.0)

	if combat_manager == null:
		return

	# Достаём позиции из CombatManager (они должны быть публичными vars)
	var ppos: Vector2i = combat_manager.player_grid_pos
	var epos: Vector2i = combat_manager.enemy_grid_pos

	# Игрок
	var pr = Rect2(Vector2(ppos.x * cell_size, ppos.y * cell_size) + Vector2(8, 8), Vector2(cell_size - 16, cell_size - 16))
	draw_rect(pr, Color(0.2, 0.8, 1.0, 0.5), true)

	# Враг
	var er = Rect2(Vector2(epos.x * cell_size, epos.y * cell_size) + Vector2(12, 12), Vector2(cell_size - 24, cell_size - 24))
	draw_rect(er, Color(1.0, 0.2, 0.2, 0.5), true)
