extends Node2D
class_name Unit

signal cell_entered(cell: Vector2i)
signal movement_finished(unit: Unit, final_cell: Vector2i)

@export var data: UnitData

@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D

var map_manager: MapManager # No @onready needed here if we set it in _ready
var stats: Stats
var equipped_attack: AttackResource
var game_ref: Node = null
var highlights_ref: Node2D = null

# Movement state
var path: PackedVector2Array = []
var path_index := 0
var is_moving: bool = false
var selected: bool = false


# --- Initialization ---

func _ready() -> void:
	add_to_group("Units")
	
	# Faster, cleaner way to find the Manager
	map_manager = get_tree().get_first_node_in_group("MapManager")
	game_ref = get_tree().get_first_node_in_group("Game")
	if not game_ref:
			game_ref = get_tree().root.find_child("Game", true, false)
	highlights_ref = get_tree().get_first_node_in_group("CellHighlights")
	
	# Safety check in case MapManager isn't in the tree yet
	if not map_manager:
		print("Warning: Unit ", name, " couldn't find MapManager!")

	if data:
		_setup_from_data()
		
	# Duplicate AI so different units of the same type don't "share" a brain
	if data and data.ai_behavior:
		data.ai_behavior = data.ai_behavior.duplicate()

func _setup_from_data() -> void:
	if not data: return
	
	# 1. Setup Stats
	if data.base_stats:
		stats = data.base_stats.duplicate()
		stats.setup_stats()

	# 2. Setup Visuals
	if data.sprite_sheet:
		sprite.texture = data.sprite_sheet
		sprite.region_enabled = true
		sprite.region_rect = data.world_region 
		sprite.scale = Vector2(data.visual_scale, data.visual_scale)
	
	# AUTOMATION: Calculate offset based on world_region size
	var w = data.world_region.size.x
	var h = data.world_region.size.y
	
	# This puts the pivot at the bottom-center of the sprite
	var auto_offset = Vector2(-w / 2.0, -h)
	
	# Apply logic for 2x2 or 3x3 units
	if data.grid_size.x > 1 or data.grid_size.y > 1:
		var shift = (Vector2(data.grid_size) - Vector2.ONE) * 16.0
		auto_offset += shift

	sprite.offset = auto_offset
	
	# Move collision to the middle of the sprite's calculated height
	collision_shape.position = Vector2(0, (auto_offset.y / 2) * data.visual_scale)
	
	_update_collision_to_match_region()
	
	# 3. Setup Attacks
	if data.attacks.size() > 0:
		# Set the starting attack based on the index in UnitData
		var index = clampi(data.default_attack_index, 0, data.attacks.size() - 1)
		equipped_attack = data.attacks[index]
	elif data.default_attack: # Fallback for your old system
		equipped_attack = data.default_attack
	
	stats.leveled_up.connect(_on_level_up)

# HELPER: Use this instead of map_manager.world_to_cell(unit.global_position)
func get_cell() -> Vector2i:
	# We subtract a few pixels (8) from the Y position before calculating.
	# This ensures that even if the feet are on the bottom line, 
	# Godot picks the correct tile.
	return map_manager.world_to_cell(global_position - Vector2(0, 8))

# HELPER: Use this to teleport units safely
func snap_to_cell(cell: Vector2i) -> void:
	if not map_manager: return
	# Directly set to the floor position
	global_position = map_manager.cell_to_unit_pos(cell)

# --- Movement Logic ---

func _process(delta: float) -> void:
	# 1. Handle Combat/Path Movement (Your existing code)
	if is_moving and not path.is_empty():
		_process_movement(delta) # Move your existing movement logic here
	
	# 2. Handle Exploration Detection
	if Globals.current_mode == Globals.GameMode.EXPLORATION:
		# If we are an AI unit moving in exploration, tell highlights to redraw the cone
		if highlights_ref:
			highlights_ref.queue_redraw()
		
		if data and data.ai_behavior and not data.is_player_controlled:
			if game_ref:
				data.ai_behavior.check_detection(self, game_ref)


