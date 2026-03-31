extends Node2D

const PANEL_BG := Color(0.05, 0.06, 0.08, 0.92)
const PANEL_BG_SOFT := Color(0.08, 0.10, 0.14, 0.92)
const PANEL_BORDER := Color(1, 1, 1, 0.14)
const TEXT_COLOR := Color(1, 1, 1, 0.96)
const MUTED_TEXT := Color(0.82, 0.84, 0.88, 0.90)
const PLAYER_COLOR := Color(0.2, 0.8, 1.0, 0.72)
const DISABLED_TEXT := Color(0.58, 0.60, 0.64, 0.92)

const DIR_ORDER := [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1)
]

var overworld_manager: OverworldManager

var direction_rects: Dictionary = {}
var sense_button_rects: Dictionary = {}
var save_button_rect: Rect2 = Rect2()
var load_button_rect: Rect2 = Rect2()

var main_panel_rect: Rect2 = Rect2()
var side_panel_rect: Rect2 = Rect2()
var minimap_rect: Rect2 = Rect2()
var buttons_panel_rect: Rect2 = Rect2()
var player_center: Vector2 = Vector2.ZERO
var _last_viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	overworld_manager = get_tree().get_first_node_in_group("overworld_manager")

	if overworld_manager:
		if not overworld_manager.world_changed.is_connected(queue_redraw):
			overworld_manager.world_changed.connect(queue_redraw)

	if not Session.session_loaded.is_connected(queue_redraw):
		Session.session_loaded.connect(queue_redraw)

	if not Session.log_changed.is_connected(queue_redraw):
		Session.log_changed.connect(queue_redraw)

	_last_viewport_size = get_viewport_rect().size
	queue_redraw()


func _process(_delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size != _last_viewport_size:
		_last_viewport_size = viewport_size
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if overworld_manager == null:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_rebuild_layout()

			if _handle_action_click(mouse_event.position):
				get_viewport().set_input_as_handled()
				return

			for key in direction_rects.keys():
				if typeof(key) != TYPE_VECTOR2I:
					continue
				var dir: Vector2i = key

				var rect_value: Variant = direction_rects[key]
				if typeof(rect_value) != TYPE_RECT2:
					continue
				var rect: Rect2 = rect_value

				if rect.has_point(mouse_event.position):
					overworld_manager.try_move(dir)
					get_viewport().set_input_as_handled()
					return


func _handle_action_click(click_pos: Vector2) -> bool:
	for key in sense_button_rects.keys():
		if typeof(key) != TYPE_STRING:
			continue
		var sense_type: String = key

		var rect_value: Variant = sense_button_rects[key]
		if typeof(rect_value) != TYPE_RECT2:
			continue
		var rect: Rect2 = rect_value

		if rect.has_point(click_pos):
			overworld_manager.use_sense_by_skill(sense_type)
			return true

	if save_button_rect.has_point(click_pos):
		Session.save_game()
		return true

	if load_button_rect.has_point(click_pos):
		Session.load_game()
		return true

	return false


func _draw() -> void:
	_rebuild_layout()

	var viewport_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.01, 0.02, 0.94), true)

	_draw_panel(main_panel_rect)
	_draw_panel(side_panel_rect)

	var font := ThemeDB.fallback_font

	_draw_main_area(font)
	_draw_side_area(font)


