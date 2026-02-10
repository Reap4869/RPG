extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, target_cell: Vector2i, _attack: AttackResource, game: Node) -> void:
	# PHASE 1: The Teleport (Runs when the tile is struck)
	if victim == null:
		var target_pos = game.map_manager.cell_to_world(target_cell)
		game.map_manager.move_unit_occupancy(attacker, target_cell)
		attacker.global_position = target_pos
		game._send_to_log("%s blinks into the fray!" % attacker.name, Color.PURPLE)
	
	# PHASE 2: The Extra Logic (Runs when a victim is found)
	else:
		# If you want to do something special to the unit you hit AFTER blinking
		# Example: Shred 10% of their armor
		#victim.stats.resistances[Globals.DamageType.PHYSICAL] -= 0.1
		return
