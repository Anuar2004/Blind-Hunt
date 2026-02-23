# res://scripts/states/GameStateMachine.gd
extends Node
class_name GameStateMachine

@export var initial_state_path: NodePath

var current_state: BaseState

func _ready():
	# Назначим ссылку machine каждому состоянию
	for child in get_children():
		if child is BaseState:
			child.machine = self

	# Выберем стартовое состояние
	if initial_state_path != NodePath():
		var st = get_node(initial_state_path)
		change_state(st.name)
	else:
		# fallback: первое состояние-ребёнок
		for child in get_children():
			if child is BaseState:
				change_state(child.name)
				break

func change_state(state_name: String, data := {}):
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

func _unhandled_input(event: InputEvent):
	if current_state:
		current_state.handle_input(event)

func _process(delta: float):
	if current_state:
		current_state.update(delta)
