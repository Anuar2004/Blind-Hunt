extends Node2D
class_name Player

const CELL_SIZE := 64

@export var draw_overworld_token := false
@onready var cam: Camera2D = $Camera2D

var overworld_visible := true


func _ready() -> void:
	add_to_group("player")
	_ensure_defaults()
	_sync_world_position_from_session()

	visible = draw_overworld_token and overworld_visible

	if cam:
		cam.enabled = false

	queue_redraw()


func _process(_delta: float) -> void:
	if overworld_visible:
		_sync_world_position_from_session()


func _draw() -> void:
	if not draw_overworld_token:
		return

	draw_rect(
		Rect2(Vector2(8, 8), Vector2(CELL_SIZE - 16, CELL_SIZE - 16)),
		Color(0.2, 0.8, 1.0, 0.6),
		true
	)


func _ensure_defaults() -> void:
	if not ("player_max_hp" in Session):
		Session.player_max_hp = int(Session.player_hp)


func _sync_world_position_from_session() -> void:
	position = Vector2(Session.player_pos.x * CELL_SIZE, Session.player_pos.y * CELL_SIZE)


func set_overworld_mode(enabled: bool) -> void:
	overworld_visible = enabled
	visible = enabled and draw_overworld_token

	if cam:
		cam.enabled = false


func take_damage(amount: int) -> void:
	amount = max(amount, 0)
	if amount <= 0:
		return

	Session.player_hp = max(0, int(Session.player_hp) - amount)
	Session.add_log("Ты получил урон: -" + str(amount) + " HP.")


func heal(amount: int) -> void:
	amount = max(amount, 0)
	if amount <= 0:
		return

	var max_hp := int(Session.player_max_hp)
	Session.player_hp = min(max_hp, int(Session.player_hp) + amount)
	Session.add_log("Ты восстановил " + str(amount) + " HP.")


func is_dead() -> bool:
	return int(Session.player_hp) <= 0


func get_hp() -> int:
	return int(Session.player_hp)


func get_max_hp() -> int:
	return int(Session.player_max_hp)
