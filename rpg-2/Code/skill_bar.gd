# skill_bar.gd
extends GridContainer # Change this from Control/HBox to GridContainer

signal attack_requested(index: int)

func update_buttons(unit: Unit) -> void:
	# 1. Clear old buttons
	for child in get_children():
		child.queue_free()
	
	if not unit or not unit.data:
		return

	# 2. Create buttons from the unit's attack array
	for i in range(unit.data.attacks.size()):
		var attack_data = unit.data.attacks[i]
		if not attack_data: continue
		
		var btn = Button.new()
		btn.text = attack_data.attack_name
		
		# Set a minimum size so the grid stays neat
		btn.custom_minimum_size = Vector2(80, 40) 
		
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