func _rebuild_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	var left_reserved: float = 320.0
	var right_panel_w: float = clamp(viewport_size.x * 0.24, 280.0, 340.0)
	var top_margin: float = 20.0
	var bottom_reserved: float = 180.0
	var gap: float = 20.0

	var usable_h: float = max(260.0, viewport_size.y - top_margin - bottom_reserved)

	side_panel_rect = Rect2(
		Vector2(viewport_size.x - right_panel_w - 20.0, top_margin),
		Vector2(right_panel_w, usable_h)
	)

	var main_w: float = side_panel_rect.position.x - left_reserved - gap
	main_w = max(main_w, 280.0)

	main_panel_rect = Rect2(
		Vector2(left_reserved, top_margin),
		Vector2(main_w, usable_h)
	)

	player_center = main_panel_rect.position + main_panel_rect.size * 0.5

	var card_w: float = clamp(main_panel_rect.size.x * 0.18, 120.0, 160.0)
	var card_h: float = clamp(main_panel_rect.size.y * 0.18, 108.0, 126.0)

	var radius_x: float = min(main_panel_rect.size.x * 0.34, main_panel_rect.size.x * 0.5 - card_w * 0.78 - 18.0)
	var radius_y: float = min(main_panel_rect.size.y * 0.28, main_panel_rect.size.y * 0.5 - card_h * 0.78 - 18.0)

	radius_x = max(radius_x, 138.0)
	radius_y = max(radius_y, 96.0)

	direction_rects.clear()

	for dir in DIR_ORDER:
		var offset: Vector2 = _dir_layout_offset(dir)
		var center_pos: Vector2 = player_center + Vector2(offset.x * radius_x, offset.y * radius_y)
		var rect := Rect2(center_pos - Vector2(card_w, card_h) * 0.5, Vector2(card_w, card_h))
		direction_rects[dir] = rect

	var minimap_margin: float = 14.0
	var minimap_h: float = min(side_panel_rect.size.y * 0.58, side_panel_rect.size.y - 200.0)
	minimap_rect = Rect2(
		side_panel_rect.position + Vector2(minimap_margin, 34.0),
		Vector2(side_panel_rect.size.x - minimap_margin * 2.0, minimap_h)
	)

	buttons_panel_rect = Rect2(
		Vector2(side_panel_rect.position.x + 14.0, minimap_rect.position.y + minimap_rect.size.y + 14.0),
		Vector2(side_panel_rect.size.x - 28.0, side_panel_rect.position.y + side_panel_rect.size.y - (minimap_rect.position.y + minimap_rect.size.y + 14.0) - 14.0)
	)

	_rebuild_action_buttons()


func _rebuild_action_buttons() -> void:
	sense_button_rects.clear()

	var padding: float = 10.0
	var button_gap: float = 10.0
	var inner_x: float = buttons_panel_rect.position.x + padding
	var inner_w: float = buttons_panel_rect.size.x - padding * 2.0
	var sense_h: float = 52.0
	var util_h: float = 44.0

	var y: float = buttons_panel_rect.position.y + 34.0

	sense_button_rects["hearing"] = Rect2(Vector2(inner_x, y), Vector2(inner_w, sense_h))
	y += sense_h + button_gap
	sense_button_rects["smell"] = Rect2(Vector2(inner_x, y), Vector2(inner_w, sense_h))
	y += sense_h + button_gap
	sense_button_rects["echo"] = Rect2(Vector2(inner_x, y), Vector2(inner_w, sense_h))
	y += sense_h + 18.0

	var util_w: float = floor((inner_w - button_gap) * 0.5)
	save_button_rect = Rect2(Vector2(inner_x, y), Vector2(util_w, util_h))
	load_button_rect = Rect2(Vector2(inner_x + util_w + button_gap, y), Vector2(util_w, util_h))


