extends UnitAI
class_name SlimeAI

enum Personality { MELEE_FIRST, RANGED_FIRST }
@export var behavior: Personality = Personality.MELEE_FIRST

func make_decision(unit: Unit, game: Node, map_manager: MapManager) -> void:
	print("[AI LOGIC] Starting decision for ", unit.name)
	var start_cell = map_manager.world_to_cell(unit.global_position)
	var target_player = _find_closest_player(unit, game, map_manager)
	
	if not target_player:
		print("[AI LOGIC] No targets found. Ending turn.")
		decision_completed.emit()
		return

	var target_cell = map_manager.world_to_cell(target_player.global_position)
	var attack_to_use = _choose_attack(unit)
	unit.equipped_attack = attack_to_use
	
	var dist = _get_chebyshev_dist(start_cell, target_cell)
	var has_los = game.map_manager.is_line_clear(start_cell, target_cell)
	
	print("[AI LOGIC] Target: ", target_player.name, " Dist: ", dist, " Range: ", attack_to_use.attack_range, " LOS: ", has_los)

	# --- CAN ATTACK ---
	if dist <= attack_to_use.attack_range and has_los:
		print("[AI LOGIC] Attacking ", target_player.name)
		game.active_unit = unit 
		unit.stats.stamina -= attack_to_use.stamina_cost
		unit.stats.mana -= attack_to_use.mana_cost
		
		var targets: Array[Vector2i] = [target_cell]
		game._execute_multi_target_attack(targets)
		
		await game.attack_finished
		game.active_unit = null
		print("[AI LOGIC] Attack finished and active_unit cleared.")
		decision_completed.emit()
	
	# --- MUST MOVE ---
	else:
		print("[AI LOGIC] Target out of range or no LOS. Attempting movement.")
		_handle_movement_logic(unit, target_cell, attack_to_use, map_manager)

func _choose_attack(unit: Unit) -> AttackResource:
	var attacks = unit.data.attacks
	if attacks.size() < 2: return attacks[0]
	
	var melee = attacks[0] # Usually index 0
	var ranged = attacks[1] # Usually index 1
	var can_afford_ranged = unit.stats.mana >= ranged.mana_cost and unit.stats.stamina >= ranged.stamina_cost
	
	if behavior == Personality.MELEE_FIRST:
		# If close or can't afford ranged, go melee
		return melee if unit.stats.stamina >= melee.stamina_cost else melee
	else:
		# Ranged personality
		return ranged if can_afford_ranged else melee

func _handle_movement_logic(unit: Unit, target_cell: Vector2i, attack: AttackResource, map_manager: MapManager) -> void:
	var start_cell = map_manager.world_to_cell(unit.global_position)
	var best_path = []
	var best_cost = 0.0
	
	# Find tiles we can attack from
	var possible_destinations = _get_tiles_at_range(target_cell, attack.attack_range, map_manager)
	print("[AI MOVE] Found ", possible_destinations.size(), " potential attack spots.")
	
	for dest in possible_destinations:
		var result = map_manager.get_path_with_stamina(start_cell, dest, unit.stats.stamina, unit.data.grid_size, unit)
		if not result[0].is_empty():
			if best_path.is_empty() or result[0].size() < best_path.size():
				best_path = result[0]
				best_cost = result[1]

	if not best_path.is_empty():
		print("[AI MOVE] Path found. Moving...")
		unit.movement_finished.connect(_on_unit_finished_walking, CONNECT_ONE_SHOT)
		var world_path := PackedVector2Array()
		for c in best_path:
			world_path.append(map_manager.cell_to_world(c))
		unit.follow_path(world_path, best_cost)
	else:
		print("[AI MOVE] No valid path to attack range. Ending turn.")
		decision_completed.emit()

func _get_tiles_at_range(target: Vector2i, attack_range: int, map_manager: MapManager) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for x in range(-attack_range, attack_range + 1):
		for y in range(-attack_range, attack_range + 1):
			if max(abs(x), abs(y)) == attack_range:
				var cell = target + Vector2i(x, y)
				if map_manager.is_within_bounds(cell) and not map_manager.grid_data[cell].is_wall:
					points.append(cell)
	return points

func _get_chebyshev_dist(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

func _on_unit_finished_walking(_unit: Unit, _cell: Vector2i) -> void:
	decision_completed.emit()

func _find_closest_player(unit: Unit, game: Node, map_manager: MapManager) -> Unit:
	var closest_unit: Unit = null
	var min_dist = 9999
	for p in game.player_team.get_children():
		var d = _get_chebyshev_dist(map_manager.world_to_cell(p.global_position), map_manager.world_to_cell(unit.global_position))
		if d < min_dist:
			min_dist = d
			closest_unit = p
	return closest_unit
