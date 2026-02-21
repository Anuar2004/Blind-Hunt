extends Node
class_name OverworldManager

const GRID_WIDTH := 10 #Размеры карты, возможно потом будут ненужными, я хочу сделать бесконечный открытый мир
const GRID_HEIGHT := 10 #Размеры карты, возможно потом будут ненужными, я хочу сделать бесконечный открытый мир
const CELL_SIZE := 64

var grid := [] #Массив, в котором будет храниться grid-карта, где каждая клетка - это 
var player_pos := Vector2i(5, 5) #Точка позиция для персонажа, в будущем нужно будет сделать чисто ее центром карты

@onready var overworld_layer := get_parent()
@onready var gsm := get_tree().get_first_node_in_group("gsm")

func _ready():
	generate_grid()

func generate_grid():
	grid.clear() #чистит поле от старых клеток, пока хз зачем. Наверное просто хорошая практика
	for y in GRID_HEIGHT: #двойной loop по x и y координатам для создания клеток, в конце ряд добавляется на карту... 
		#Тут надо пересмотреть метод построения карты, потому что я хочу сделать карту открытой и процедурногенерируемой
		var row = []
		for x in GRID_WIDTH:
			row.append({
				"type": "ENEMY" if randi() % 5 == 0 else "EMPTY",
				"discovered": false,
				"resolved": false
			})
		grid.append(row)

func try_move(dir: Vector2i): #функция перемещени по карте,
	var new_pos = player_pos + dir #в зависимости от стороны передвижения, перс получается новую позицию
	if new_pos.x < 0 or new_pos.x >= GRID_WIDTH: return #не дает выйти за карту
	if new_pos.y < 0 or new_pos.y >= GRID_HEIGHT: return

	player_pos = new_pos
	resolve_cell() #в зависимости от контента клетки, решает ее
	update_player_visual()

func resolve_cell():
	var cell = grid[player_pos.y][player_pos.x]
	if cell["type"] == "ENEMY" and not cell["resolved"]:
		gsm.change_state("CombatState", {
			"world_cell": player_pos,
			"danger": 1
		})

func update_player_visual(): #пока нету, ПОНАДОБИТСЯ в будущем при создании ноды игрока
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.position = overworld_layer.position + Vector2(
			player_pos.x * CELL_SIZE + CELL_SIZE / 2.0,
			player_pos.y * CELL_SIZE + CELL_SIZE / 2.0
		)

#const DIRECTIONS = [
	#Vector2i(-1,-1),
	#Vector2i(0,-1),
	#Vector2i(1,-1),
	#Vector2i(-1,0),
	#Vector2i(1,0),
	#Vector2i(-1,1),
	#Vector2i(0,1),
	#Vector2i(1,1),
#]
#
#var cells = []
#
#func generate_cells():
	#cells.clear()
#
	#var senses = ["hearing", "smell", "echo"]
	#var sense_pool = []
#
	## гарантируем минимум 1 каждого
	#for s in senses:
		#sense_pool.append(s)
#
	#while sense_pool.size() < 8:
		#sense_pool.append(senses.pick_random())
#
	#sense_pool.shuffle()
#
	#for i in range(8):
		#var cell = {
			#"direction": DIRECTIONS[i],
			#"sense_type": sense_pool[i],
			#"content_type": _random_content_for(sense_pool[i]),
			#"intensity": randi_range(1,5)
		#}
#
		#cells.append(cell)
#
#func _random_content_for(sense_type: String) -> String:
	#match sense_type:
		#"hearing":
			#return ["dogs", "help", "steps"].pick_random()
		#"smell":
			#return ["blood", "fire", "food"].pick_random()
		#"echo":
			#return ["wall", "pit", "large_enemy"].pick_random()
		#_:
			#return "unknown"
#
#func use_sense(sense_type: String, level: int):
#
	#var result = []
#
	#for cell in cells:
		#if cell.sense_type != sense_type:
			#continue
#
		#var entry = {}
		#entry.content = cell.content_type
#
		#match level:
			#1:
				#entry.directions = _get_blurred_dirs(cell.direction, 3)
			#2:
				#entry.directions = _get_blurred_dirs(cell.direction, 2)
			#3:
				#entry.directions = [cell.direction]
			#_:
				#entry.directions = [cell.direction]
#
		#result.append(entry)
#
	#return result
#
#func _get_blurred_dirs(real_dir: Vector2i, spread: int):
	#var dirs = [real_dir]
#
	#var possible = DIRECTIONS.duplicate()
	#possible.erase(real_dir)
	#possible.shuffle()
#
	#for i in range(spread):
		#dirs.append(possible[i])
#
	#return dirs
