extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, _target_cell: Vector2i, _attack: AttackResource, game: Node) -> void:
	if victim == null or not "stats" in victim:
		return

	# Since the system applied Bleed right before this, this will trigger!
	if victim.stats._has_buff("Bleed"):
		# Maybe melee heals for less but more consistently
		attacker.stats.health += 3
		attacker.stats.stamina += 2
		game._spawn_damage_number(3, attacker.global_position, Globals.DamageType.PHYSICAL, AttackResource.HitResult.HIT, "HEAL")
		game._send_to_log("%s tastes blood!" % attacker.name, Color.CRIMSON)
