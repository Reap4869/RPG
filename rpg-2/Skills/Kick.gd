# Kick.gd
extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, _target: Vector2i, attack: AttackResource, game: Node) -> void:
	if victim:
		var a_cell = game.map_manager.world_to_cell(attacker.global_position)
		var v_cell = game.map_manager.world_to_cell(victim.global_position)
		var dir = (v_cell - a_cell)
		# Normalize to 1 tile
		dir = Vector2i(clampi(dir.x, -1, 1), clampi(dir.y, -1, 1))
		
		game.apply_knockback(victim, dir, attack.knockback_distance)
