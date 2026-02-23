extends Node2D

const CELL_SIZE := 64
var overworld_manager: OverworldManager

func _ready():
	overworld_manager = get_tree().get_first_node_in_group("overworld_manager")
	if overworld_manager:
		if not overworld_manager.world_changed.is_connected(queue_redraw):
			overworld_manager.world_changed.connect(queue_redraw)

	if not Session.log_changed.is_connected(queue_redraw):
		Session.log_changed.connect(queue_redraw)

	queue_redraw()

# ------------------------------------------------------------
# DRAW
# ------------------------------------------------------------

func _draw():
	if overworld_manager == null:
		return

	var world: Dictionary = Session.world
	var player_pos: Vector2i = Session.player_pos

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
	_draw_log_overlay()

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
	var obs_list: Array = Session.observations

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

func _draw_log_overlay() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return

	var lines_to_show := 8
	var start = max(0, Session.log.size() - lines_to_show)

	var x := 20.0
	var y := 24.0
	var line_h := 18.0

	# фон-панель
	var h := lines_to_show * line_h + 12.0
	draw_rect(Rect2(Vector2(x - 10.0, y - 18.0), Vector2(520.0, h)), Color(0, 0, 0, 0.5), true)

	for i in range(start, Session.log.size()):
		draw_string(font, Vector2(x, y), Session.log[i])
		y += line_h