func _draw_main_area(font) -> void:
	if font:
		draw_string(
			font,
			main_panel_rect.position + Vector2(18, 22),
			"Exploration",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			TEXT_COLOR
		)

		draw_string(
			font,
			main_panel_rect.position + Vector2(18, 44),
			_phase_prompt(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			MUTED_TEXT
		)

	for dir in DIR_ORDER:
		var rect_value: Variant = direction_rects.get(dir, Rect2())
		if typeof(rect_value) != TYPE_RECT2:
			continue
		var rect: Rect2 = rect_value

		draw_line(
			player_center,
			rect.get_center(),
			Color(1, 1, 1, 0.05),
			2.0
		)

	for dir in DIR_ORDER:
		var rect_value_2: Variant = direction_rects.get(dir, Rect2())
		if typeof(rect_value_2) != TYPE_RECT2:
			continue
		var rect_2: Rect2 = rect_value_2
		_draw_direction_card(font, dir, rect_2)

	_draw_player_core(font)


func _draw_player_core(font) -> void:
	var outer := Rect2(player_center - Vector2(64, 64), Vector2(128, 128))
	var inner := Rect2(player_center - Vector2(38, 38), Vector2(76, 76))

	draw_rect(outer, Color(1, 1, 1, 0.04), false, 2.0)
	draw_rect(inner, PLAYER_COLOR, true)
	draw_rect(inner, Color(1, 1, 1, 0.18), false, 2.0)

	if font:
		draw_string(
			font,
			player_center + Vector2(-70, 62),
			"Охотник",
			HORIZONTAL_ALIGNMENT_CENTER,
			140,
			16,
			TEXT_COLOR
		)

		draw_string(
			font,
			player_center + Vector2(-100, 84),
			"Позиция: (%d, %d)" % [Session.player_pos.x, Session.player_pos.y],
			HORIZONTAL_ALIGNMENT_CENTER,
			200,
			14,
			MUTED_TEXT
		)


func _draw_direction_card(font, dir: Vector2i, rect: Rect2) -> void:
	var target_pos: Vector2i = Session.player_pos + dir
	var entries: Array = _get_entries_for_pos(target_pos)
	var accent: Color = _card_accent_color(entries)
	var can_move_now: bool = false

	if overworld_manager and overworld_manager.has_method("can_move"):
		can_move_now = overworld_manager.can_move()

	var bg := PANEL_BG_SOFT
	if not can_move_now:
		bg = Color(0.08, 0.09, 0.11, 0.92)

	draw_rect(rect, bg, true)
	draw_rect(rect, accent if not entries.is_empty() else PANEL_BORDER, false, 2.0)

	if font == null:
		return

	var title_lines: Array[String] = _wrap_direction_title(_dir_arrow(dir), _dir_name(dir))
	var title_y: float = rect.position.y + 18.0

	for line in title_lines:
		draw_string(
			font,
			Vector2(rect.position.x + 10.0, title_y),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 20.0,
			14,
			TEXT_COLOR
		)
		title_y += 15.0

	var body_y: float = title_y + 6.0

	if entries.is_empty():
		var empty_lines := _wrap_text_lines("Нет подсказок", 18)
		_draw_wrapped_lines(font, empty_lines, rect, body_y, 13, MUTED_TEXT, 3)
		return

	var max_entries := 2
	var lines_left := 4

	for i in range(min(entries.size(), max_entries)):
		if lines_left <= 0:
			break

		var entry_value = entries[i]
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value

		var sense_type := str(entry.get("sense_type", ""))
		var line_color := _sense_color(sense_type, 0.96)
		var wrapped := _wrap_text_lines(str(entry.get("text", "")), 18)

		var used := _draw_wrapped_lines(font, wrapped, rect, body_y, 12, line_color, lines_left)
		body_y += float(used) * 14.0 + 2.0
		lines_left -= used

	if entries.size() > max_entries and lines_left > 0:
		draw_string(
			font,
			Vector2(rect.position.x + 10.0, body_y),
			"+%d ещё" % (entries.size() - max_entries),
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 20.0,
			12,
			MUTED_TEXT
		)

func _draw_side_area(font) -> void:
	if font:
		draw_string(
			font,
			side_panel_rect.position + Vector2(14, 22),
			"Minimap",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			TEXT_COLOR
		)

	_draw_minimap()
	_draw_buttons_panel(font)


func _draw_buttons_panel(font) -> void:
	_draw_panel(buttons_panel_rect)

	if font == null:
		return

	draw_string(
		font,
		buttons_panel_rect.position + Vector2(10, 18),
		"Actions",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		TEXT_COLOR
	)

	_draw_action_button(
		font,
		sense_button_rects.get("hearing", Rect2()),
		"Слух",
		"Использовать слух",
		_can_use_sense(),
		_sense_color("hearing", 0.45)
	)

	_draw_action_button(
		font,
		sense_button_rects.get("smell", Rect2()),
		"Нюх",
		"Использовать нюх",
		_can_use_sense(),
		_sense_color("smell", 0.45)
	)

	_draw_action_button(
		font,
		sense_button_rects.get("echo", Rect2()),
		"Эхо",
		"Использовать эхо",
		_can_use_sense(),
		_sense_color("echo", 0.45)
	)

	_draw_action_button(
		font,
		save_button_rect,
		"Сохранить",
		"Записать текущий run",
		true,
		Color(0.3, 0.7, 1.0, 0.30)
	)

	_draw_action_button(
		font,
		load_button_rect,
		"Загрузить",
		"Прочитать сохранение",
		true,
		Color(0.9, 0.7, 0.2, 0.30)
	)


func _draw_action_button(font, rect_value: Variant, title: String, subtitle: String, enabled: bool, accent: Color) -> void:
	if typeof(rect_value) != TYPE_RECT2:
		return
	var rect: Rect2 = rect_value

	var bg: Color = PANEL_BG_SOFT
	var border: Color = accent
	var title_color: Color = TEXT_COLOR
	var subtitle_color: Color = MUTED_TEXT

	if not enabled:
		bg = Color(0.08, 0.09, 0.11, 0.92)
		border = Color(1, 1, 1, 0.10)
		title_color = DISABLED_TEXT
		subtitle_color = DISABLED_TEXT

	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 2.0)

	draw_string(
		font,
		rect.position + Vector2(10, 18),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 20.0,
		15,
		title_color
	)

	draw_string(
		font,
		rect.position + Vector2(10, 38),
		subtitle,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 20.0,
		13,
		subtitle_color
	)


