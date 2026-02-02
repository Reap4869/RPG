extends Node2D

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i, button: int)

var map_manager: MapManager
var current_hovered_size := Vector2i(1, 1)
var current_size: Vector2i = Vector2i(1, 1) # Default size
var current_cell := Vector2i.ZERO

func _ready() -> void:
	# This waits until the whole tree is built before looking
	map_manager = get_node("../World/MapManager")

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var hovered_cell = map_manager.world_to_cell(mouse_pos)
	
	if hovered_cell != current_cell:
		current_cell = hovered_cell
		cell_hovered.emit(current_cell)
	
	# Faster way to get Game node
	var game_node = get_parent() 
	var final_box_cell = hovered_cell
	var new_size = Vector2i(1, 1)
	
	if game_node and game_node.has_method("_get_occupant_at_cell"):
		var occupant = game_node._get_occupant_at_cell(hovered_cell)
		
		if occupant is Unit:
			# FIX: Use 'occupant' instead of 'unit'
			final_box_cell = map_manager.world_to_cell(occupant.global_position)
			new_size = occupant.data.grid_size
		elif occupant is WorldObject:
			# SNAP: Objects also need to be snapped to their top-left origin
			final_box_cell = map_manager.world_to_cell(occupant.global_position)
			# If you ever make 2x2 crates, this handles it:
			# new_size = occupant.data.grid_size (if you add grid_size to ObjectData)
	
	current_size = new_size
	# Update position based on the top-left cell of the occupant
	global_position = Vector2(final_box_cell * Globals.TILE_SIZE)
	queue_redraw()

func _draw():
	# Draw the yellow outline based on current_size
	var rect_size = Vector2(current_size * Globals.TILE_SIZE)
	# Draw a thick yellow rectangle (false means outline only)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color.YELLOW, false, 2.0)

# FIXED: Changed from _input to _unhandled_input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		cell_clicked.emit(current_cell, event.button_index)
