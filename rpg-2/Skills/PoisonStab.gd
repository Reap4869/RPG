extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, _target_cell: Vector2i, attack: AttackResource, _game: Node) -> void:
	# 1. ALWAYS add this check first!
	if victim == null or not "stats" in victim:
		return
		
	# 2. Add the buff (The Stats.gd logic handles the "Toxin" stacking)
	if attack.buff_to_apply:
		victim.stats.add_buff(attack.buff_to_apply, false, attacker)
