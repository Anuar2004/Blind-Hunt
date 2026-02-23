extends Node2D

const CELL_SIZE := 64
var overworld_manager: OverworldManager

func _ready():
	overworld_manager = get_tree().get_first_node_in_group("overworld_manager")
	queue_redraw()

# ------------------------------------------------------------
# DRAW
# ------------------------------------------------------------

func _draw():
	if overworld_manager == null:
		return

	var world: Dictionary = overworld_manager.world
	var player_pos: Vector2i = overworld_manager.player_pos

	# --- Рисуем все сгенерированные клетки ---
	for pos in world.keys():
		var screen_pos := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)

		draw_rect(
			Rect2(screen_pos, Vector2(CELL_SIZE, CELL_SIZE)),
			Color.WHITE,
			false,
			1.5
		)

	# --- Игрок ---
	var player_screen := Vector2(player_pos.x * CELL_SIZE, player_pos.y * CELL_SIZE)
	draw_rect(
		Rect2(player_screen + Vector2(8,8), Vector2(CELL_SIZE - 16, CELL_SIZE - 16)),
		Color(0.2, 0.8, 1.0, 0.6),
		true
	)

	# --- Память игрока (размытые наблюдения) ---
	_draw_observations()

	# --- Мгновенная подсветка текущего сенсора ---
	_draw_current_sense(player_pos, overworld_manager.last_sense_type, overworld_manager.last_sense_result)

# ------------------------------------------------------------
# ОТРИСОВКА ТЕКУЩЕГО СЕНСОРА
# ------------------------------------------------------------

func _draw_current_sense(player_pos: Vector2i, sense_type: String, sense_result: Array):
	if sense_result.is_empty():
		return

	var color := Color(0.2, 1.0, 0.2, 0.25)

	match sense_type:
		"hearing":
			color = Color(0.2, 0.6, 1.0, 0.35)
		"smell":
			color = Color(0.6, 1.0, 0.2, 0.35)
		"echo":
			color = Color(1.0, 0.8, 0.2, 0.35)

	for entry in sense_result:
		if not entry.has("dirs"):
			continue

		for dir in entry["dirs"]:
			if typeof(dir) != TYPE_VECTOR2I:
				continue

			var wp: Vector2i = player_pos + dir
			var sp := Vector2(wp.x * CELL_SIZE, wp.y * CELL_SIZE)

			draw_rect(
				Rect2(sp, Vector2(CELL_SIZE, CELL_SIZE)),
				color,
				true
			)

# ------------------------------------------------------------
# ОТРИСОВКА ПАМЯТИ (наблюдений)
# ------------------------------------------------------------

func _draw_observations():
	var obs_list: Array = overworld_manager.observations

	for obs in obs_list:
		var origin: Vector2i = obs["origin"]
		var sense_type: String = obs["sense_type"]
		var dirs: Array = obs["dirs"]
		var content: String = str(obs["content"])

		var color := Color(0.2, 1.0, 0.2, 0.15)

		match sense_type:
			"hearing":
				color = Color(0.2, 0.6, 1.0, 0.18)
			"smell":
				color = Color(0.6, 1.0, 0.2, 0.18)
			"echo":
				color = Color(1.0, 0.8, 0.2, 0.18)

		for dir in dirs:
			if typeof(dir) != TYPE_VECTOR2I:
				continue

			var wp: Vector2i = origin + dir
			var sp := Vector2(wp.x * CELL_SIZE, wp.y * CELL_SIZE)

			draw_rect(
				Rect2(sp, Vector2(CELL_SIZE, CELL_SIZE)),
				color,
				true
			)

			# Временно текст (для отладки)
			var font := ThemeDB.fallback_font
			draw_string(
				font,
				sp + Vector2(6, CELL_SIZE * 0.6),
				content,
				HORIZONTAL_ALIGNMENT_LEFT,
				CELL_SIZE - 12,
				14,
				Color(1,1,1,0.9)
			)