func _draw_minimap() -> void:
	draw_rect(minimap_rect, Color(0.03, 0.03, 0.05, 0.96), true)
	draw_rect(minimap_rect, PANEL_BORDER, false, 1.5)

	var bounds: Rect2i = _get_world_bounds()

	var fit_x: float = minimap_rect.size.x / float(max(1, bounds.size.x))
	var fit_y: float = minimap_rect.size.y / float(max(1, bounds.size.y))
	var cell_px: float = floor(min(fit_x, fit_y))
	cell_px = clamp(cell_px, 4.0, 22.0)

	var board_size := Vector2(float(bounds.size.x) * cell_px, float(bounds.size.y) * cell_px)
	var board_origin := minimap_rect.position + (minimap_rect.size - board_size) * 0.5

	for key in Session.world.keys():
		if typeof(key) != TYPE_VECTOR2I:
			continue
		var pos: Vector2i = key

		var local: Vector2i = pos - bounds.position
		var cell_rect := Rect2(
			board_origin + Vector2(float(local.x) * cell_px, float(local.y) * cell_px),
			Vector2(cell_px - 1.0, cell_px - 1.0)
		)

		draw_rect(cell_rect, Color(0.18, 0.18, 0.22, 1.0), true)
		draw_rect(cell_rect, Color(1, 1, 1, 0.06), false, 1.0)

	_draw_minimap_entry_overlays(board_origin, bounds, cell_px, Session.observations, false)

	if overworld_manager:
		_draw_minimap_entry_overlays(board_origin, bounds, cell_px, overworld_manager.last_sense_result, true)

	var player_local: Vector2i = Session.player_pos - bounds.position
	var player_rect := Rect2(
		board_origin + Vector2(float(player_local.x) * cell_px, float(player_local.y) * cell_px),
		Vector2(cell_px - 1.0, cell_px - 1.0)
	)
	draw_rect(player_rect, Color(0.2, 0.8, 1.0, 0.95), true)
	draw_rect(player_rect, Color(1, 1, 1, 0.24), false, 1.5)


