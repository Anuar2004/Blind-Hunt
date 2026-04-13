extends BaseState
class_name ExplorationState

@onready var village_layer := get_tree().get_first_node_in_group("village_layer")
@onready var overworld_layer := get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer := get_tree().get_first_node_in_group("combat_layer")
@onready var overworld_manager := get_tree().get_first_node_in_group("overworld_manager")
@onready var player := get_tree().get_first_node_in_group("player")

func enter(data := {}) -> void:
	print("ENTER: Exploration")

	if village_layer:
		village_layer.visible = false
	if overworld_layer:
		overworld_layer.visible = true
	if combat_layer:
		combat_layer.visible = false

	if player and player.has_method("set_overworld_mode"):
		player.set_overworld_mode(true)

	if typeof(data) == TYPE_DICTIONARY and (data.has("encounter_id") or data.has("victory")):
		_apply_combat_result(data)

	if Session.exploration_turn_phase != "sense" and Session.exploration_turn_phase != "move":
		Session.exploration_turn_phase = "sense"

	if overworld_manager:
		if not overworld_manager.encounter_requested.is_connected(_on_encounter_requested):
			overworld_manager.encounter_requested.connect(_on_encounter_requested)
		if not overworld_manager.run_returned_home.is_connected(_on_run_returned_home):
			overworld_manager.run_returned_home.connect(_on_run_returned_home)
		if bool(data.get("started_from_village", false)) or Session.world.is_empty():
			overworld_manager.ensure_ring_with_minimum_signals(Session.player_pos)
			overworld_manager.emit_signal("world_changed")

func exit() -> void:
	print("EXIT: Exploration")

func handle_input(event: InputEvent) -> void:
	if overworld_manager == null or not Session.run_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
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
			KEY_R:
				overworld_manager.return_to_village_now()
				return

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

func _on_run_returned_home(summary: Dictionary) -> void:
	machine.change_state("VillageState", {"run_summary": summary})

func _apply_combat_result(result: Dictionary) -> void:
	Session.combat_snapshot.clear()

	var victory: bool = bool(result.get("victory", false))

	var source_cell_value = result.get("source_cell", Session.player_pos)
	var cell_pos: Vector2i = Session.player_pos

	if typeof(source_cell_value) == TYPE_VECTOR2I:
		cell_pos = source_cell_value
	elif source_cell_value is Array and source_cell_value.size() >= 2:
		cell_pos = Vector2i(int(source_cell_value[0]), int(source_cell_value[1]))

	if victory and Session.world.has(cell_pos):
		var cell = Session.world[cell_pos]
		cell["content_type"] = "empty"
		cell["cleared"] = true

	if victory:
		Session.register_kill(str(result.get("enemy_pack", "")), int(result.get("defeated_count", 0)))
		Session.add_log(Session.get_contract_progress_text())
		Session.request_autosave()
