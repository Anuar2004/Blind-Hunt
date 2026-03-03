# res://scripts/states/CombatState.gd
extends BaseState
class_name CombatState

@onready var overworld_layer = get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer = get_tree().get_first_node_in_group("combat_layer")
@onready var combat_manager: CombatManager = get_tree().get_first_node_in_group("combat_manager")

func enter(data := {}):
	print("ENTER: Combat")
	if overworld_layer: overworld_layer.visible = false
	if combat_layer: combat_layer.visible = true

	if combat_manager:
		if not combat_manager.combat_finished.is_connected(_on_combat_finished):
			combat_manager.combat_finished.connect(_on_combat_finished)
		combat_manager.start_combat(data)

func exit():
	print("EXIT: Combat")

func handle_input(event: InputEvent) -> void:
	if combat_manager == null:
		return

	if event.is_action_pressed("toggle_debug_enemies"):
		combat_manager.toggle_debug_show_enemies()
		return

	# --- Сенсы (1/2/3) ---
	if event.is_action_pressed("sense_hearing"):
		combat_manager.use_sense("hearing")
		return
	if event.is_action_pressed("sense_smell"):
		combat_manager.use_sense("smell")
		return
	if event.is_action_pressed("sense_touch"):
		combat_manager.use_sense("touch")
		return

	# --- Атака ---
	if event.is_action_pressed("attack"):
		combat_manager.try_attack()
		return

	# --- Движение ---
	var dir := Vector2i.ZERO
	if event.is_action_pressed("ui_up"):
		dir = Vector2i(0, -1)
	elif event.is_action_pressed("ui_down"):
		dir = Vector2i(0, 1)
	elif event.is_action_pressed("ui_left"):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_right"):
		dir = Vector2i(1, 0)

	if dir != Vector2i.ZERO:
		combat_manager.try_move(dir)
		return

func _on_combat_finished(result: Dictionary) -> void:
	machine.change_state("ExplorationState", result)
