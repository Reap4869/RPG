extends Node

@export var starting_map: MapData 
@export var fire_vfx_resource: VisualEffectData

@onready var world = $World
@onready var map_manager = $World/MapManager
@onready var units_manager = $World/UnitsManager
@onready var objects_manager = $World/Objects
@onready var player_team: PlayerGroup = $World/UnitsManager/PlayerGroup
@onready var enemy_team: EnemyGroup = $World/UnitsManager/EnemyGroup
@onready var selector = $Selector
@onready var highlights = $World/CellHighlights
@onready var main_ui = $UI/MainUI
@onready var unit_info_panel = $UI/MainUI/UnitInfoPanel

var occupancy_grid: Dictionary = {}
var active_unit: Unit = null
var selected_unit: Unit = null
var enemy_queue: Array = []
var multi_target_selection: Array[Vector2i] = []
var current_attack_index: int = -1
var active_hold_sfx: AudioStreamPlayer2D = null
var active_hold_vfx: Node = null
var is_attack_in_progress: bool = false # The "Lock"

var current_mode := InteractionMode.SELECT
enum InteractionMode { SELECT, ATTACK }

const WORLD_VFX_SCENE = preload("uid://pc6usvw46jfj")

func _ready() -> void:
	player_team.player_defeated.connect(_trigger_game_over)
	enemy_team.enemies_defeated.connect(_trigger_victory)
	selector.cell_clicked.connect(_on_selector_clicked)
	if $MusicPlayer.stream:
		$MusicPlayer.play()
	$UI/MainUI.end_turn_requested.connect(_on_end_turn_button_pressed)
	$UI/MainUI.attack_requested.connect(_on_attack_requested)
	
	if starting_map:
		_initialize_battle(starting_map)
	else:
		print("Warning: No starting_map assigned!")

# --- INPUT HANDLING ---

func select_player_unit() -> void:
	# 1. Find the player unit
	var units = player_team.get_children()
	if units.size() == 0:
		return
		
	var unit_to_select = units[0]
	
	# 2. Select it (updates UI and Highlights)
	_set_active_unit(unit_to_select)
	
	# 3. Move Camera and Clamp it
	var cam = get_viewport().get_camera_2d()
	if cam:
		cam.global_position = unit_to_select.global_position
		if cam.has_method("force_clamp"):
			cam.force_clamp()
			

func _on_selector_clicked(cell: Vector2i, button: int) -> void:
	if is_attack_in_progress: return # Don't allow canceling mid-animation
		
	if Globals.current_state != Globals.TurnState.PLAYER_TURN:
		return

	if button == MOUSE_BUTTON_LEFT:
		if current_mode == InteractionMode.ATTACK:
			_handle_attack_input(cell)
		else:
			_handle_selection(cell)
	elif button == MOUSE_BUTTON_RIGHT:
		# If we have an active player unit, handle their movement
		if active_unit and active_unit.data.is_player_controlled:
			if current_mode == InteractionMode.ATTACK:
				var attack = active_unit.equipped_attack
				_stop_hold_effects()
				main_ui.skill_bar.set_button_text(current_attack_index, attack.attack_name)
				_set_interaction_mode(InteractionMode.SELECT)
				multi_target_selection.clear()
			else:
				_handle_movement(cell)
				

# --- INITIALIZATION ---

func _initialize_battle(map_resource: MapData) -> void:
	# 1. Clear the "Boss's" record
	occupancy_grid.clear()
	
	# 2. Tell the MapManager to build the walls and start the music
	map_manager.setup_map(map_resource)
	
	# 3. Ensure the Boss is listening for new units
	if not units_manager.unit_spawned.is_connected(_on_unit_registered):
		units_manager.unit_spawned.connect(_on_unit_registered)
	
	# 4. Tell the other Managers to spawn their things
	units_manager.setup_units(map_resource)
#	objects_manager.setup_objects(map_resource) # Pass the whole resource!
	
	# 5. Position the camera
	_setup_camera(map_resource)
	
	if not objects_manager.object_spawned.is_connected(_on_object_registered):
		objects_manager.object_spawned.connect(_on_object_registered)
		
	objects_manager.setup_objects(map_resource)

# --- COMBAT LOGIC ---

