extends Control
class_name HUD

@export var lines_to_show := 6

const PANEL_BG := Color(0, 0, 0, 0.58)
const PANEL_BORDER := Color(1, 1, 1, 0.16)
const TEXT_COLOR := Color(1, 1, 1, 0.95)
const MUTED_TEXT := Color(0.82, 0.82, 0.82, 0.92)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not Session.log_changed.is_connected(queue_redraw):
		Session.log_changed.connect(queue_redraw)
	if not Session.session_loaded.is_connected(queue_redraw):
		Session.session_loaded.connect(queue_redraw)
	if not Session.village_updated.is_connected(queue_redraw):
		Session.village_updated.connect(queue_redraw)
	if not Session.contract_changed.is_connected(queue_redraw):
		Session.contract_changed.connect(queue_redraw)
	if not Session.run_inventory_changed.is_connected(queue_redraw):
		Session.run_inventory_changed.connect(queue_redraw)

	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return

	_draw_status_stack(font)
	_draw_bottom_log(font)

	if _is_combat():
		_draw_combat_legend(font)

func _draw_status_stack(font) -> void:
	var panel_w := 280.0
	var x := 20.0
	if _is_village():
		x = _hud_size().x - panel_w - 20.0
	var start := Vector2(x, 20)

	var hp_panel_pos := start
	var hp_panel_size := Vector2(panel_w, 56)
	_draw_panel(hp_panel_pos, hp_panel_size)

	var hp := int(Session.player_hp)
	var max_hp := _get_player_max_hp()
	var hp_ratio := 0.0
	if max_hp > 0:
		hp_ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)

	draw_string(font, hp_panel_pos + Vector2(10, 18), "HP: %d / %d" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)

	var bar_pos := hp_panel_pos + Vector2(10, 30)
	var bar_size := Vector2(hp_panel_size.x - 20, 14)
	draw_rect(Rect2(bar_pos, bar_size), Color(0.15, 0.15, 0.15, 0.95), true)

	var hp_color := Color(0.85, 0.2, 0.2, 0.96)
	if hp_ratio > 0.66:
		hp_color = Color(0.25, 0.8, 0.35, 0.96)
	elif hp_ratio > 0.33:
		hp_color = Color(0.95, 0.72, 0.2, 0.96)

	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * hp_ratio, bar_size.y)), hp_color, true)

	var mode_panel_pos := hp_panel_pos + Vector2(0, 68)
	var mode_panel_size := Vector2(panel_w, 58)
	_draw_panel(mode_panel_pos, mode_panel_size)
	draw_string(font, mode_panel_pos + Vector2(10, 24), "Mode: " + _get_pretty_state_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)
	draw_string(font, mode_panel_pos + Vector2(10, 44), _get_mode_subtext(), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 20.0, 15, MUTED_TEXT)

	var senses_panel_pos := mode_panel_pos + Vector2(0, 68)
	var senses_panel_size := Vector2(panel_w, 96)
	_draw_panel(senses_panel_pos, senses_panel_size)
	draw_string(font, senses_panel_pos + Vector2(10, 18), "Senses", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)

	if _is_village():
		draw_string(font, senses_panel_pos + Vector2(10, 38), "Gold:     %d" % int(Session.gold), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, senses_panel_pos + Vector2(10, 56), "Backpack: %d" % int(Session.backpack_capacity), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, senses_panel_pos + Vector2(10, 74), "Profile:  auto-save", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, senses_panel_pos + Vector2(10, 92), "Contract: %s" % _short_contract_title(), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 20.0, 15, MUTED_TEXT)
	else:
		var hearing_lvl := int(Session.skills.get("hearing", 1))
		var smell_lvl := int(Session.skills.get("smell", 1))
		var echo_lvl := int(Session.skills.get("echo", 1))
		draw_string(font, senses_panel_pos + Vector2(10, 38), "Hearing: %d" % hearing_lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, senses_panel_pos + Vector2(10, 56), "Smell:   %d" % smell_lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, senses_panel_pos + Vector2(10, 74), ("Touch:   %d" if _is_combat() else "Echo:    %d") % echo_lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, senses_panel_pos + Vector2(10, 92), Session.get_contract_progress_text(), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 20.0, 15, MUTED_TEXT)

	if not _is_village():
		var run_panel_pos := senses_panel_pos + Vector2(0, 108)
		var run_panel_size := Vector2(panel_w, 94)
		_draw_panel(run_panel_pos, run_panel_size)
		draw_string(font, run_panel_pos + Vector2(10, 18), "Run", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)
		draw_string(font, run_panel_pos + Vector2(10, 38), "Backpack: %d / %d" % [Session.get_backpack_used(), int(Session.backpack_capacity)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, run_panel_pos + Vector2(10, 56), "Loot value: %d" % Session.get_carried_loot_value(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)
		draw_string(font, run_panel_pos + Vector2(10, 74), _loot_preview_inline(), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 20.0, 15, MUTED_TEXT)

func _draw_combat_legend(font) -> void:
	var hud_size := _hud_size()
	var panel_pos := Vector2(hud_size.x - 330.0 - 20.0, 20.0)
	var panel_size := Vector2(330, 104)
	_draw_panel(panel_pos, panel_size)

	draw_string(font, panel_pos + Vector2(10, 18), "Combat Legend", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)
	_draw_legend_row(font, panel_pos + Vector2(10, 34), Color(1.0, 0.2, 0.2, 0.70), "Threat zone")
	_draw_legend_row(font, panel_pos + Vector2(10, 54), Color(1.0, 1.0, 0.2, 0.70), "Smell trail / blood")
	_draw_legend_row(font, panel_pos + Vector2(10, 74), Color(0.2, 0.4, 1.0, 0.70), "Terrain felt by touch")
	_draw_legend_row(font, panel_pos + Vector2(10, 94), Color(0.2, 0.8, 1.0, 0.70), "Player")

func _draw_bottom_log(font) -> void:
	var hud_size := _hud_size()
	var start_idx = max(0, Session.log.size() - lines_to_show)

	var panel_w = min(hud_size.x - 40.0, 760.0)
	var line_h := 18.0
	var panel_h := 18.0 + float(lines_to_show) * line_h + 10.0
	var panel_pos := Vector2(20.0, hud_size.y - panel_h - 20.0)
	var panel_size := Vector2(panel_w, panel_h)

	_draw_panel(panel_pos, panel_size)
	draw_string(font, panel_pos + Vector2(10, 18), "Log", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)

	var y := panel_pos.y + 38.0
	for i in range(start_idx, Session.log.size()):
		draw_string(font, Vector2(panel_pos.x + 10.0, y), str(Session.log[i]), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 20.0, 15, MUTED_TEXT)
		y += line_h

func _draw_panel(pos: Vector2, panel_size: Vector2) -> void:
	draw_rect(Rect2(pos, panel_size), PANEL_BG, true)
	draw_rect(Rect2(pos, panel_size), PANEL_BORDER, false, 1.5)

func _draw_legend_row(font, pos: Vector2, swatch_color: Color, label: String) -> void:
	draw_rect(Rect2(pos, Vector2(14, 14)), swatch_color, true)
	draw_rect(Rect2(pos, Vector2(14, 14)), Color(1, 1, 1, 0.18), false, 1.0)
	draw_string(font, pos + Vector2(24, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED_TEXT)

func _get_player_max_hp() -> int:
	return max(1, int(Session.player_max_hp))

func _get_state_name() -> String:
	var gsm = get_tree().get_first_node_in_group("gsm")
	if gsm == null:
		return "Unknown"
	if "current_state" in gsm and gsm.current_state != null:
		var state = gsm.current_state
		if state is Node:
			return state.name
	return "Unknown"

func _get_pretty_state_name() -> String:
	var raw := _get_state_name()
	match raw:
		"VillageState":
			return "Village"
		"ExplorationState":
			return "Exploration"
		"CombatState":
			return "Combat"
		_:
			return raw

func _is_combat() -> bool:
	return _get_state_name() == "CombatState"

func _is_village() -> bool:
	return _get_state_name() == "VillageState"

func _get_mode_subtext() -> String:
	if _is_village():
		if Session.selected_contract.is_empty():
			return "Choose a contract"
		return str(Session.selected_contract.get("title", "Choose a contract"))
	return _get_exploration_phase_text()

func _get_exploration_phase_text() -> String:
	var phase = Session.get("exploration_turn_phase")
	match phase:
		"sense":
			return "Turn: Use a sense"
		"move":
			return "Turn: Move"
		_:
			return "Turn: Use a sense"

func _short_contract_title() -> String:
	if Session.selected_contract.is_empty():
		return "not selected"
	return str(Session.selected_contract.get("title", "contract"))

func _loot_preview_inline() -> String:
	if Session.get_carried_loot_count() <= 0:
		return "Loot: empty"
	var lines := Session.get_loot_preview_lines(1)
	if lines.is_empty():
		return "Loot: empty"
	return "Last: %s" % lines[0]

func _hud_size() -> Vector2:
	return get_viewport_rect().size
