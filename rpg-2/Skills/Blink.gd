extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, target_cell: Vector2i, _attack: AttackResource, game: Node) -> void:
	# Teleport should only happen once, in the tile-phase (victim is null)
	if victim == null:
		# 1. Use your existing MapManager function to check if the area is valid
		# We pass the attacker so the "is_occupied" check ignores the attacker itself
		if not game.map_manager.is_area_walkable(target_cell, attacker.data.grid_size, attacker):
			game._send_to_log("Teleport failed: Destination blocked!", Color.GRAY)
			return
			
		# 2. Update occupancy using the Game's helper
		# This handles unregistering the old spot and registering the new spot
		game.register_unit_position(attacker, target_cell)
		
		# 3. Move the visuals
		attacker.global_position = game.map_manager.cell_to_world(target_cell)
		
		# 4. Trigger surface entry logic (so standing on fire immediately hurts)
		attacker.cell_entered.emit(target_cell)
		game._send_to_log("%s warped to %s!" % [attacker.name, target_cell], Color.CYAN)