func _on_attack_requested(index: int) -> void:
	if active_unit and not active_unit.is_moving:
		_stop_hold_effects() # Clean up any previous loops first
		
		current_attack_index = index
		multi_target_selection.clear()
		active_unit.switch_attack(index)
		
		var attack = active_unit.equipped_attack
		
		# Start Hold SFX
		if attack.hold_sfx:
			active_hold_sfx = AudioStreamPlayer2D.new()
			active_hold_sfx.stream = attack.hold_sfx
			active_unit.add_child(active_hold_sfx)
			active_hold_sfx.play()
			
		# Start Hold VFX (Like a glow in the hand)
		if attack.hold_vfx:
			active_hold_vfx = WORLD_VFX_SCENE.instantiate()
			active_unit.add_child(active_hold_vfx)
			active_hold_vfx.setup(attack.hold_vfx)

		_set_interaction_mode(InteractionMode.ATTACK)
		_update_highlights()

# Helper function to clean up
func _stop_hold_effects() -> void:
	if is_instance_valid(active_hold_sfx):
		active_hold_sfx.queue_free()
	if is_instance_valid(active_hold_vfx):
		active_hold_vfx.queue_free()

func _handle_attack_input(cell: Vector2i) -> void:
	var attack = active_unit.equipped_attack
	
	# Check distance using your footpint function
	var dist = _get_footprint_distance(map_manager.world_to_cell(active_unit.global_position), active_unit.data.grid_size, cell)
	if dist > attack.attack_range:
		print("Out of range!")
		return

	# Add target
	multi_target_selection.append(cell)
	
	var progress_text = "%s (%d/%d)" % [attack.attack_name, multi_target_selection.size(), attack.max_targets]
	main_ui.skill_bar.set_button_text(current_attack_index, progress_text)
	
	if multi_target_selection.size() >= attack.max_targets:
		# CHECK COSTS RIGHT BEFORE EXECUTION
		if active_unit.stats.stamina < attack.stamina_cost or active_unit.stats.mana < attack.mana_cost:
			print("Not enough resources!")
			multi_target_selection.clear()
			return
			
		# SPEND
		active_unit.stats.stamina -= attack.stamina_cost
		active_unit.stats.mana -= attack.mana_cost
		active_unit.stats.health -= attack.health_cost # Added health cost!
		
		var targets_to_fire = multi_target_selection.duplicate()
		multi_target_selection.clear()
		main_ui.skill_bar.set_button_text(current_attack_index, attack.attack_name)
		_execute_multi_target_attack(targets_to_fire)

