extends Node2D

const GRID_WIDTH := 10 #Размеры карты, возможно потом будут ненужными, я хочу сделать бесконечный открытый мир
const GRID_HEIGHT := 10 #Размеры карты, возможно потом будут ненужными, я хочу сделать бесконечный открытый мир
const CELL_SIZE := 64

var overworld_manager: Node

func _ready(): #генерируется все клетки карты
	overworld_manager = get_tree().get_first_node_in_group("overworld_manager")
	
func _process(_delta):
	queue_redraw() #встроенная функция которая отрисосывает layout при помощи функции _draw

func _draw():
	# Линии сетки
	for x in range(GRID_WIDTH + 1):
		draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, GRID_HEIGHT * CELL_SIZE), Color.WHITE, 2.0)
	for y in range(GRID_HEIGHT + 1):
		draw_line(Vector2(0, y * CELL_SIZE), Vector2(GRID_WIDTH * CELL_SIZE, y * CELL_SIZE), Color.WHITE, 2.0)

	# Маркер клетки игрока (квадрат в центре клетки)
	var ppos = overworld_manager.player_pos
	var grid_map = overworld_manager.grid
	
	var rect_pos = Vector2(ppos.x * CELL_SIZE, ppos.y * CELL_SIZE)
	draw_rect(Rect2(rect_pos + Vector2(8, 8), Vector2(CELL_SIZE - 16, CELL_SIZE - 16)), Color(0.2, 0.8, 1.0, 0.35), true)

	# (Опционально) подсветим ENEMY клетки, чтобы видеть где они
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			if grid_map[y][x]["type"] == "ENEMY":
				var p = Vector2(x * CELL_SIZE, y * CELL_SIZE)
				draw_rect(Rect2(p + Vector2(18, 18), Vector2(CELL_SIZE - 36, CELL_SIZE - 36)), Color(1.0, 0.2, 0.2, 0.25), true)
