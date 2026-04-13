extends BaseState
class_name VillageState

@onready var village_layer := get_tree().get_first_node_in_group("village_layer")
@onready var overworld_layer := get_tree().get_first_node_in_group("overworld_layer")
@onready var combat_layer := get_tree().get_first_node_in_group("combat_layer")
@onready var player := get_tree().get_first_node_in_group("player")

func enter(data := {}) -> void:
	print("ENTER: Village")

	if village_layer:
		village_layer.visible = true
		if village_layer.has_signal("contract_selected") and not village_layer.contract_selected.is_connected(_on_contract_selected):
			village_layer.contract_selected.connect(_on_contract_selected)
		if village_layer.has_signal("start_requested") and not village_layer.start_requested.is_connected(_on_start_requested):
			village_layer.start_requested.connect(_on_start_requested)
		if village_layer.has_signal("upgrade_requested") and not village_layer.upgrade_requested.is_connected(_on_upgrade_requested):
			village_layer.upgrade_requested.connect(_on_upgrade_requested)

	if overworld_layer:
		overworld_layer.visible = false
	if combat_layer:
		combat_layer.visible = false

	if player and player.has_method("set_overworld_mode"):
		player.set_overworld_mode(false)

	Session.in_village = true
	Session.request_autosave()

func exit() -> void:
	print("EXIT: Village")

func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_on_contract_selected(0)
				return
			KEY_2:
				_on_contract_selected(1)
				return
			KEY_3:
				_on_contract_selected(2)
				return
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_on_start_requested()
				return
			KEY_B:
				_on_upgrade_requested()
				return

func _on_contract_selected(index: int) -> void:
	Session.select_contract_by_index(index)

func _on_start_requested() -> void:
	if not Session.begin_selected_run():
		Session.add_log("Сначала выбери контракт.")
		return

	machine.change_state("ExplorationState", {"started_from_village": true})

func _on_upgrade_requested() -> void:
	Session.buy_backpack_upgrade()
