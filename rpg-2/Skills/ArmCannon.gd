# RadialKnockback.gd
extends SkillAction

func execute_skill(_attacker: Unit, victim: Unit, target_cell: Vector2i, attack: AttackResource, game: Node) -> void:
	if victim:
		var v_cell = game.map_manager.world_to_cell(victim.global_position)
		# Direction is FROM the explosion center TO the victim
		var dir = (v_cell - target_cell)
		
		if dir == Vector2i.ZERO: # Victim is exactly in center
			dir = Vector2i.UP # Default fallback
		else:
			dir = Vector2i(clampi(dir.x, -1, 1), clampi(dir.y, -1, 1))
			
		game.apply_knockback(victim, dir, attack.knockback_distance)
