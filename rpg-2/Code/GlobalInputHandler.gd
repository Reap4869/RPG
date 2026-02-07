extends Node

func _unhandled_input(event: InputEvent) -> void:
	# Quit Game
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	
	# Select Player Unit (F1)
	# This checks if you pressed the key you assigned in Input Map
	if event.is_action_pressed("select_player"):
		_select_first_player_unit()
	if event.is_action_pressed("toggle_debug"):
		_toggle_debug()
		
func _select_first_player_unit():
	var game_node = get_tree().root.find_child("Game", true, false)
	if game_node and game_node.has_method("select_player_unit"):
		game_node.select_player_unit()
		
func _toggle_debug() -> void:
	var game_node = get_tree().root.find_child("Game", true, false)
	if game_node and game_node.has_method("hide_debug_panel"):
		game_node.hide_debug_panel()
