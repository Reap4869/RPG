extends Node2D
class_name PlayerController

var active_unit: Unit
var game: Node
var is_moving := false

func _ready():
	game = get_parent() # Or however you reference your main game script

func _process(_delta):
	#if active_unit:
		# print identity once per second (or remove after debugging)
		# For brevity we'll print every frame here while debugging
		#print("[PC] controlling:", active_unit.name, " instance:", active_unit)
	if Globals.current_mode == Globals.GameMode.EXPLORATION:
		_handle_exploration_movement()

func _handle_exploration_movement():
	# If we already have an active_unit assigned by Game.gd, use it.
	# Otherwise, fallback to the first player child.
	if not active_unit:
		var players = game.player_team.get_children()
		if players.size() > 0:
			active_unit = players[0]
	
	if not active_unit or active_unit.is_moving:
		return
		
	var input_dir := Vector2i.ZERO
	# Use 'else if' to ensure only one direction is picked per frame
	if Input.is_action_just_pressed("move_up"):      input_dir = Vector2i.UP
	elif Input.is_action_just_pressed("move_down"):  input_dir = Vector2i.DOWN
	elif Input.is_action_just_pressed("move_left"):  input_dir = Vector2i.LEFT
	elif Input.is_action_just_pressed("move_right"): input_dir = Vector2i.RIGHT
	
	if input_dir != Vector2i.ZERO:
		var map = game.map_manager
		var current_cell = active_unit.get_cell()
		var target_cell = current_cell + input_dir
		
		# CHECK: Is it in bounds? Is it a wall? Is it occupied by someone else?
		if map.is_within_bounds(target_cell):
			var cell_data = map.grid_data[target_cell]
			if not cell_data.is_wall and not cell_data.is_occupied:
				
				# CRITICAL: Tell the unit to leave its current cell before moving
				active_unit.leave_current_cells()
				
				var target_world = map.cell_to_unit_pos(target_cell)
				var path = PackedVector2Array([target_world])
				active_unit.follow_path(path, 0.0)
				
				# Connect to ensure it occupies the new cell when it arrives
				if not active_unit.movement_finished.is_connected(active_unit.occupy_new_cells):
					active_unit.movement_finished.connect(active_unit.occupy_new_cells, CONNECT_ONE_SHOT)
