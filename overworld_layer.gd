extends Node2D

const CELL_SIZE := 64
var overworld_manager: OverworldManager

func _ready():
	overworld_manager = get_tree().get_first_node_in_group("overworld_manager")
	if overworld_manager:
		if not overworld_manager.world_changed.is_connected(queue_redraw):
			overworld_manager.world_changed.connect(queue_redraw)

	if not Session.session_loaded.is_connected(queue_redraw):
		Session.session_loaded.connect(queue_redraw)

	queue_redraw()

# ------------------------------------------------------------
# DRAW
# ------------------------------------------------------------

func _draw():
	if overworld_manager == null:
		return

	var world: Dictionary = Session.world

	for pos in world.keys():
		var screen_pos := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		draw_rect(Rect2(screen_pos, Vector2(CELL_SIZE, CELL_SIZE)), Color.WHITE, false, 1.5)

	_draw_observations(false)
	_draw_entries(overworld_manager.last_sense_result, true)

func _draw_observations(current_only: bool) -> void:
	if current_only:
		return
	_draw_entries(Session.observations, false)

func _draw_entries(entries: Array, is_current: bool) -> void:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var sense_type := str(entry.get("sense_type", ""))
		match str(entry.get("kind", "")):
			"marker":
				_draw_marker_entry(entry, sense_type, is_current)
			"trail":
				_draw_trail_entry(entry, sense_type, is_current)
			"echo":
				_draw_echo_entry(entry, is_current)

func _draw_marker_entry(entry: Dictionary, sense_type: String, is_current: bool) -> void:
	var pos: Vector2i = entry.get("source_pos", Vector2i.ZERO)
	var alpha := 0.18 if not is_current else 0.35
	var color := _sense_color(sense_type, alpha)
	var sp := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)

	draw_rect(Rect2(sp, Vector2(CELL_SIZE, CELL_SIZE)), color, true)
	draw_rect(Rect2(sp + Vector2(8, 8), Vector2(CELL_SIZE - 16, CELL_SIZE - 16)), color.lightened(0.15), false, 2.0)
	_draw_entry_text(entry, sp, is_current)

func _draw_trail_entry(entry: Dictionary, sense_type: String, is_current: bool) -> void:
	var alpha := 0.16 if not is_current else 0.32
	var color := _sense_color(sense_type, alpha)
	var trail_cells: Array = entry.get("trail_cells", [])

	for p in trail_cells:
		if typeof(p) != TYPE_VECTOR2I:
			continue
		var sp := Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE)
		draw_rect(Rect2(sp + Vector2(10, 10), Vector2(CELL_SIZE - 20, CELL_SIZE - 20)), color, true)

	var source_pos: Vector2i = entry.get("source_pos", Vector2i.ZERO)
	var source_sp := Vector2(source_pos.x * CELL_SIZE, source_pos.y * CELL_SIZE)
	draw_rect(Rect2(source_sp, Vector2(CELL_SIZE, CELL_SIZE)), color, true)
	_draw_entry_text(entry, source_sp, is_current)

func _draw_echo_entry(entry: Dictionary, is_current: bool) -> void:
	var pos: Vector2i = entry.get("source_pos", Vector2i.ZERO)
	var alpha := 0.16 if not is_current else 0.34
	var color := _sense_color("echo", alpha)
	var sp := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var rect := Rect2(sp, Vector2(CELL_SIZE, CELL_SIZE))

	draw_rect(rect, color, true)
	draw_rect(rect, color.lightened(0.25), false, 1.5)
	_draw_echo_icon(str(entry.get("shape", "unknown")), rect, color.lightened(0.5))
	_draw_entry_text(entry, sp, is_current)

func _draw_echo_icon(shape: String, rect: Rect2, color: Color) -> void:
	var center := rect.position + rect.size * 0.5
	match shape:
		"human":
			draw_circle(center + Vector2(0, -10), 7.0, color)
			draw_line(center + Vector2(0, -2), center + Vector2(0, 14), color, 3.0)
			draw_line(center + Vector2(-8, 4), center + Vector2(8, 4), color, 2.0)
		"beast", "hulking":
			draw_circle(center, 12.0 if shape == "beast" else 15.0, color)
			draw_circle(center + Vector2(-10, -8), 4.0, color)
			draw_circle(center + Vector2(10, -8), 4.0, color)
		"wall":
			draw_line(rect.position + Vector2(10, rect.size.y * 0.5), rect.position + Vector2(rect.size.x - 10, rect.size.y * 0.5), color, 6.0)
		"pit":
			draw_circle(center, 14.0, Color(color.r, color.g, color.b, 0.0))
			draw_arc(center, 14.0, 0.0, TAU, 18, color, 3.0)
		"roots", "tracks":
			for i in range(3):
				var x := rect.position.x + 16 + i * 12
				draw_line(Vector2(x, rect.position.y + rect.size.y - 12), Vector2(x - 4, rect.position.y + 16), color, 2.0)
		_:
			draw_circle(center, 10.0, color)

func _draw_entry_text(entry: Dictionary, screen_pos: Vector2, is_current: bool) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := str(entry.get("text", ""))
	if text == "":
		return
	var color := Color(1, 1, 1, 0.95 if is_current else 0.82)
	draw_string(font, screen_pos + Vector2(4, CELL_SIZE * 0.62), text, HORIZONTAL_ALIGNMENT_LEFT, CELL_SIZE * 2.4, 14, color)

func _sense_color(sense_type: String, alpha: float) -> Color:
	match sense_type:
		"hearing":
			return Color(0.2, 0.6, 1.0, alpha)
		"smell":
			return Color(0.6, 1.0, 0.2, alpha)
		"echo":
			return Color(1.0, 0.8, 0.2, alpha)
		_:
			return Color(1.0, 1.0, 1.0, alpha)
