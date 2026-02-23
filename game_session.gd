extends Node
class_name GameSession

signal log_changed

# --- Player ---
var player_hp_max: int = 3
var player_hp: int = 3

var skills := {
	"hearing": 1,
	"smell": 1,
	"echo": 1
}

# --- Overworld ---
var world: Dictionary = {}         # Vector2i -> cell dict
var player_pos: Vector2i = Vector2i.ZERO
var observations: Array = []       # blurred memory entries

# Seed (опционально)
var seed_value: int = 0

# --- Log ---
var log: Array[String] = []
const LOG_MAX := 30

func new_game(new_seed: int = 0) -> void:
	if new_seed == 0:
		seed_value = randi()
	else:
		seed_value = new_seed

	seed(seed_value)

	player_hp_max = 3
	player_hp = player_hp_max
	skills = {"hearing": 1, "smell": 1, "echo": 1}

	world.clear()
	observations.clear()
	player_pos = Vector2i.ZERO

	log.clear()
	emit_signal("log_changed")

func add_log(msg: String) -> void:
	log.append(msg)
	if log.size() > LOG_MAX:
		log.pop_front()
	emit_signal("log_changed")
