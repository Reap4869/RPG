extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, _target_cell: Vector2i, _attack: AttackResource, game: Node) -> void:
	# SAFETY: If there is no victim (tile-phase) or victim is an object without stats, exit.
	if victim == null or not "stats" in victim:
		return

	if victim.stats._has_buff("Bleed"):
		attacker.stats.health += 5
		attacker.stats.stamina += 5
		game._spawn_damage_number(5, attacker.global_position, Globals.DamageType.LOVE, AttackResource.HitResult.HIT, "HEAL")