func _execute_multi_target_attack(target_cells: Array[Vector2i]) -> void:
	is_attack_in_progress = true
	var attack = active_unit.equipped_attack
	_stop_hold_effects()

	# --- 1. CASTING PHASE ---
	var active_vfx_nodes: Array[Node] = []

	# Visual on the Unit
	if attack.casting_vfx:
		var vfx = WORLD_VFX_SCENE.instantiate()
		world.add_child(vfx)
		vfx.global_position = active_unit.global_position
		vfx.setup(attack.casting_vfx)
		active_vfx_nodes.append(vfx)

	# Visual on the TARGETED CELLS (The new part!)
	if attack.target_cast_vfx:
		for cell in target_cells:
			var target_vfx = WORLD_VFX_SCENE.instantiate()
			world.add_child(target_vfx)
			target_vfx.global_position = map_manager.cell_to_world(cell)
			target_vfx.setup(attack.target_cast_vfx)
			active_vfx_nodes.append(target_vfx)

	# Wait for casting sound
	if attack.casting_sfx:
		var p = play_sfx(attack.casting_sfx, active_unit.global_position)
		if p: await p.finished

	# --- 2. CLEANUP CASTING LOOPS ---
	for node in active_vfx_nodes:
		if is_instance_valid(node):
			node.queue_free()

	# 2. TARGET LOOP
	for i in range(target_cells.size()):
		var target_cell = target_cells[i]
		var target_pos = map_manager.cell_to_world(target_cell)
		
		# PROJECTILE PHASE
		if attack.has_projectile:
			var proj_scene = load("uid://nlir0s34c32o")
			if proj_scene:
				var proj = proj_scene.instantiate()
				get_parent().add_child(proj)
				proj.launch(attack.projectile_vfx, active_unit.global_position, target_pos, attack.projectile_speed, attack.projectile_sfx)
				await proj.arrived 
		
		# IMPACT PHASE (Only once at the CENTER of the target_cell)
		if attack.impact_sfx:
			play_sfx(attack.impact_sfx, target_pos)
		
		if attack.impact_vfx:
			var vfx = WORLD_VFX_SCENE.instantiate()
			world.add_child(vfx)
			vfx.global_position = target_pos
			vfx.setup(attack.impact_vfx)
		
		
		# 1. HIT STOP (Freeze)
		if attack.screen_freeze_type != Globals.FreezeType.NONE:
			await _apply_hit_stop(attack.screen_freeze_type) 

		# 2. CAMERA ZOOM (Now separate!)
		if attack.screen_zoom_type != Globals.ZoomType.NONE:
			var cam = get_viewport().get_camera_2d()
			if cam:
				cam.apply_impact_zoom(attack.screen_zoom_type, target_pos)

		# 3. SCREEN FLASH
		if attack.use_screen_flash:
			_apply_screen_flash(Color(1, 1, 1, 0.5), 0.15)

		# 4. SCREEN SHAKE
		if attack.screen_shake_type != Globals.ShakeType.NONE:
			_apply_screen_shake(attack.screen_shake_type)
				
		# 3. AOE LOGIC (Apply hits to victims)
		var affected_tiles = _get_aoe_tiles(target_cell, attack.aoe_range, attack.aoe_shape)
		for cell in affected_tiles:
			var victim = _get_occupant_at_cell(cell)
			if victim:
				# SFX on the unit
				if attack.hit_sfx:
					play_sfx(attack.hit_sfx, victim.global_position)
				
				# NEW: Add hit_vfx if you have one in your Resource
				if attack.hit_vfx:
					var h_vfx = WORLD_VFX_SCENE.instantiate()
					world.add_child(h_vfx)
					h_vfx.global_position = victim.global_position
					h_vfx.setup(attack.hit_vfx)
					
				_apply_attack_damage(attack, active_unit, victim)
			# SURFACE LOGIC
			if attack.surface_to_create != Globals.SurfaceType.NONE:
				if attack.surface_sfx:
					play_sfx(attack.surface_sfx, map_manager.cell_to_world(cell))
				map_manager.apply_surface_to_cell(cell, attack.surface_to_create, attack.surface_duration, attack.surface_vfx)

	# 3. UNLOCK
	is_attack_in_progress = false # UNLOCK INPUT
	print("--- MULTI-ATTACK COMPLETE ---")
	_set_interaction_mode(InteractionMode.SELECT)
	main_ui.update_buttons(active_unit)

func _apply_attack_damage(attack: AttackResource, attacker: Unit, victim: Node2D) -> void:
	var data = attack.get_damage_data(attacker.stats, victim.stats)
	var damage = data[0]
	var result = data[1]
	var effect_multiplier = data[0] # 1.0, 0.5, or 0.0
	
	if attack.category == Globals.AttackCategory.SPELL:
		if result == attack.HitResult.MISS:
			_spawn_damage_number(0, victim.global_position, attack.damage_type, result, "RESISTED")
		else:
			_apply_spell_effect(attack, victim, effect_multiplier)
	else:
	
		# NEW: Spawn the number here (Even for a MISS, we can show "MISS")
		_spawn_damage_number(roundi(damage), victim.global_position, attack.damage_type, result)

		if result == attack.HitResult.MISS:
			_send_to_log("%s missed %s!" % [attacker.name, victim.name], Color.GRAY)
			return

		# Apply Health Change
		# --- FIXED: Apply damage to Units OR Objects ---
		if victim is Unit:
			victim.stats.take_damage(damage)
			victim.play_hit_flash()
			if attack.buff_to_apply:
				victim.stats.add_buff(attack.buff_to_apply)
				
		elif victim is WorldObject:
			victim.stats.take_damage(damage)

	# Combat Log
	var type_color = Globals.DAMAGE_COLORS.get(attack.damage_type, Color.WHITE)
	var prefix = ""
	match result:
		attack.HitResult.GRAZE: prefix = "GRAZE! "
		attack.HitResult.CRIT: prefix = "CRITICAL HIT! "

	var main_msg = "%s%s used %s! %s takes" % [prefix, attacker.name, attack.attack_name, victim.name]
	var log_node = get_tree().get_first_node_in_group("CombatLog")
	if log_node:
		log_node.add_combat_entry(main_msg, str(ceil(damage)), type_color)

	# Spawn Hit VFX
	if attack.hit_vfx:
		var vfx = WORLD_VFX_SCENE.instantiate()
		world.add_child(vfx)
		vfx.global_position = victim.global_position
		vfx.setup(attack.hit_vfx)

	# Death Check
	if victim is Unit and victim.stats.health <= 0:
		_handle_unit_death(victim)
	elif victim is WorldObject and victim.stats.health <= 0:
		_handle_object_death(victim)

