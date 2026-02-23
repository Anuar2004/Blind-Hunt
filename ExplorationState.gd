extends BaseState
class_name ExplorationState

@onready var overworld_layer := get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer := get_tree().get_first_node_in_group("combat_layer")
@onready var overworld_manager := get_tree().get_first_node_in_group("overworld_manager")

func enter(_data := {}):
	print("ENTER: Exploration")
	if overworld_layer: overworld_layer.visible = true
	if combat_layer: combat_layer.visible = false
	if overworld_layer: overworld_layer.queue_redraw()
	if overworld_manager and not overworld_manager.encounter_requested.is_connected(_on_encounter_requested):
		overworld_manager.encounter_requested.connect(_on_encounter_requested)

func exit():
	print("EXIT: Exploration")

func handle_input(event: InputEvent) -> void:
	if overworld_manager == null:
		return

	# --- Сенсы (пример: 1/2/3/0) ---
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				overworld_manager.use_sense("hearing", 1)
				overworld_layer.queue_redraw()
				return
			KEY_2:
				overworld_manager.use_sense("smell", 1)
				overworld_layer.queue_redraw()
				return
			KEY_3:
				overworld_manager.use_sense("echo", 1)
				overworld_layer.queue_redraw()
				return
			KEY_0:
				overworld_manager.clear_last_sense()
				overworld_layer.queue_redraw()
				return

	# --- Движение (только 4 направления; диагонали сделаем позже отдельными экшенами) ---
	if event.is_action_pressed("ui_up"):
		overworld_manager.try_move(Vector2i(0, -1))
		overworld_layer.queue_redraw()
	elif event.is_action_pressed("ui_down"):
		overworld_manager.try_move(Vector2i(0, 1))
		overworld_layer.queue_redraw()
	elif event.is_action_pressed("ui_left"):
		overworld_manager.try_move(Vector2i(-1, 0))
		overworld_layer.queue_redraw()
	elif event.is_action_pressed("ui_right"):
		overworld_manager.try_move(Vector2i(1, 0))
		overworld_layer.queue_redraw()

func _on_encounter_requested(data: Dictionary) -> void:
	machine.change_state("CombatState", data)
