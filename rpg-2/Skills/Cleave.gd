# CleaveKnockback.gd
extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, target_cell: Vector2i, attack: AttackResource, game: Node) -> void:
	if victim:
		var origin = game.map_manager.world_to_cell(attacker.global_position)
		var diff = target_cell - origin
		var dir = Vector2i(clampi(diff.x, -1, 1), clampi(diff.y, -1, 1))
		
		game.apply_knockback(victim, dir, attack.knockback_distance)
