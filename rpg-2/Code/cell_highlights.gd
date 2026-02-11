extends Node2D

@onready var map_manager: MapManager = get_tree().get_first_node_in_group("MapManager")
var selector: Node2D = null

var last_hovered_cell: Vector2i = Vector2i(-1, -1)
var cached_path: Array = []
var cached_move_range: Array[Vector2i] = []

var display_mode: String = "move"
var active_unit: Unit = null

func _ready() -> void:
	# Search for the selector
	selector = get_tree().get_first_node_in_group("Selector")
	
	if selector:
		selector.cell_hovered.connect(_on_cell_hovered)
	else:
		# If it's not found, print a helpful error for yourself!
		print("Error: CellHighlights couldn't find a node in group 'Selector'")

func _on_cell_hovered(_cell: Vector2i) -> void:
	queue_redraw()

func _draw() -> void:
	if not selector: 
		selector = get_tree().get_first_node_in_group("Selector")
		if not selector: return
	
	if Globals.show_cell_ocupancy:
		_draw_occupancy_overlay()

	if Globals.show_cell_outlines:
		_draw_grid()
	
	if not active_unit: 
		return
	
	var tile_size = Globals.TILE_SIZE
	var main_cell = map_manager.world_to_cell(active_unit.global_position)
	var draw_color = Color.CYAN if display_mode == "move" else Color.RED
	draw_color.a = 0.3
	
	# --- NEW: Draw Enemy Vision Cones in Exploration ---
	if Globals.current_mode == Globals.GameMode.EXPLORATION:
		_draw_enemy_detection_cones()
	
	# 2. Draw Selection Base
	var rect_pos = Vector2(main_cell * tile_size)
	var rect_size = Vector2(active_unit.data.grid_size * tile_size)
	draw_rect(Rect2(rect_pos, rect_size), draw_color, true)
	draw_rect(Rect2(rect_pos, rect_size), draw_color, false, 2.0)

	if not active_unit or active_unit.is_moving: 
		return

	if display_mode == "attack":
		_draw_hover_target_highlight()
		_draw_attack_range(Color(1, 0, 0, 0.3))
	else:
		_draw_move_range(Color(0, 0.5, 1, 0.3))
		_draw_path_preview()
		_draw_ghost_destination()

func set_active_unit(unit: Unit):
	active_unit = unit
	cached_move_range.clear() # Reset cache for new unit
	queue_redraw()

func _draw_occupancy_overlay() -> void:
	var tile_size = Globals.TILE_SIZE
	# We iterate our grid_data directly! Much faster than finding nodes.
	for cell in map_manager.grid_data:
		var data = map_manager.grid_data[cell]
		if data.is_occupied:
			var rect = Rect2(Vector2(cell * tile_size), Vector2(tile_size, tile_size))
			draw_rect(rect, Color(1, 0, 0, 0.2), true)
		
		# BONUS: Divinity Style - Highlight surfaces like Fire
		if data.surface_type == Globals.SurfaceType.FIRE:
			var rect = Rect2(Vector2(cell * tile_size), Vector2(tile_size, tile_size))
			draw_rect(rect, Color(1, 0.5, 0, 0.3), true) # Orange for fire

func _draw_grid() -> void:
	var t_size = float(Globals.TILE_SIZE)
	var region = map_manager.astar.region
	# Use line drawing for a cleaner grid if you want, or keep rects:
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var pos = Vector2(x, y) * t_size
			draw_rect(Rect2(pos, Vector2(t_size, t_size)), Color(0, 1, 1, 0.2), false, 1.0)

func _draw_move_range(color: Color) -> void:
	if not active_unit: return
	
	if cached_move_range.is_empty():
		_calculate_move_range_cache()
	
	var tile_size_vec = Vector2(Globals.TILE_SIZE, Globals.TILE_SIZE)
	
	for cell in cached_move_range:
		# Use the simpler math here:
		var rect_pos = Vector2(cell * Globals.TILE_SIZE)
		draw_rect(Rect2(rect_pos, tile_size_vec), color, true)

func _draw_enemy_detection_cones() -> void:
	var game = get_tree().get_first_node_in_group("Game")
	if not game: return

	for enemy in game.enemy_team.get_children():
		if enemy is Unit and enemy.data.ai_behavior:
			var ai = enemy.data.ai_behavior
			var center = game.map_manager.world_to_cell(enemy.global_position)
			
			# 1. Draw Proximity Circle (Diamond/Square shape)
			var prox_tiles = game._get_aoe_tiles(center, ai.proximity_radius, Globals.AreaShape.DIAMOND)
			for tile in prox_tiles:
				_draw_rect_at_cell(tile, Color(1, 0, 0, 0.2)) # Light Red
			
			# 2. Draw Vision Cone
			# Check tiles within detection_radius to see if they are in the FOV
			for x in range(-ai.detection_radius, ai.detection_radius + 1):
				for y in range(-ai.detection_radius, ai.detection_radius + 1):
					var target_cell = center + Vector2i(x, y)
					if _is_in_vision_cone(center, target_cell, ai):
						_draw_rect_at_cell(target_cell, Color(1, 1, 0, 0.15)) # Light Yellow