# --- SELECTION & HIGHLIGHTS ---

func _handle_selection(cell: Vector2i) -> void:
	# Use the more generic occupant getter since we have objects now
	var occupant = _get_occupant_at_cell(cell)
	
	if occupant is Unit:
		_set_selected_unit(occupant)
		if occupant.data.is_player_controlled:
			_set_active_unit(occupant)
		else:
			_set_active_unit(null) # Can't control enemies
	elif occupant is WorldObject:
		# You might want a _set_selected_object later for a destructible info panel!
		_set_selected_unit(null)
		_set_active_unit(null)
	else:
		_set_active_unit(null)
		_set_selected_unit(null)

func _set_selected_unit(unit: Unit) -> void:
	# Clean up previous selection visual if your Unit script has a highlight
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
		
	selected_unit = unit
	
	if unit_info_panel:
		unit_info_panel.display_unit(unit)
	
	if selected_unit:
		selected_unit.set_selected(true)

func _set_active_unit(unit: Unit) -> void:
	active_unit = unit
	
	# Only show command buttons for player units
	main_ui.update_buttons(active_unit)
	
	# Update Highlights (Move/Attack range)
	if highlights:
		highlights.active_unit = unit
		highlights.cached_move_range.clear() 
		highlights.cached_path.clear()       
		_update_highlights()

func _update_highlights() -> void:
	if not highlights: return
	highlights.active_unit = active_unit
	highlights.display_mode = "attack" if current_mode == InteractionMode.ATTACK else "move"
	highlights.queue_redraw()

func _set_interaction_mode(new_mode: InteractionMode) -> void:
	current_mode = new_mode
	_update_highlights()

# --- UTILITY ---

func _on_unit_registered(unit: Unit, cell: Vector2i) -> void:
	register_unit_position(unit, cell)
	unit.movement_finished.connect(_on_unit_movement_finished)

func _on_object_registered(obj: WorldObject, cell: Vector2i) -> void:
	# Just like register_unit_position, but for objects!
	register_object_position(obj, cell)

func _send_to_log(msg: String, color: Color = Color.WHITE) -> void:
	var log_node = get_tree().get_first_node_in_group("CombatLog")
	if log_node:
		log_node.add_message(msg, color)

# Change '-> Unit' to '-> Node2D' or remove the type hint entirely
func _get_occupant_at_cell(cell: Vector2i) -> Node2D:
	if occupancy_grid.has(cell):
		return occupancy_grid[cell]
	return null

func _handle_unit_death(unit: Unit) -> void:
	if not is_instance_valid(unit): return

	_send_to_log("%s has been slain!" % unit.name, Color.ORANGE_RED)
	
	# 1. Clear the tiles
	unregister_unit(unit)
	
	# 2. Safety: Clear UI references
	if active_unit == unit:
		_set_active_unit(null)
	if selected_unit == unit:
		_set_selected_unit(null)
	
	# 3. Final cleanup
	unit.queue_free()

func _handle_object_death(obj: WorldObject) -> void:
	_send_to_log("%s was destroyed!" % obj.name, Color.GRAY)
	unregister_object(obj)
	obj.queue_free()

func _setup_camera(map_resource: MapData) -> void:
	var map_width_px = map_resource.size.x * map_manager.cell_size.x
	var map_height_px = map_resource.size.y * map_manager.cell_size.y
	var cam = get_viewport().get_camera_2d()
	if cam and cam.has_method("set"):
		cam.limit_min = Vector2.ZERO
		cam.limit_max = Vector2(map_width_px, map_height_px)

# --- MOVEMENT ---

