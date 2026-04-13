extends Control
class_name VillageLayer

signal contract_selected(index: int)
signal start_requested
signal upgrade_requested

const BG := Color(0.03, 0.03, 0.04, 0.97)
const PANEL_BG := Color(0.07, 0.08, 0.10, 0.94)
const PANEL_SOFT := Color(0.10, 0.11, 0.14, 0.94)
const BORDER := Color(1, 1, 1, 0.14)
const TEXT := Color(1, 1, 1, 0.96)
const MUTED := Color(0.82, 0.84, 0.88, 0.92)
const ACCENT := Color(0.2, 0.8, 1.0, 0.85)
const DISABLED := Color(0.50, 0.52, 0.56, 0.92)

var _last_viewport_size: Vector2 = Vector2.ZERO
var _contract_rects: Array[Rect2] = []
var _start_button_rect: Rect2 = Rect2()
var _upgrade_button_rect: Rect2 = Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	if not Session.session_loaded.is_connected(queue_redraw):
		Session.session_loaded.connect(queue_redraw)
	if not Session.contract_changed.is_connected(queue_redraw):
		Session.contract_changed.connect(queue_redraw)
	if not Session.village_updated.is_connected(queue_redraw):
		Session.village_updated.connect(queue_redraw)
	if not Session.log_changed.is_connected(queue_redraw):
		Session.log_changed.connect(queue_redraw)

	_last_viewport_size = get_viewport_rect().size
	queue_redraw()

