extends BaseState
class_name ExplorationState

@onready var overworld_layer := get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer := get_tree().get_first_node_in_group("combat_layer")
@onready var overworld_manager := get_tree().get_first_node_in_group("overworld_manager")
@onready var player := get_tree().get_first_node_in_group("player")

func enter(_data := {}):
	print("ENTER: Exploration")

	if overworld_layer:
		overworld_layer.visible = true
	if combat_layer:
		combat_layer.visible = false

	if player and player.has_method("set_overworld_mode"):
		player.set_overworld_mode(true)

	if typeof(_data) == TYPE_DICTIONARY and (_data.has("encounter_id") or _data.has("victory")):
		_apply_combat_result(_data)

	if Session.exploration_turn_phase != "sense" and Session.exploration_turn_phase != "move":
		Session.exploration_turn_phase = "sense"

	if overworld_manager and not overworld_manager.encounter_requested.is_connected(_on_encounter_requested):
		overworld_manager.encounter_requested.connect(_on_encounter_requested)

func exit():
	print("EXIT: Exploration")

func handle_input(_event: InputEvent) -> void:
	return

func _on_encounter_requested(data: Dictionary) -> void:
	machine.change_state("CombatState", data)

func _apply_combat_result(result: Dictionary) -> void:
	var victory: bool = bool(result.get("victory", false))
	var cell_pos: Vector2i = result.get("source_cell", Session.player_pos)

	if victory and Session.world.has(cell_pos):
		var cell = Session.world[cell_pos]
		cell["content_type"] = "empty"
		cell["cleared"] = true
