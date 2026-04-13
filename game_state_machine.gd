# res://scripts/states/GameStateMachine.gd
extends Node
class_name GameStateMachine

@export var initial_state_path: NodePath

var current_state: BaseState

func _ready() -> void:
	for child in get_children():
		if child is BaseState:
			child.machine = self

	var resumed := Session.try_resume_autosave()
	if not resumed:
		Session.new_game()

	var target_state := Session.current_state_name
	if target_state == "" or get_node_or_null(target_state) == null:
		if initial_state_path != NodePath():
			var st = get_node(initial_state_path)
			target_state = st.name
		else:
			for child in get_children():
				if child is BaseState:
					target_state = child.name
					break

	var enter_data := {}
	if resumed and target_state == "CombatState":
		enter_data = {"resume_from_autosave": true}

	change_state(target_state, enter_data)

func change_state(state_name: String, data := {}) -> void:
	var next_state = get_node_or_null(state_name)
	if next_state == null:
		push_error("State not found: %s" % state_name)
		return
	if not (next_state is BaseState):
		push_error("Node is not a BaseState: %s" % state_name)
		return

	if current_state != null:
		current_state.exit()

	current_state = next_state
	current_state.enter(data)
	Session.mark_current_state(state_name)

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)