func _spawn_damage_number(amount: int, position: Vector2, damage_type: Globals.DamageType, result: AttackResource.HitResult) -> void:
	var label = Label.new()
	label.scale = Vector2(2.0, 2.0)
	
	# Handle MISS/GRAZE/CRIT text
	if result == AttackResource.HitResult.MISS:
		label.text = "MISS"
	else:
		label.text = str(amount)
	
	# Setup styling
	
	# 2. Outline (This makes it readable on any background)
	label.add_theme_constant_override("outline_size", 4) # Thickness of the outline
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	# 3. Shadow (Adds a 3D depth effect)
	#label.add_theme_constant_override("shadow_offset_x", 2)
	#label.add_theme_constant_override("shadow_offset_y", 2)
	#label.add_theme_color_override("font_shadow_color", Color.BLACK)
	#label.add_theme_constant_override("outline_size", 6)
	
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100 
	label.modulate = Globals.DAMAGE_COLORS.get(damage_type, Color.WHITE)
	
	# If it's a CRIT, make it bigger!
	if result == AttackResource.HitResult.CRIT:
		label.scale = Vector2(3.0, 3.0)
		label.add_theme_constant_override("outline_size", 4)
	
	label.global_position = position + Vector2(-10, -20) # Start closer to unit head
	world.add_child(label)
	
	var tween = create_tween().set_parallel(true)
	
	# Slow, small float: move up only 20 pixels (less than 1 tile) over 1.2 seconds
	tween.tween_property(label, "position:y", label.position.y - 25, 1.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	# Fade out starts later and lasts longer
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.8)
	
	tween.finished.connect(label.queue_free)

func _handle_movement(target_cell: Vector2i) -> void:
	if not active_unit or active_unit.is_moving:
		return
		
	var start_cell = map_manager.world_to_cell(active_unit.global_position)
	
	# NEW: Instead of just clearing a dictionary, we tell the map the unit "lifted"
	# its entire footprint off the grid.
	unregister_unit(active_unit) 
	
	var result = map_manager.get_path_with_stamina(
		start_cell, 
		target_cell, 
		active_unit.stats.stamina, 
		active_unit.data.grid_size,
		active_unit # Pass self to ignore own "ghost" during calculation
	)
	
	var grid_path = result[0]
	
	if grid_path.is_empty(): 
		register_unit_position(active_unit, start_cell)
		return
		
	var world_path := PackedVector2Array()
	for c in grid_path:
		world_path.append(map_manager.cell_to_world(c))
		
	active_unit.follow_path(world_path, result[1])

func _on_unit_movement_finished(unit: Unit, final_cell: Vector2i) -> void:
	register_unit_position(unit, final_cell)
	print(unit.name," ", final_cell)
	if highlights:
		highlights.cached_move_range.clear()
		highlights.cached_path.clear() # <--- Add this to hide the ghost
		highlights.queue_redraw()

func is_cell_vacant(cell: Vector2i, ignore_unit: Unit = null) -> bool:
	if not occupancy_grid.has(cell):
		return true
	
	# If there is a unit there, but it's the one we told the game to ignore...
	if occupancy_grid[cell] == ignore_unit:
		return true
		
	return false

func register_unit_position(unit: Unit, start_cell: Vector2i) -> void:
	unregister_unit(unit) # Always clear first
	
	var size = unit.data.grid_size
	for x in range(size.x):
		for y in range(size.y):
			var cell = start_cell + Vector2i(x, y)
			
			# 1. Update Game's internal tracking
			occupancy_grid[cell] = unit
			
			# 2. Update MapManager's CellData for Divinity-style interaction
			if map_manager.grid_data.has(cell):
				var cell_info = map_manager.grid_data[cell]
				cell_info.is_occupied = true
				cell_info.occupant = unit

func unregister_unit(unit: Unit) -> void:
	if not unit: return
	
	var keys_to_remove = []
	for cell in occupancy_grid.keys():
		if occupancy_grid[cell] == unit:
			keys_to_remove.append(cell)
			
			# NEW: Clear the MapManager data too
			if map_manager.grid_data.has(cell):
				map_manager.grid_data[cell].is_occupied = false
				map_manager.grid_data[cell].occupant = null
	
	for key in keys_to_remove:
		occupancy_grid.erase(key)

