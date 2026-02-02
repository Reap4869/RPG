class_name MapManager
extends Node

@onready var vfx_container_scene = preload("uid://pc6usvw46jfj")
@export var cell_size := Vector2i(32, 32)

var grid_data: Dictionary = {} # Key: Vector2i, Value: CellData
var astar: AStarGrid2D
var current_map_data: MapData
var current_visual_map: Node # This holds the instantiated TileMap
var current_map_size: Vector2i = Vector2i.ZERO

func _ready() -> void:
	add_to_group("MapManager")

func setup_map(data: MapData) -> void:
	load_map_from_resource(data)
	# If you add a "initial_surfaces" dictionary to MapData:
	# for cell in data.initial_surfaces:
	#    apply_surface_to_cell(cell, ...)
	var music_player = get_tree().root.find_child("MusicPlayer", true, false)
	if music_player and data.music:
		music_player.stream = data.music
		music_player.play()

func load_map_from_resource(data: MapData) -> void:
	if current_visual_map:
		current_visual_map.queue_free()
	
	current_map_data = data
	current_map_size = data.size
	
	if data.map_scene:
		current_visual_map = data.map_scene.instantiate()
		add_child(current_visual_map)
		_scan_tilemap_layers(current_visual_map)
	
	# 1. Setup AStar
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, data.size)
	astar.cell_size = cell_size
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	
	# 2. Build the Grid Data from the Resource
	grid_data.clear()
	for x in range(data.size.x):
		for y in range(data.size.y):
			var cell = Vector2i(x, y)
			var cell_info = CellData.new()
			
			# Get terrain type from MapData (defaults to NORMAL if not in dict)
			var type = data.terrain.get(cell, MapData.TerrainType.NORMAL)
			
			match type:
				MapData.TerrainType.WALL:
					cell_info.is_wall = true
					astar.set_point_solid(cell, true)
				MapData.TerrainType.MUD:
					cell_info.move_cost_multiplier = 1.5
					astar.set_point_weight_scale(cell, 1.5)
				MapData.TerrainType.WATER:
					# Example: Water is walkable but slow
					cell_info.move_cost_multiplier = 2.0
					astar.set_point_weight_scale(cell, 2.0)
			
			grid_data[cell] = cell_info

	# 3. Final AStar update
	astar.update()

func _scan_tilemap_layers(map_root: Node) -> void:
	# Find your layers by name
	var ground_layer = map_root.find_child("Ground") as TileMapLayer
	var wall_layer = map_root.find_child("Walls") as TileMapLayer
	
	if not ground_layer or not wall_layer:
		print("Warning: Could not find Ground or Walls layers!")
		return

	# Loop through all cells in the map size
	for x in range(current_map_size.x):
		for y in range(current_map_size.y):
			var cell = Vector2i(x, y)
			
			# 1. Check Walls Layer
			# If there is a tile in the Walls layer at this position, it's a wall
			if wall_layer.get_cell_source_id(cell) != -1:
				current_map_data.terrain[cell] = MapData.TerrainType.WALL
				continue # Skip further checks for this cell
			
			# 2. Check Ground Layer for Mud
			var tile_data = ground_layer.get_cell_tile_data(cell)
			if tile_data:
				# Check the Custom Data Layer you made in the editor
				if tile_data.get_custom_data("is_mud") == true:
					current_map_data.terrain[cell] = MapData.TerrainType.MUD

# Optimization: Only run this when something MOVES, not every frame
func update_astar_weights():
	for cell in grid_data:
		var data = grid_data[cell]
		astar.set_point_solid(cell, data.is_wall or data.is_occupied)
		
		# Divinity Style: Weight the path based on move cost
		# Higher weight = AStar avoids it unless necessary
		astar.set_point_weight_scale(cell, data.move_cost_multiplier)

# --- Keep all your existing functions below this line! ---

func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and \
			cell.x < current_map_size.x and \
			cell.y < current_map_size.y

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size.x, cell.y * cell_size.y) + Vector2(cell_size / 2)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos / Vector2(cell_size)).floor())