func _is_in_vision_cone(origin: Vector2i, target: Vector2i, ai: SlimeAI) -> bool:
	var dist = max(abs(origin.x - target.x), abs(origin.y - target.y))
	if dist > ai.detection_radius or dist == 0: return false
	
	var dir_to_target = (Vector2(target) - Vector2(origin)).normalized()
	return ai.facing_direction.dot(dir_to_target) >= 0.4

func _draw_rect_at_cell(cell: Vector2i, color: Color):
	var game = get_tree().get_first_node_in_group("Game")
	var rect = Rect2(game.map_manager.cell_to_world(cell) - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, color)

func _draw_cone_for_unit(origin: Vector2i, facing: Vector2, radius: int, fov: float, color: Color) -> void:
	var tile_size = Globals.TILE_SIZE
	
	# Loop through a square area that contains the radius
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var target_cell = origin + Vector2i(x, y)
			
			# 1. Range Check (Chebyshev or Euclidean, matching your AI logic)
			var dist = max(abs(x), abs(y)) 
			if dist > radius or dist == 0: continue
			
			if map_manager.is_within_bounds(target_cell):
				# 2. Angle Check
				var dir_to_cell = (Vector2(target_cell) - Vector2(origin)).normalized()
				var angle = rad_to_deg(facing.angle_to(dir_to_cell))
				
				if abs(angle) <= (fov / 2.0):
					# 3. LOS Check (Optional: Don't draw the cone behind walls)
					if map_manager.is_line_clear(origin, target_cell):
						var rect_pos = Vector2(target_cell * tile_size)
						draw_rect(Rect2(rect_pos, Vector2(tile_size, tile_size)), color, true)
						# Draw a subtle outline for the edge of the cone
						draw_rect(Rect2(rect_pos, Vector2(tile_size, tile_size)), Color(color.r, color.g, color.b, 0.3), false, 1.0)

func _calculate_move_range_cache() -> void:
	var start_cell = map_manager.world_to_cell(active_unit.global_position)
	var stamina = active_unit.stats.stamina
	var radius = floori(stamina / float(Globals.BASE_MOVE_COST))
	
	# Lift unit so it doesn't block its own range calculation
	var game_node = get_tree().root.find_child("Game", true, false)
	game_node.unregister_unit(active_unit)
	
	# Clear previous cache
	cached_move_range.clear()
	
	# Loop within the reachable radius
	for x in range(start_cell.x - radius, start_cell.x + radius + 1):
		for y in range(start_cell.y - radius, start_cell.y + radius + 1):
			var cell = Vector2i(x, y)
			
			if not map_manager.is_within_bounds(cell): 
				continue

			var result = map_manager.get_path_with_stamina(
				start_cell, 
				cell, 
				stamina, 
				active_unit.data.grid_size, 
				active_unit
			)

			# Only add to cache if the path is valid and reaches the target
			if not result[0].is_empty() and result[0].back() == cell:
				cached_move_range.append(cell)
			elif cell == start_cell:
				cached_move_range.append(cell)
	
	# Put the unit back after calculation
	game_node.register_unit_position(active_unit, start_cell)

func _draw_attack_range(color: Color) -> void:
	if not active_unit: return
	
	var unit_origin = map_manager.world_to_cell(active_unit.global_position)
	var unit_size = active_unit.data.grid_size
	var attack_range = active_unit.equipped_attack.attack_range
	
	# We loop through a large area around the unit
	for x in range(-attack_range, unit_size.x + attack_range):
		for y in range(-attack_range, unit_size.y + attack_range):
			var target_cell = unit_origin + Vector2i(x, y)
			
			# Check if this cell is within range of ANY tile the unit occupies
			if _is_in_range_of_footprint(unit_origin, unit_size, target_cell, attack_range):
				var rect = Rect2(Vector2(target_cell * 32), Vector2(32, 32))
				draw_rect(rect, color, true)

# Helper function for footprint math
func _is_in_range_of_footprint(origin: Vector2i, size: Vector2i, target: Vector2i, max_dist: int) -> bool:
	for x in range(size.x):
		for y in range(size.y):
			var occupied_tile = origin + Vector2i(x, y)
			
			# DIAGONAL FIX: Use max() here as well
			var dx = abs(occupied_tile.x - target.x)
			var dy = abs(occupied_tile.y - target.y)
			var d = max(dx, dy)
			
			if d <= max_dist:
				return true
	return false

