extends SkillAction

func execute_skill(_attacker: Unit, victim: Unit, _target_cell: Vector2i, _attack: AttackResource, game: Node) -> void:
	if victim == null or not "stats" in victim:
		return
	
	var stats = victim.stats
	var removed_names = []
	
	# Loop backwards when removing from an Array!
	for i in range(stats.active_buffs.size() - 1, -1, -1):
		var buff_data = stats.active_buffs[i]
		# If it's NOT positive, it's a debuff
		if not buff_data.resource.is_positive:
			removed_names.append(buff_data.resource.buff_name)
			stats.active_buffs.remove_at(i)
	
	if removed_names.is_empty():
		game._send_to_log("%s had no debuffs to dispel." % victim.name, Color.GRAY)
	else:
		# Print to console for you
		print("--- DISPEL LOG [%s] ---" % victim.name)
		for n in removed_names:
			print("Removed: %s" % n)
		print("-----------------------")
		
		# Log to the game UI
		var msg = "%s was Dispeled! Removed: %s" % [victim.name, ", ".join(removed_names)]
		game._send_to_log(msg, Color.CYAN)
		
		# Important: update the stats and icons
		stats.recalculate_stats()
		stats.buffs_updated.emit(stats.active_buffs)
