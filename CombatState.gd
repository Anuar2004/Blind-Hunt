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
	if combat_manager:
		if not combat_manager.combat_finished.is_connected(_on_combat_finished):
			combat_manager.combat_finished.connect(_on_combat_finished)
		combat_manager.start_combat(_data)

func exit():
	print("EXIT: Combat")
	
func _on_combat_finished(result: Dictionary) -> void:
	machine.change_state("ExplorationState", result)

func handle_input(event: InputEvent):
	if combat_manager:
		combat_manager.handle_player_input(event)
