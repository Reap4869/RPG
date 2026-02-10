extends GridContainer # Change this from Control/HBox to GridContainer

signal attack_requested(index: int)

func update_buttons(unit: Unit) -> void:
	# 1. ALWAYS clear old buttons first, even if unit is null
	for child in get_children():
		child.queue_free()
	
	# 2. Hide and exit if no unit, or if it's an enemy/not player controlled
	if not unit or not unit.data or not unit.data.is_player_controlled:
		self.visible = false
		return
	
	# 3. Only now show and build buttons
	self.visible = true
	
	for i in range(unit.data.attacks.size()):
		var attack_data = unit.data.attacks[i]
		if not attack_data: continue
		
		var attack_name = attack_data.attack_name
		var btn = Button.new()
		btn.text = attack_data.attack_name
		
		# --- COOLDOWN LOGIC ---
		var max_cd = attack_data.cooldown_turns
		var current_cd = unit.stats.attack_cooldowns.get(attack_name, 0)
		
		if current_cd > 0:
			btn.text = "%s\nCD: %d/%d" % [attack_name, current_cd, max_cd]
			btn.modulate = Color(0.5, 0.5, 0.5, 0.8) # Gray out
			btn.disabled = true 
		else:
			btn.text = attack_name
		
		# --- HOTKEY MAPPING (1-9) ---
		if i < 9:
			var shortcut = Shortcut.new()
			var event = InputEventKey.new()
			event.keycode = KEY_1 + i # Maps KEY_1, KEY_2, etc.
			shortcut.events.append(event)
			btn.shortcut = shortcut
			# Optional: Show the hotkey on the button
			#btn.text = "[%d] " % (i + 1) + btn.text
		
		# Set a minimum size so the grid stays neat
		btn.custom_minimum_size = Vector2(60, 30) 
		
		# Connect the signal
		btn.pressed.connect(func(): attack_requested.emit(i))
		
		add_child(btn)


# This allows us to find a button by its index later
func set_button_text(index: int, new_text: String) -> void:
	if index >= 0 and index < get_child_count():
		var btn = get_child(index) as Button
		if btn:
			btn.text = new_text

# Add this so we can reset everything easily
func reset_all_button_names(unit: Unit) -> void:
	if not unit: return
	for i in range(unit.data.attacks.size()):
		set_button_text(i, unit.data.attacks[i].attack_name)
