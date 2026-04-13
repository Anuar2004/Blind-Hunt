extends BaseState
class_name CombatState

@onready var village_layer := get_tree().get_first_node_in_group("village_layer")
@onready var overworld_layer = get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer = get_tree().get_first_node_in_group("combat_layer")
@onready var combat_manager: CombatManager = get_tree().get_first_node_in_group("combat_manager")
@onready var player := get_tree().get_first_node_in_group("player")

func enter(data := {}) -> void:
	print("ENTER: Combat")

	if village_layer:
		village_layer.visible = false
	if overworld_layer:
		overworld_layer.visible = false
	if combat_layer:
		combat_layer.visible = true

	if player and player.has_method("set_overworld_mode"):
		player.set_overworld_mode(false)

	if combat_manager:
		if not combat_manager.combat_finished.is_connected(_on_combat_finished):
			combat_manager.combat_finished.connect(_on_combat_finished)

		if bool(data.get("resume_from_autosave", false)) and not Session.combat_snapshot.is_empty():
			combat_manager.restore_from_dict(Session.combat_snapshot)
		else:
			combat_manager.start_combat(data)

func exit() -> void:
	print("EXIT: Combat")

func handle_input(event: InputEvent) -> void:
	if combat_manager == null:
		return

	if event.is_action_pressed("toggle_debug_enemies"):
		combat_manager.toggle_debug_show_enemies()
		return

	if event.is_action_pressed("sense_hearing"):
		combat_manager.use_sense("hearing")
		return
	if event.is_action_pressed("sense_smell"):
		combat_manager.use_sense("smell")
		return
	if event.is_action_pressed("sense_touch"):
		combat_manager.use_sense("touch")
		return

	if event.is_action_pressed("attack"):
		combat_manager.try_attack()
		return

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
	Session.combat_snapshot.clear()
	if bool(result.get("victory", false)):
		machine.change_state("ExplorationState", result)
		return

	var summary := Session.finish_failed_run("combat_defeat")
	machine.change_state("VillageState", {"run_summary": summary})
