extends BaseState
class_name ExplorationState

@onready var overworld_layer := get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer := get_tree().get_first_node_in_group("combat_layer")
@onready var overworld_manager := get_tree().get_first_node_in_group("overworld_manager")

func enter(_data := {}):
	print("ENTER: Exploration")
	if overworld_layer: overworld_layer.visible = true
	if combat_layer: combat_layer.visible = false

	# применяем CombatResult если вернулись из боя
	if typeof(_data) == TYPE_DICTIONARY and (_data.has("encounter_id") or _data.has("victory")):
		_apply_combat_result(_data)

	if overworld_manager and not overworld_manager.encounter_requested.is_connected(_on_encounter_requested):
		overworld_manager.encounter_requested.connect(_on_encounter_requested)

func exit():
	print("EXIT: Exploration")

func handle_input(event: InputEvent) -> void:
	if overworld_manager == null:
		return

	# --- Сенсы ---
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				Session.save_game()
				return
			KEY_F9:
				Session.load_game()
				return
			KEY_1:
				overworld_manager.use_sense_by_skill("hearing")
				return
			KEY_2:
				overworld_manager.use_sense_by_skill("smell")
				return
			KEY_3:
				overworld_manager.use_sense_by_skill("echo")
				return
			KEY_0:
				overworld_manager.clear_last_sense()
				return

	# --- Движение ---
	if event.is_action_pressed("ui_up"):
		overworld_manager.try_move(Vector2i(0, -1))
	elif event.is_action_pressed("ui_down"):
		overworld_manager.try_move(Vector2i(0, 1))
	elif event.is_action_pressed("ui_left"):
		overworld_manager.try_move(Vector2i(-1, 0))
	elif event.is_action_pressed("ui_right"):
		overworld_manager.try_move(Vector2i(1, 0))

func _on_encounter_requested(data: Dictionary) -> void:
	machine.change_state("CombatState", data)

func _apply_combat_result(result: Dictionary) -> void:
	var victory: bool = bool(result.get("victory", false))
	var cell_pos: Vector2i = result.get("source_cell", Session.player_pos)

	# MVP: если победил — очищаем клетку
	if victory and Session.world.has(cell_pos):
		var cell = Session.world[cell_pos]
		cell["content_type"] = "empty"
		cell["cleared"] = true