func register_object_position(obj: WorldObject, cell: Vector2i) -> void:
	occupancy_grid[cell] = obj
	
	# Also tell the MapManager so AStar knows it's blocked
	if map_manager.grid_data.has(cell):
		var cell_data = map_manager.grid_data[cell]
		cell_data.is_occupied = true
		cell_data.occupant = obj
	
	# Update AStar weights so pathfinding avoids the object
	map_manager.update_astar_weights()

func unregister_object(obj: WorldObject) -> void:
	var keys_to_remove = []
	for cell in occupancy_grid.keys():
		if occupancy_grid[cell] == obj:
			keys_to_remove.append(cell)
			if map_manager.grid_data.has(cell):
				map_manager.grid_data[cell].is_occupied = false
				map_manager.grid_data[cell].occupant = null
	for key in keys_to_remove:
		occupancy_grid.erase(key)

func _get_footprint_distance(origin: Vector2i, size: Vector2i, target: Vector2i) -> int:
	var shortest_dist = 9999
	for x in range(size.x):
		for y in range(size.y):
			var occupied_tile = origin + Vector2i(x, y)
			# Use max() here so the AI understands diagonal attacks!
			var d = max(abs(occupied_tile.x - target.x), abs(occupied_tile.y - target.y))
			if d < shortest_dist:
				shortest_dist = d
	return shortest_dist

func _get_aoe_tiles(center: Vector2i, aoe_range: int, shape: Globals.AreaShape) -> Array[Vector2i]:
	var affected_tiles: Array[Vector2i] = []
	
	# Range 0 or 1 is always just the target tile
	if aoe_range <= 0:
		return [center]

	# To get Range 1 = 2x2, we need the loop to go from 0 to 1 (2 steps)
	# To get Range 2 = 3x3, we need the loop to go from -1 to 1 (3 steps)
	var start_offset: int
	var end_offset: int

	if aoe_range % 2 == 0: # EVEN (2, 4, 6...)
		start_offset = -(aoe_range / 2) + 1
		end_offset = (aoe_range / 2)
	else: # ODD (1, 3, 5...)
		start_offset = -(aoe_range / 2)
		end_offset = (aoe_range / 2)

	for x in range(start_offset, end_offset + 1):
		for y in range(start_offset, end_offset + 1):
			var cell = center + Vector2i(x, y)
			
			if shape == Globals.AreaShape.SQUARE:
				affected_tiles.append(cell)
			elif shape == Globals.AreaShape.DIAMOND:
				# Manhattan distance check for diamond
				if abs(x) + abs(y) <= (aoe_range / 2):
					affected_tiles.append(cell)
						
	return affected_tiles

# --- TURNS ---

func _on_end_turn_button_pressed() -> void:
	if Globals.current_state == Globals.TurnState.PLAYER_TURN:
		_end_player_turn()

func _end_player_turn() -> void:
	print("--- TURN ENDED ---")
	Globals.current_state = Globals.TurnState.ENEMY_TURN
	_set_active_unit(null)
	_run_enemy_phase() 

func _run_enemy_phase() -> void:
	print("--- ENEMY TURN ---")
	_send_to_log("--- ENEMY TURN ---", Color.WHITE)
	enemy_team.replenish_all_stamina()
	# Get all enemies and put them in a queue
	enemy_queue = enemy_team.get_children()
	_process_next_enemy()

func _process_next_enemy() -> void:
	if enemy_queue.is_empty():
		_start_player_turn()
		return

	var current_enemy = enemy_queue.pop_front()
	
	# STRICT CHECK: Must be a Unit AND have AI
	if current_enemy is Unit and current_enemy.data and current_enemy.data.ai_behavior:
		print("Processing AI for: ", current_enemy.name)
		
		var ai = current_enemy.data.ai_behavior
		if not ai.decision_completed.is_connected(_process_next_enemy):
			ai.decision_completed.connect(_process_next_enemy, CONNECT_ONE_SHOT)
		
		ai.make_decision(current_enemy, self, map_manager)
	else:
		# This is where @Node2D@3 ends up. 
		# We just print a skip message and move to the next one.
		print("Skipping non-unit node in EnemyGroup: ", current_enemy.name)
		_process_next_enemy()

func _start_player_turn() -> void:
	print("--- PLAYER TURN ---")
	_send_to_log("--- PLAYER TURN ---", Color.WHITE)
	Globals.current_state = Globals.TurnState.PLAYER_TURN
	map_manager.tick_surfaces() # Surfaces decay at the start of a new round
	player_team.replenish_all_stamina()
	# Optional: Select the first player unit automatically
	select_player_unit()

