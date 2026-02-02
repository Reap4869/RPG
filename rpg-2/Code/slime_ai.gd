extends UnitAI
class_name SlimeAI

func make_decision(unit: Unit, game: Node, map_manager: MapManager) -> void:
	var start_cell = map_manager.world_to_cell(unit.global_position)
	var target_player = _find_closest_player(unit, game, map_manager)
	
	if not target_player:
		decision_completed.emit()
		return

	var target_cell = map_manager.world_to_cell(target_player.global_position)
	
	# --- ATTACK CHECK (Allows Diagonals) ---
	var dx = abs(target_cell.x - start_cell.x)
	var dy = abs(target_cell.y - start_cell.y)
	var attack_dist = max(dx, dy) # Chebyshev distance for diagonal attacks
	
	if attack_dist <= unit.equipped_attack.attack_range:
		# Get the cell coordinates of the player to attack
		var p_cell = map_manager.world_to_cell(target_player.global_position)
	
		# Pass the target cell AND the unit (the slime)
		game._execute_attack_at_cell(p_cell, unit) 
	
		decision_completed.emit()
		return

	# --- MOVEMENT (4-Directional only) ---
	var best_path = []
	var best_cost = 0.0
	
	# Only check North, South, East, West for destination
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	for dir in directions:
		var neighbor = target_cell + dir
		if map_manager.is_within_bounds(neighbor):
			var result = map_manager.get_path_with_stamina(start_cell, neighbor, unit.stats.stamina, unit.data.grid_size, unit)
			# We want the path that gets us closest (the shortest path to a neighbor)
			if not result[0].is_empty():
				if best_path.is_empty() or result[0].size() < best_path.size():
					best_path = result[0]
					best_cost = result[1]

	if not best_path.is_empty():
		unit.movement_finished.connect(_on_unit_finished_walking, CONNECT_ONE_SHOT)
		
		var world_path := PackedVector2Array()
		for c in best_path:
			world_path.append(map_manager.cell_to_world(c))
		unit.follow_path(world_path, best_cost)
	else:
		print(unit.name, " is stuck or already as close as possible.")
		decision_completed.emit()

func _on_unit_finished_walking(unit: Unit, _cell: Vector2i) -> void:
	# We use the 'unit' provided by the signal itself
	print(unit.name, " finished walking and is ending its turn.")
	decision_completed.emit()

# Helper to find the nearest player unit
func _find_closest_player(unit: Unit, game: Node, map_manager: MapManager) -> Unit:
	var closest_unit: Unit = null
	var min_dist = 9999
		
	for p in game.player_team.get_children():
		var p_cell = map_manager.world_to_cell(p.global_position)
		var u_cell = map_manager.world_to_cell(unit.global_position)
		var dx = abs(p_cell.x - u_cell.x)
		var dy = abs(p_cell.y - u_cell.y)
		var d = max(dx, dy)
		if d < min_dist:
			min_dist = d
			closest_unit = p
	return closest_unit
