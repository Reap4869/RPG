extends SkillAction

func execute_skill(attacker: Unit, victim: Unit, _target_cell: Vector2i, _attack: AttackResource, game: Node) -> void:
	if victim == null or not "stats" in victim:
		return

	# 1. Define your modifiers (You can also get these from the attack resource if you add variables)
	var int_modifier = 2.0      # How much INT contributes
	var stack_weight = 0.5     # How much each extra poison stack adds to the multiplier
	
	# 2. Get the Math
	var base_power = attacker.stats.current_intelligence * int_modifier
	var curse_multiplier = victim.stats.get_curse_score(stack_weight)
	var raw_punition_dmg = base_power * curse_multiplier
	
	# 3. Calculate final damage
	# Apply Resistance
	var resist_pct = victim.stats.get_resistance(Globals.DamageType.LOVE) # Or whichever type Punition is
	var final_dmg = roundi(raw_punition_dmg * (1.0 - resist_pct))
	
	# Log the breakdown similarly
	print("--- [SKILL: PUNITION] ---")
	print("Curses Found: %.1f | Resist: %d%%" % [curse_multiplier, roundi(resist_pct * 100)])
	print(">> TOTAL: %d" % final_dmg)
	
	if final_dmg > 0:
		victim.take_damage(final_dmg)
		game._spawn_damage_number(final_dmg, victim.global_position, Globals.DamageType.LOVE, AttackResource.HitResult.CRIT)
		game._send_to_log("%s's sins weigh heavily! Punition deals %d damage." % [victim.name, final_dmg], Color.DARK_ORCHID)
	else:
		game._send_to_log("%s is pure of heart... Punition failed." % victim.name, Color.WHITE)