# Helper to keep _process clean
func _process_movement(delta: float):
	var target_pos = path[path_index]
	# Update facing direction for AI vision
	var move_vec = (target_pos - global_position).normalized()
	if move_vec.length() > 0.1 and data and data.ai_behavior:
		data.ai_behavior.facing_direction = move_vec
		
	global_position = global_position.move_toward(target_pos, 200.0 * delta)
	
	if global_position.distance_to(target_pos) < 0.1:
		# --- NEW: Trigger surface effect for the cell we just reached ---
		var reached_cell = get_cell()
		# --- TRIGGER SOUNDS AND EFFECTS ---
		cell_entered.emit(reached_cell)
		
		path_index += 1
		
		# Check if we finished the whole path
		if path_index >= path.size():
			is_moving = false
			# IMPORTANT: Use snap_to_cell here to ensure the final 
			# position is the FLOOR, not the CENTER.
			snap_to_cell(reached_cell)
			movement_finished.emit(self, reached_cell)
			path.clear()


func follow_path(new_path: PackedVector2Array, cost: float) -> void:
	if new_path.is_empty():
		return
	
	path = new_path
	path_index = 0
	is_moving = true
	
	# Determine direction for AI facing
	var move_dir = (new_path[0] - global_position).normalized()
	if data and data.ai_behavior:
		data.ai_behavior.facing_direction = move_dir
	
		# If exploration, we just move without deducting
	if Globals.current_mode == Globals.GameMode.COMBAT:
		if stats:
			stats.stamina -= cost
	# Subtract the stamina cost immediately when movement starts
	
# --- Helper Functions ---
func _on_level_up(_new_level: int):
	# Create a visual effect
	#var vfx = load("res://vfx/level_up_anim.tscn").instantiate()
	#add_child(vfx)
	# Play a sound
	#game.play_sfx(level_up_sfx, global_position)
	print("You just Level up!")
	return

func switch_attack(index: int) -> void:
	if index >= 0 and index < data.attacks.size():
		equipped_attack = data.attacks[index]

func _set_occupancy(origin: Vector2i, occupied: bool) -> void:
	for x in range(data.grid_size.x):
		for y in range(data.grid_size.y):
			var cell = origin + Vector2i(x, y)
			if map_manager.grid_data.has(cell):
				var cell_data = map_manager.grid_data[cell]
				cell_data.is_occupied = occupied
				cell_data.occupant = self if occupied else null

func _update_collision_to_match_region() -> void:
	if not data: return
	
	# 1. Create a unique copy of the shape so we don't resize every unit
	collision_shape.shape = collision_shape.shape.duplicate()
	
	# 2. Set the size based on the region and visual scale
	var final_size = data.world_region.size * data.visual_scale
	
	if collision_shape.shape is RectangleShape2D:
		collision_shape.shape.size = final_size
	elif collision_shape.shape is CircleShape2D:
		collision_shape.shape.radius = max(final_size.x, final_size.y) / 2.0
	
	# 3. Align the shape with the sprite's visual offset
	collision_shape.position = data.sprite_offset * data.visual_scale
	
	# 4. Reset scale to ensure 1:1 pixel mapping
	collision_shape.scale = Vector2.ONE

func set_selected(value: bool) -> void:
	selected = value
	# Update visuals for selection (example; adjust to your node names)
	if selected:
		# show selection visuals, e.g. highlight sprite or outline
		if sprite:
			sprite.modulate = Color(1,1,1,1) # example
	else:
		# hide selection visuals / reset
		if sprite:
			sprite.modulate = Color(1,1,1,1) # reset as appropriate

func replenish_stamina() -> void:
	if stats:
		stats.stamina = stats.current_max_stamina

# Call this BEFORE starting a move
func leave_current_cells() -> void:
	var current_cell = get_cell()
	_set_occupancy(current_cell, false)

# Call this AFTER finishing a move
func occupy_new_cells(_unit: Unit = null, _cell: Vector2i = Vector2i.ZERO) -> void:
	var current_cell = get_cell()
	_set_occupancy(current_cell, true)

func play_hit_flash() -> void:
	var tween = create_tween()
	# Turn the sprite red
	tween.tween_property(sprite, "modulate", Color.RED, 0.3)
	# Turn it back to normal
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)

func take_damage(amount: int):
	stats.health -= amount # If this line is missing, the health bar never moves!
	play_hit_flash()
	# NEW: If we are attacked in exploration, force start combat!
	if Globals.current_mode == Globals.GameMode.EXPLORATION:
		var game = get_tree().get_first_node_in_group("Game")
		if game:
			game.start_combat(self)
			#print("Combat started! You hit %s", stats.name)