func _draw_path_preview() -> void:
	# 1. Use cached_path! active_unit.path is only for live movement.
	if not active_unit or cached_path.is_empty():
		return
		
	var unit_size = active_unit.data.grid_size
	var tile_size = Globals.TILE_SIZE
	
	# 2. Iterate the WHOLE path. 
	# We start at 1 to skip the tile the unit is ALREADY on.
	for i in range(0, cached_path.size()):
		var cell = cached_path[i]
		
		# --- HAZARD CHECK ---
		var is_hazard = false
		for x in range(unit_size.x):
			for y in range(unit_size.y):
				var f_cell = cell + Vector2i(x, y)
				var d = map_manager.grid_data.get(f_cell)
				if d and d.surface_type != Globals.SurfaceType.NONE:
					is_hazard = true; break
		
		# Logic: If it's the last tile in the path, we can draw it differently 
		# or let the Ghost Destination handle it.
		#var is_last = (i == cached_path.size() - 1)
		var path_color = Color(1, 0, 0, 0.5) if is_hazard else Color(1, 1, 1, 0.4)
		
		var rect_pos = Vector2(cell * tile_size)
		var rect_size = Vector2(unit_size * tile_size)
		
		# Draw the step
		draw_rect(Rect2(rect_pos, rect_size), path_color, false, 2.0)
		path_color.a = 0.1
		draw_rect(Rect2(rect_pos, rect_size), path_color, true)

func _draw_ghost_destination() -> void:
	#if cached_path.is_empty(): 
	#	return
	var hovered_cell = selector.current_cell
	
	# 1. ONLY recalculate if the mouse actually moved
	if hovered_cell != last_hovered_cell:
		last_hovered_cell = hovered_cell
		
		var start_cell = map_manager.world_to_cell(active_unit.global_position)
		
		# We pass 'active_unit' so the pathfinder knows to ignore the unit's current body
		var result = map_manager.get_path_with_stamina(
			start_cell, 
			hovered_cell, 
			active_unit.stats.stamina, 
			active_unit.data.grid_size,
			active_unit # <--- New argument to ignore self
		)
		cached_path = result[0]
	
	# 2. Use the CACHED path for everything else
	if cached_path.is_empty():
		# Only draw the error box if we are actually inside the map 
		# but the path is blocked/too long
		if map_manager.is_within_bounds(hovered_cell):
			var error_pos = Vector2(hovered_cell * Globals.TILE_SIZE)
			draw_rect(Rect2(error_pos, Vector2(Globals.TILE_SIZE, Globals.TILE_SIZE)), Color(1, 0, 0, 0.5), true)
		return
	
	# 3. Draw logic (The "Land" point)
	var destination_cell = cached_path[-1]
	var tile_size = Globals.TILE_SIZE
	var grid_local_pos = Vector2(destination_cell * tile_size)

	var visual_scale = active_unit.data.visual_scale
	var region = active_unit.sprite.region_rect
	
	# Alignment Math
	var footprint_width = active_unit.data.grid_size.x * tile_size
	var sprite_width = region.size.x * visual_scale
	var centered_x = (footprint_width - sprite_width) / 2.0

	var draw_pos = grid_local_pos + Vector2(centered_x, 0) + active_unit.sprite.offset

	draw_texture_rect_region(
		active_unit.sprite.texture,
		Rect2(draw_pos, region.size * visual_scale),
		region,
		Color(1, 1, 1, 0.4)
	)

func _draw_hover_target_highlight() -> void:
	var hovered_cell = selector.current_cell 
	var game_node = get_tree().root.find_child("Game", true, false)
	if not game_node or not active_unit: return
	
	var attack = active_unit.equipped_attack
	if not attack: return
	
	# Before calculating AoE, check if we can even see the hovered cell
	var attacker_cell = game_node.map_manager.world_to_cell(active_unit.global_position)

	if not game_node.map_manager.is_line_clear(attacker_cell, hovered_cell):
		# Draw a "Blocked" highlight or just return
		var rect = Rect2(Vector2(hovered_cell * 32), Vector2(32, 32))
		draw_rect(rect, Color(0, 0, 0, 0.4), true) # Dark tint for blocked
		return
	
	# 1. Get the tiles affected by the AoE
	var aoe_tiles = game_node._get_aoe_tiles(hovered_cell, attack.aoe_range, attack.aoe_shape, attacker_cell)
	
	# 2. Draw the AoE tiles
	for cell in aoe_tiles:
		var rect = Rect2(Vector2(cell * 32), Vector2(32, 32))
		# Use a slightly different color for the "Center" of the attack
		var color = Color(1, 0.4, 0, 0.5) if cell == hovered_cell else Color(1, 0, 0, 0.3)
		draw_rect(rect, color, true)
	
	# 3. Highlight occupants within the AoE (Units or Objects)
	for cell in aoe_tiles:
		var occupant = game_node._get_occupant_at_cell(cell)
		if occupant and occupant != active_unit:
			_draw_occupant_highlight(occupant)

func _draw_occupant_highlight(occupant: Node2D) -> void:
	var o_size = occupant.data.grid_size
	var o_origin = map_manager.world_to_cell(occupant.global_position)
	var rect_pos = Vector2(o_origin * 32)
	var rect_size = Vector2(o_size * 32)
	
	# Draw a thick border around units/objects caught in the blast
	draw_rect(Rect2(rect_pos, rect_size), Color.YELLOW, false, 2.0)