func get_path_with_stamina(start: Vector2i, end: Vector2i, stamina: float, unit_size: Vector2i, unit_to_ignore: Unit = null) -> Array:
	if not is_within_bounds(end) or grid_data[end].is_wall:
		return [[], 0.0]

	# 1. Update dynamic occupancy (Units)
	# We only do this right before pathfinding
	_refresh_dynamic_occupants(unit_to_ignore, unit_size)

	var id_path = astar.get_id_path(start, end)
	var valid_path: Array[Vector2i] = []
	var total_cost: float = 0.0 

	if id_path.is_empty():
		return [valid_path, 0.0]

	for i in range(1, id_path.size()):
		var cell = id_path[i]
		# divinity logic: Base Cost * Cell Multiplier
		var cell_multiplier = grid_data[cell].move_cost_multiplier
		var step_cost = Globals.BASE_MOVE_COST * cell_multiplier
		
		if total_cost + step_cost <= stamina:
			total_cost += step_cost
			valid_path.append(cell)
		else:
			break
			
	return [valid_path, total_cost]

func _refresh_dynamic_occupants(unit_to_ignore: Unit, moving_unit_size: Vector2i) -> void:
	for cell in grid_data:
		# A cell is "Solid" for this specific path if:
		# 1. It's a wall OR occupied by someone else
		# 2. OR a large unit wouldn't fit here (it would overlap a wall/unit)
		
		var is_base_solid = grid_data[cell].is_wall or (grid_data[cell].is_occupied and grid_data[cell].occupant != unit_to_ignore)
		
		# If the unit is larger than 1x1, we need to check if its whole body fits
		if not is_base_solid and moving_unit_size != Vector2i(1, 1):
			if not is_area_walkable(cell, moving_unit_size, unit_to_ignore):
				is_base_solid = true
				
		astar.set_point_solid(cell, is_base_solid)

func is_cell_walkable(cell: Vector2i) -> bool:
	if not current_map_data: return false
	return current_map_data.is_walkable(cell)

func is_area_walkable(top_left_cell: Vector2i, unit_size: Vector2i, unit_to_ignore: Unit = null) -> bool:
	for x in range(unit_size.x):
		for y in range(unit_size.y):
			var cell = top_left_cell + Vector2i(x, y)
			
			if not is_within_bounds(cell): return false
			
			var data = grid_data[cell]
			if data.is_wall: return false
			
			# If occupied, check if the occupant is someone else
			if data.is_occupied and data.occupant != unit_to_ignore:
				return false
				
	return true

func apply_surface_to_cell(cell: Vector2i, type: Globals.SurfaceType, duration: int, vfx_data: VisualEffectData) -> void:
	if not grid_data.has(cell): return
	
	var data = grid_data[cell]

	# 1. Clean up old node
	if is_instance_valid(data.surface_vfx_node):
		data.surface_vfx_node.queue_free()
	
	# 2. Update Data
	data.surface_type = type
	data.surface_timer = duration
	
	# 3. SPAWN THE VFX (Check if this part is actually running)
	if type != Globals.SurfaceType.NONE:
		if vfx_data == null:
			print("DEBUG: Cannot spawn surface because vfx_data is NULL!")
		else:
			_spawn_surface_vfx(cell, vfx_data)

func _spawn_surface_vfx(cell: Vector2i, vfx_data: VisualEffectData) -> void:
	var data = grid_data[cell]
	
	var vfx = vfx_container_scene.instantiate() as WorldVFX
	add_child(vfx)
	
	vfx.global_position = cell_to_world(cell)
	vfx.setup(vfx_data) # This now applies the scale!
	
	data.surface_vfx_node = vfx

func tick_surfaces() -> void:
	for cell in grid_data:
		var cell_info = grid_data[cell]
		# Use 'is_instance_valid' because the node might have queue_free'd itself
		if is_instance_valid(cell_info.surface_vfx_node):
			cell_info.surface_vfx_node.tick_turn()
		else:
			# If the node is gone, reset the data
			cell_info.surface_vfx_node = null
			cell_info.surface_type = Globals.SurfaceType.NONE
