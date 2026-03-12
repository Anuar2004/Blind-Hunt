extends Control
class_name HUD

@export var lines_to_show := 8

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	if not Session.log_changed.is_connected(queue_redraw):
		Session.log_changed.connect(queue_redraw)

	if not Session.session_loaded.is_connected(queue_redraw):
		Session.session_loaded.connect(queue_redraw)

	queue_redraw()

func _draw() -> void:
	_draw_hp_panel()
	_draw_state_panel()
	_draw_log_panel()

func _draw_hp_panel() -> void:
	var hp := int(Session.player_hp)
	var max_hp := _get_player_max_hp()

	var panel_pos := Vector2(20, 20)
	var panel_size := Vector2(260, 52)

	draw_rect(Rect2(panel_pos, panel_size), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(1, 1, 1, 0.15), false, 1.5)

	var bar_margin := 10.0
	var bar_pos := panel_pos + Vector2(bar_margin, 28)
	var bar_size := Vector2(panel_size.x - bar_margin * 2.0, 14)

	draw_rect(Rect2(bar_pos, bar_size), Color(0.15, 0.15, 0.15, 0.9), true)

	var fill_ratio := 0.0
	if max_hp > 0:
		fill_ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)

	draw_rect(
		Rect2(bar_pos, Vector2(bar_size.x * fill_ratio, bar_size.y)),
		Color(0.85, 0.2, 0.2, 0.95),
		true
	)

	var font := ThemeDB.fallback_font
	if font == null:
		return

	draw_string(font, panel_pos + Vector2(10, 18), "HP: %d / %d" % [hp, max_hp])

func _draw_state_panel() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return

	var state_name := _get_state_name()
	var panel_pos := Vector2(300, 20)
	var panel_size := Vector2(220, 36)

	draw_rect(Rect2(panel_pos, panel_size), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(1, 1, 1, 0.15), false, 1.5)

	draw_string(font, panel_pos + Vector2(10, 22), "Mode: " + state_name)

func _draw_log_panel() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return

	var start = max(0, Session.log.size() - lines_to_show)

	var panel_pos := Vector2(20, 90)
	var line_h := 18.0
	var panel_size := Vector2(560, lines_to_show * line_h + 16.0)

	draw_rect(Rect2(panel_pos, panel_size), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(1, 1, 1, 0.15), false, 1.5)

	var y := panel_pos.y + 20.0
	for i in range(start, Session.log.size()):
		draw_string(font, Vector2(panel_pos.x + 10.0, y), str(Session.log[i]))
		y += line_h

func _get_player_max_hp() -> int:
	if "player_max_hp" in Session:
		return max(1, int(Session.player_max_hp))
	return max(1, int(Session.player_hp))

func _get_state_name() -> String:
	var gsm = get_tree().get_first_node_in_group("game_state_machine")
	if gsm == null:
		return "Unknown"

	if "current_state" in gsm and gsm.current_state != null:
		var state = gsm.current_state
		if state is Node:
			return state.name

	return "Unknown"
