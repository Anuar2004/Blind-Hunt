# res://scripts/states/CombatState.gd
extends BaseState
class_name CombatState

@onready var overworld_layer = get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer = get_tree().get_first_node_in_group("combat_layer")
@onready var combat_manager = get_tree().get_first_node_in_group("combat_manager")

func enter(_data := {}):
	print("ENTER: Combat")
	if overworld_layer: overworld_layer.visible = false
	if combat_layer: combat_layer.visible = true
	if combat_manager: combat_manager.start_combat(_data)

func exit():
	print("EXIT: Combat")

func handle_input(event: InputEvent):
	# Для теста: нажми E чтобы вернуться в поиск
	if event.is_action_pressed("to_exploration"):
		machine.change_state("ExplorationState")
