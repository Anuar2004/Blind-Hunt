# res://scripts/states/ExplorationState.gd
extends BaseState
class_name ExplorationState

@onready var overworld_layer = get_tree().get_first_node_in_group("overworld_layer")
@onready var overworld_manager = get_tree().get_first_node_in_group("overworld_manager")
@onready var combat_layer = get_tree().get_first_node_in_group("combat_layer")

func enter(_data := {}):
	print("ENTER: Exploration")
	if overworld_layer: overworld_layer.visible = true
	if combat_layer: combat_layer.visible = false

func exit():
	print("EXIT: Exploration")

func handle_input(event: InputEvent):
	# Для теста: нажми C чтобы перейти в бой
	if event.is_action_pressed("to_combat"):
		machine.change_state("CombatState")
	if event.is_action_pressed("ui_up"):
		overworld_manager.try_move(Vector2i(0, -1))
	if event.is_action_pressed("ui_down"):
		overworld_manager.try_move(Vector2i(0, 1))
	if event.is_action_pressed("ui_left"):
		overworld_manager.try_move(Vector2i(-1, 0))
	if event.is_action_pressed("ui_right"):
		overworld_manager.try_move(Vector2i(1, 0))