# --- END CONDITIONS ---

func _trigger_victory() -> void:
	if Globals.current_state == Globals.TurnState.VICTORY: return
	
	print("VICTORY!")
	_send_to_log("--- VICTORY! ---", Color.GOLD)
	Globals.current_state = Globals.TurnState.VICTORY

func _trigger_game_over() -> void:
	if Globals.current_state == Globals.TurnState.GAME_OVER: return
	
	print("GAME OVER")
	_send_to_log("--- DEFEAT... ---", Color.RED)
	Globals.current_state = Globals.TurnState.GAME_OVER

# --- EFFECTS VFX SFX ---

func _apply_screen_shake(type: Globals.ShakeType) -> void:
	if not Globals.screen_effects_enabled or type == Globals.ShakeType.NONE:
		return
		
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	var intensity: float = 0.0
	var duration: float = 0.0
	var amount: float = 0.0
	var some: float = 0.0
	
	# Setting different values for each type
	match type:
		Globals.ShakeType.SMALL:
			intensity = 4
			duration = 0.1
			amount = 3
			some = 3
		Globals.ShakeType.MID:
			intensity = 8.0
			duration = 0.2
			amount = 0.15
			some = 6
		Globals.ShakeType.BIG:
			intensity = 8
			duration = 0.4
			amount = 12
			some = 12
	
	var original_offset = camera.offset
	var tween = create_tween()
	
	for i in range(amount):
		var shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity
		tween.tween_property(camera, "offset", shake_offset, duration / some)
	
	tween.tween_property(camera, "offset", original_offset, 0.05)


func _apply_hit_stop(type: Globals.FreezeType) -> void:
	# FIX: Changed 'FreezeTypeType' to 'FreezeType'
	if not Globals.screen_effects_enabled or type == Globals.FreezeType.NONE:
		return
		
	var duration: float = 0.0
	
	match type:
		Globals.FreezeType.SMALL:
			duration = 0.05
		Globals.FreezeType.MID:
			duration = 0.1
		Globals.FreezeType.BIG:
			duration = 0.2 # Dramatic pause for huge hits
	
	Engine.time_scale = 0.05
	# The last 'true' here is vital—it tells the timer to ignore the slow time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func _apply_screen_flash(color: Color, duration: float) -> void:
	if not Globals.screen_effects_enabled:
		return

	# 1. Create the nodes on the fly
	var canvas = CanvasLayer.new()
	var flash = ColorRect.new()
	
	# 2. Setup the flash appearance
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE # Important: don't block clicks!
	
	# 3. Add to the scene
	add_child(canvas)
	canvas.add_child(flash)
	
	# 4. Animate the fade out
	var tween = create_tween()
	# Animates the 'alpha' (transparency) from current to 0
	tween.tween_property(flash, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE)
	
	# 5. Cleanup
	await tween.finished
	canvas.queue_free()

func play_hit_effect(vfx_resource: VisualEffectData, pos: Vector2):
	var vfx = preload("uid://pc6usvw46jfj").instantiate()
	world.add_child(vfx)
	vfx.global_position = pos
	vfx.setup(vfx_resource) # It will delete itself automatically

func play_sfx(stream: AudioStream, position: Vector2 = Vector2.ZERO) -> AudioStreamPlayer2D:
	if not stream: return null
	
	var sfx_player = AudioStreamPlayer2D.new()
	sfx_player.stream = stream
	sfx_player.global_position = position
	sfx_player.pitch_scale = randf_range(0.9, 1.1)
	
	add_child(sfx_player)
	sfx_player.play()
	
	sfx_player.finished.connect(sfx_player.queue_free)
	
	# Return the player so we can await it!
	return sfx_player

# --- INPUT OVERRIDE (Fixing Space Bar) ---

func _input(event):
	if event.is_action_pressed("ui_accept"): 
		var mouse_cell = selector.current_cell
		if fire_vfx_resource:
			print("Space pressed: Spawning test fire at ", mouse_cell)
			map_manager.apply_surface_to_cell(mouse_cell, Globals.SurfaceType.FIRE, 3, fire_vfx_resource)
			# Consumes the input so it doesn't click buttons or attack
			get_viewport().set_input_as_handled()