func _draw_minimap_entry_overlays(board_origin: Vector2, bounds: Rect2i, cell_px: float, entries: Array, is_current: bool) -> void:
	for entry_value in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var sense_type := str(entry.get("sense_type", ""))

		match str(entry.get("kind", "")):
			"trail":
				var trail_cells = entry.get("trail_cells", [])
				if trail_cells is Array:
					for p in trail_cells:
						if typeof(p) != TYPE_VECTOR2I:
							continue
						_draw_minimap_overlay_cell(board_origin, bounds, cell_px, p, sense_type, is_current)

				var source_pos: Variant = entry.get("source_pos", Vector2i.ZERO)
				if typeof(source_pos) == TYPE_VECTOR2I:
					_draw_minimap_overlay_cell(board_origin, bounds, cell_px, source_pos, sense_type, is_current)

			_:
				var source_pos_2: Variant = entry.get("source_pos", Vector2i.ZERO)
				if typeof(source_pos_2) == TYPE_VECTOR2I:
					_draw_minimap_overlay_cell(board_origin, bounds, cell_px, source_pos_2, sense_type, is_current)


func _draw_minimap_overlay_cell(board_origin: Vector2, bounds: Rect2i, cell_px: float, pos: Vector2i, sense_type: String, is_current: bool) -> void:
	var local: Vector2i = pos - bounds.position
	var rect := Rect2(
		board_origin + Vector2(float(local.x) * cell_px, float(local.y) * cell_px),
		Vector2(cell_px - 1.0, cell_px - 1.0)
	)

	var inset: float = 1.0 if is_current else 2.0
	var overlay_rect := rect.grow(-inset)
	var alpha: float = 0.42 if is_current else 0.22
	var color := _sense_color(sense_type, alpha)

	draw_rect(overlay_rect, color, true)
	draw_rect(overlay_rect, Color(1, 1, 1, 0.08), false, 1.0)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL_BG, true)
	draw_rect(rect, PANEL_BORDER, false, 1.5)


func _get_world_bounds() -> Rect2i:
	var min_x: int = Session.player_pos.x
	var max_x: int = Session.player_pos.x
	var min_y: int = Session.player_pos.y
	var max_y: int = Session.player_pos.y

	for key in Session.world.keys():
		if typeof(key) != TYPE_VECTOR2I:
			continue
		var pos: Vector2i = key

		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)

	return Rect2i(
		Vector2i(min_x, min_y),
		Vector2i(max_x - min_x + 1, max_y - min_y + 1)
	)


func _get_entries_for_pos(target_pos: Vector2i) -> Array:
	var result: Array = []
	var seen: Dictionary = {}

	if overworld_manager:
		_collect_entries_for_pos(result, seen, overworld_manager.last_sense_result, target_pos)

	_collect_entries_for_pos(result, seen, Session.observations, target_pos)

	return result


func _collect_entries_for_pos(into: Array, seen: Dictionary, source: Array, target_pos: Vector2i) -> void:
	for entry_value in source:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value

		var source_pos: Variant = entry.get("source_pos", Vector2i.ZERO)
		if typeof(source_pos) != TYPE_VECTOR2I:
			continue
		if source_pos != target_pos:
			continue

		var signature := "%s|%s|%s|%s" % [
			str(entry.get("sense_type", "")),
			str(entry.get("kind", "")),
			str(source_pos),
			str(entry.get("text", ""))
		]

		if seen.has(signature):
			continue

		seen[signature] = true
		into.append(entry)


func _phase_prompt() -> String:
	var phase := str(Session.get("exploration_turn_phase"))
	if phase == "move":
		return "Выбери направление"
	return "Сначала используй чувство"


func _can_use_sense() -> bool:
	if overworld_manager and overworld_manager.has_method("can_use_sense"):
		return overworld_manager.can_use_sense()
	return false


func _card_accent_color(entries: Array) -> Color:
	if entries.is_empty():
		return Color(1, 1, 1, 0.18)

	var entry_value = entries[0]
	if typeof(entry_value) != TYPE_DICTIONARY:
		return Color(1, 1, 1, 0.18)

	var entry: Dictionary = entry_value
	return _sense_color(str(entry.get("sense_type", "")), 0.55)


func _fit_text(text: String, max_chars: int) -> String:
	if max_chars <= 0:
		return ""
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 1) + "…"
	