func _process(_delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size != _last_viewport_size:
		_last_viewport_size = viewport_size
		queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_rebuild_layout()

			for i in range(_contract_rects.size()):
				if _contract_rects[i].has_point(mouse_event.position):
					emit_signal("contract_selected", i)
					get_viewport().set_input_as_handled()
					return

			if _start_button_rect.has_point(mouse_event.position):
				emit_signal("start_requested")
				get_viewport().set_input_as_handled()
				return

			if _upgrade_button_rect.has_point(mouse_event.position):
				emit_signal("upgrade_requested")
				get_viewport().set_input_as_handled()
				return

func _draw() -> void:
	_rebuild_layout()

	var font := ThemeDB.fallback_font
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	draw_rect(viewport_rect, BG, true)

	var left_rect := Rect2(Vector2(32, 32), Vector2(520, viewport_rect.size.y - 64))
	var center_rect := Rect2(Vector2(580, 32), Vector2(420, viewport_rect.size.y - 64))
	var right_rect := Rect2(Vector2(1030, 32), Vector2(max(260.0, viewport_rect.size.x - 1062.0), viewport_rect.size.y - 64))

	_draw_panel(left_rect)
	_draw_panel(center_rect)
	_draw_panel(right_rect)

	_draw_contracts(font, left_rect)
	_draw_main_panel(font, center_rect)
	_draw_meta_panel(font, right_rect)

func _rebuild_layout() -> void:
	_contract_rects.clear()
	var viewport_size := get_viewport_rect().size
	var card_w := 480.0
	var card_h := 140.0
	var start_x := 52.0
	var start_y := 86.0
	var gap := 18.0

	for i in range(3):
		_contract_rects.append(Rect2(Vector2(start_x, start_y + i * (card_h + gap)), Vector2(card_w, card_h)))

	_start_button_rect = Rect2(Vector2(612, 330), Vector2(356, 64))
	_upgrade_button_rect = Rect2(Vector2(1052, 180), Vector2(max(220.0, viewport_size.x - 1106.0), 56))

func _draw_contracts(font, rect: Rect2) -> void:
	if font:
		draw_string(font, rect.position + Vector2(16, 24), "Доска контрактов", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT)
		draw_string(font, rect.position + Vector2(16, 48), "Выбери цель вылазки. Клавиши: 1 / 2 / 3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)

	var contracts := Session.get_available_contracts()
	for i in range(min(contracts.size(), _contract_rects.size())):
		var card := _contract_rects[i]
		var contract: Dictionary = contracts[i]
		var selected := not Session.selected_contract.is_empty() and str(Session.selected_contract.get("id", "")) == str(contract.get("id", ""))
		_draw_contract_card(font, card, contract, selected, i)

func _draw_contract_card(font, rect: Rect2, contract: Dictionary, selected: bool, index: int) -> void:
	var bg := PANEL_SOFT if selected else PANEL_BG
	var border := ACCENT if selected else BORDER
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 2.0)

	if font == null:
		return

	draw_string(font, rect.position + Vector2(12, 20), "%d. %s" % [index + 1, str(contract.get("title", "Контракт"))], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 16, TEXT)
	draw_string(font, rect.position + Vector2(12, 44), str(contract.get("description", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 14, MUTED)
	draw_string(font, rect.position + Vector2(12, 96), "Награда: %d золота" % int(contract.get("reward_gold", 0)), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 14, TEXT)
	draw_string(font, rect.position + Vector2(12, 118), _contract_goal_text(contract), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 13, MUTED)

func _draw_main_panel(font, rect: Rect2) -> void:
	if font:
		draw_string(font, rect.position + Vector2(16, 24), "Деревня", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT)
		draw_string(font, rect.position + Vector2(16, 48), "Подготовка к следующей вылазке", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)

	var selected_title := "Контракт не выбран"
	if not Session.selected_contract.is_empty():
		selected_title = str(Session.selected_contract.get("title", "Контракт"))

	if font:
		draw_string(font, rect.position + Vector2(16, 92), "Выбранный контракт", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		draw_string(font, rect.position + Vector2(16, 118), selected_title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32.0, 16, ACCENT if not Session.selected_contract.is_empty() else MUTED)
		draw_string(font, rect.position + Vector2(16, 152), "Автосейв активен. Все изменения в деревне сохраняются сразу.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32.0, 14, MUTED)

	_draw_button(font, _start_button_rect, "Начать забег", "Enter / Space", Session.is_ready_to_start_run(), ACCENT)

	var summary_rect := Rect2(rect.position + Vector2(16, 430), Vector2(rect.size.x - 32.0, 220.0))
	_draw_panel(summary_rect)
	if font:
		draw_string(font, summary_rect.position + Vector2(12, 20), "Итог последней вылазки", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		var lines := _summary_lines()
		var y := summary_rect.position.y + 50.0
		for line in lines:
			draw_string(font, Vector2(summary_rect.position.x + 12.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, summary_rect.size.x - 24.0, 14, MUTED)
			y += 20.0

func _draw_meta_panel(font, rect: Rect2) -> void:
	if font:
		draw_string(font, rect.position + Vector2(16, 24), "Метапрогресс", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT)
		draw_string(font, rect.position + Vector2(16, 52), "Пока активен только рюкзак.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
		draw_string(font, rect.position + Vector2(16, 96), "Золото: %d" % Session.gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT)
		draw_string(font, rect.position + Vector2(16, 126), "Рюкзак: уровень %d" % Session.backpack_level, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		draw_string(font, rect.position + Vector2(16, 150), "Вместимость: %d слотов" % Session.backpack_capacity, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)

	var cost := Session.get_backpack_upgrade_cost()
	_draw_button(font, _upgrade_button_rect, "Улучшить рюкзак", "B · стоимость %d золота" % cost, Session.gold >= cost, Color(0.65, 1.0, 0.25, 0.85))

	var info_rect := Rect2(rect.position + Vector2(16, 270), Vector2(rect.size.x - 32.0, 220.0))
	_draw_panel(info_rect)
	if font:
		draw_string(font, info_rect.position + Vector2(12, 20), "Подсказки", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		var tips := [
			"1 / 2 / 3 — выбрать контракт",
			"Enter / Space — начать забег",
			"B — улучшить рюкзак",
			"В забеге добыча продаётся при возвращении"
		]
		var y := info_rect.position.y + 50.0
		for tip in tips:
			draw_string(font, Vector2(info_rect.position.x + 12.0, y), tip, HORIZONTAL_ALIGNMENT_LEFT, info_rect.size.x - 24.0, 14, MUTED)
			y += 22.0

func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL_BG, true)
	draw_rect(rect, BORDER, false, 1.5)

func _draw_button(font, rect: Rect2, title: String, subtitle: String, enabled: bool, accent: Color) -> void:
	var bg := PANEL_SOFT if enabled else Color(0.08, 0.09, 0.11, 0.92)
	var border := accent if enabled else BORDER
	var title_color := TEXT if enabled else DISABLED
	var subtitle_color := MUTED if enabled else DISABLED

	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 2.0)

	if font == null:
		return

	draw_string(font, rect.position + Vector2(12, 22), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 16, title_color)
	draw_string(font, rect.position + Vector2(12, 46), subtitle, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 13, subtitle_color)

func _summary_lines() -> Array[String]:
	if Session.last_run_summary.is_empty():
		return ["Здесь будет итог прошлого забега."]

	var out: Array[String] = []
	out.append("Контракт: %s" % str(Session.last_run_summary.get("title", "—")))
	out.append("Статус: %s" % _summary_status_label(str(Session.last_run_summary.get("status", "partial"))))
	if Session.last_run_summary.has("sold_loot_value"):
		out.append("Продано добычи: %d золота" % int(Session.last_run_summary.get("sold_loot_value", 0)))
	if Session.last_run_summary.has("total_gold_earned"):
		out.append("Итоговая прибыль: %d золота" % int(Session.last_run_summary.get("total_gold_earned", 0)))
	else:
		out.append("Награда: %d золота" % int(Session.last_run_summary.get("reward_gold", 0)))
	out.append(str(Session.last_run_summary.get("progress_text", "")))
	if Session.last_run_summary.has("failure_reason"):
		out.append("Причина: %s" % _failure_label(str(Session.last_run_summary.get("failure_reason", ""))))
	return out

func _contract_goal_text(contract: Dictionary) -> String:
	match str(contract.get("type", "")):
		"kill_count":
			return "Цель: %s x%d" % [_pack_label(str(contract.get("target_enemy_pack", ""))), int(contract.get("required_kills", 0))]
		"trophy_value":
			return "Цель: добыча ценностью %d" % int(contract.get("required_value", 0))
		_:
			return "Цель: контракт"

func _pack_label(pack: String) -> String:
	match pack:
		"dogs":
			return "Волки"
		"large_enemy":
			return "Крупный монстр"
		_:
			return pack

func _summary_status_label(status: String) -> String:
	match status:
		"success":
			return "контракт закрыт"
		"failure":
			return "провал"
		_:
			return "возврат без закрытия"

func _failure_label(reason: String) -> String:
	match reason:
		"combat_defeat":
			return "охотник пал в бою"
		_:
			return reason
