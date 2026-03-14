extends Node2D

@export var cell_size := 64
@export var w := 8
@export var h := 8

var combat_manager: CombatManager

func _ready():
	combat_manager = get_tree().get_first_node_in_group("combat_manager")
	if combat_manager:
		if not combat_manager.changed.is_connected(queue_redraw):
			combat_manager.changed.connect(queue_redraw)

	queue_redraw()

func _process(_delta: float) -> void:
	var board_size := Vector2(w * cell_size, h * cell_size)
	position = (get_viewport_rect().size - board_size) * 0.5

func _draw():
	# Сетка
	for x in range(w + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, h * cell_size), Color.WHITE, 2.0)
	for y in range(h + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(w * cell_size, y * cell_size), Color.WHITE, 2.0)

	if combat_manager == null:
		return

	# 1) Terrain (синий)
	_draw_known_terrain()
	_draw_known_scent()

	# 2) Игрок
	var ppos: Vector2i = combat_manager.player_grid_pos
	var pr := Rect2(Vector2(ppos.x * cell_size, ppos.y * cell_size) + Vector2(8, 8), Vector2(cell_size - 16, cell_size - 16))
	draw_rect(pr, Color(0.2, 0.8, 1.0, 0.5), true)

	# 3) Threat (красный)
	_draw_enemy_threat_union()

	# DEBUG: реальные враги
	if combat_manager.debug_show_real_enemies:
		_draw_real_enemies()

func _draw_known_terrain() -> void:
	var terrain: Dictionary = combat_manager.terrain
	var known: Dictionary = combat_manager.known_terrain
	if terrain.is_empty() or known.is_empty():
		return

	for p in known.keys():
		if not terrain.has(p):
			continue

		var kind := str(terrain[p])
		var r := Rect2(Vector2(p.x * cell_size, p.y * cell_size), Vector2(cell_size, cell_size))

		if kind == "tree":
			# дерево (блок) — плотнее
			draw_rect(r, Color(0.2, 0.4, 1.0, 0.35), true)
		elif kind == "rise":
			# возвышенность — легче, обводкой (пока без механики)
			draw_rect(r, Color(0.2, 0.4, 1.0, 0.18), true)
			draw_rect(r.grow(-6), Color(0.2, 0.4, 1.0, 0.35), false, 2.0)

func _draw_known_scent() -> void:
	var scent: Dictionary = combat_manager.scent
	var known: Dictionary = combat_manager.known_scent
	if known.is_empty():
		return

	for p in known.keys():
		var alpha := 0.22

		if scent.has(p):
			var entry: Dictionary = scent[p]
			var kind := str(entry.get("kind", ""))
			if kind == "blood":
				var intensity = clamp(int(entry.get("intensity", 1)), 1, 5)
				alpha = 0.18 + 0.08 * float(intensity)

		var r := Rect2(Vector2(p.x * cell_size, p.y * cell_size), Vector2(cell_size, cell_size))
		draw_rect(r, Color(1.0, 1.0, 0.2, alpha), true)
		draw_rect(r.grow(-8), Color(1.0, 1.0, 0.2, min(alpha + 0.15, 0.55)), false, 2.0)

func _draw_enemy_threat_union() -> void:
	var blobs := combat_manager.enemy_candidates_by_enemy
	if blobs.is_empty():
		return

	for blob in blobs:
		for p in blob:
			if typeof(p) != TYPE_VECTOR2I:
				continue

			var r := Rect2(Vector2(p.x * cell_size, p.y * cell_size), Vector2(cell_size, cell_size))
			draw_rect(r, Color(1.0, 0.2, 0.2, 0.20), true)
			draw_rect(r.grow(-6), Color(1.0, 0.2, 0.2, 0.10), false, 1.0) 

func _draw_real_enemies() -> void:
	for i in range(combat_manager.enemy_positions.size()):
		var epos: Vector2i = combat_manager.enemy_positions[i]
		var rect := Rect2(
			Vector2(epos.x * cell_size, epos.y * cell_size) + Vector2(12, 12),
			Vector2(cell_size - 24, cell_size - 24)
		)
		draw_rect(rect, Color(1.0, 0.0, 0.0, 0.85), true)