func _wrap_direction_title(arrow: String, title: String) -> Array[String]:
	var result: Array[String] = []
	result.append(arrow)

	if title.contains("-"):
		var parts := title.split("-", false, 1)
		if parts.size() == 2:
			result.append(parts[0] + "-")
			result.append(parts[1])
			return result

	result.append(title)
	return result


func _wrap_text_lines(text: String, max_chars: int) -> Array[String]:
	var result: Array[String] = []

	if max_chars <= 0:
		result.append(text)
		return result

	var clean := text.strip_edges()
	if clean.is_empty():
		result.append("")
		return result

	var words := clean.split(" ", false)
	var current := ""

	for word in words:
		if current.is_empty():
			if word.length() <= max_chars:
				current = word
			else:
				var chunks := _split_long_word(word, max_chars)
				for i in range(max(0, chunks.size() - 1)):
					result.append(chunks[i])
				current = chunks[chunks.size() - 1]
		else:
			var candidate := current + " " + word
			if candidate.length() <= max_chars:
				current = candidate
			else:
				result.append(current)
				if word.length() <= max_chars:
					current = word
				else:
					var chunks2 := _split_long_word(word, max_chars)
					for j in range(max(0, chunks2.size() - 1)):
						result.append(chunks2[j])
					current = chunks2[chunks2.size() - 1]

	if not current.is_empty():
		result.append(current)

	return result


func _split_long_word(word: String, max_chars: int) -> Array[String]:
	var result: Array[String] = []

	if word.length() <= max_chars:
		result.append(word)
		return result

	var start := 0
	while start < word.length():
		var take = min(max_chars, word.length() - start)
		result.append(word.substr(start, take))
		start += take

	return result


func _draw_wrapped_lines(font, lines: Array[String], rect: Rect2, start_y: float, font_size: int, color: Color, max_lines: int) -> int:
	var drawn := 0
	var y := start_y

	for i in range(min(lines.size(), max_lines)):
		draw_string(
			font,
			Vector2(rect.position.x + 10.0, y),
			lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 20.0,
			font_size,
			color
		)
		y += float(font_size) + 2.0
		drawn += 1

	return drawn


func _dir_layout_offset(dir: Vector2i) -> Vector2:
	match dir:
		Vector2i(0, -1):
			return Vector2(0.0, -1.10)
		Vector2i(1, -1):
			return Vector2(0.82, -0.78)
		Vector2i(1, 0):
			return Vector2(1.08, 0.0)
		Vector2i(1, 1):
			return Vector2(0.82, 0.78)
		Vector2i(0, 1):
			return Vector2(0.0, 1.10)
		Vector2i(-1, 1):
			return Vector2(-0.82, 0.78)
		Vector2i(-1, 0):
			return Vector2(-1.08, 0.0)
		Vector2i(-1, -1):
			return Vector2(-0.82, -0.78)
		_:
			return Vector2.ZERO


func _dir_name(dir: Vector2i) -> String:
	match dir:
		Vector2i(0, -1):
			return "Север"
		Vector2i(1, -1):
			return "Северо-восток"
		Vector2i(1, 0):
			return "Восток"
		Vector2i(1, 1):
			return "Юго-восток"
		Vector2i(0, 1):
			return "Юг"
		Vector2i(-1, 1):
			return "Юго-запад"
		Vector2i(-1, 0):
			return "Запад"
		Vector2i(-1, -1):
			return "Северо-запад"
		_:
			return "Направление"


func _dir_arrow(dir: Vector2i) -> String:
	match dir:
		Vector2i(0, -1):
			return "↑"
		Vector2i(1, -1):
			return "↗"
		Vector2i(1, 0):
			return "→"
		Vector2i(1, 1):
			return "↘"
		Vector2i(0, 1):
			return "↓"
		Vector2i(-1, 1):
			return "↙"
		Vector2i(-1, 0):
			return "←"
		Vector2i(-1, -1):
			return "↖"
		_:
			return "•"


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
