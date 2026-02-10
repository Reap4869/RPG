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

# Movement state
var path: PackedVector2Array = []
var path_index := 0
var is_moving := false
var selected := false: 
	set(value):
		selected = value


# --- Initialization ---

func _ready() -> void:
	add_to_group("Units")
	
	# Faster, cleaner way to find the Manager
	map_manager = get_tree().get_first_node_in_group("MapManager")
	
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

	# 2. Setup Visuals (Basic)
	if data.sprite_sheet:
		sprite.texture = data.sprite_sheet
		sprite.region_enabled = true
		sprite.region_rect = data.world_region 
		sprite.scale = Vector2(data.visual_scale, data.visual_scale)
	
	# . Calculate Final Offset (Combine "Tall Hero" and "Large Unit" logic)
	var final_offset = data.sprite_offset # Start with the .tres value
	
	# Add shift if the unit occupies more than 1x1 cells
	if data.grid_size.x > 1 or data.grid_size.y > 1:
		# For 32px tiles: 2x2 moves +16px, 3x3 moves +32px
		var shift = (Vector2(data.grid_size) - Vector2.ONE) * 16.0
		final_offset += shift

	# Apply the combined offset
	sprite.offset = final_offset
	collision_shape.position = final_offset * data.visual_scale
	
	#  Handle Collision Size & Skills
	_update_collision_to_match_region()
	
	# 3. Setup Attacks
	if data.attacks.size() > 0:
		# Set the starting attack based on the index in UnitData
		var index = clampi(data.default_attack_index, 0, data.attacks.size() - 1)
		equipped_attack = data.attacks[index]
	elif data.default_attack: # Fallback for your old system
		equipped_attack = data.default_attack
	
	stats.leveled_up.connect(_on_level_up)
# --- Movement Logic ---

func _process(delta: float) -> void:
	if not is_moving or path.is_empty():
		return
	
	var target_pos = path[path_index]
	global_position = global_position.move_toward(target_pos, 200.0 * delta)
	
	if global_position.distance_to(target_pos) < 0.1:
		# --- NEW: Trigger surface effect for the cell we just reached ---
		var reached_cell = map_manager.world_to_cell(target_pos)
		# --- TRIGGER SOUNDS AND EFFECTS ---
		cell_entered.emit(reached_cell)
		
		path_index += 1
		
		# Check if we finished the whole path
		if path_index >= path.size():
			is_moving = false
			# Snap to exact pixel center of the tile
			global_position = target_pos 
			
			var final_cell = map_manager.world_to_cell(global_position)
			movement_finished.emit(self, final_cell)
			path.clear()
		
func follow_path(new_path: PackedVector2Array, cost: float) -> void:
	if new_path.is_empty():
		return
	
	path = new_path
	path_index = 0
	is_moving = true
	
	# Subtract the stamina cost immediately when movement starts
	if stats:
		stats.stamina -= cost

# --- Helper Functions ---
func _on_level_up(_new_level: int):
	# Create a visual effect
	#var vfx = load("res://vfx/level_up_anim.tscn").instantiate()
	#add_child(vfx)
	# Play a sound
	#game.play_sfx(level_up_sfx, global_position)
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

func replenish_stamina() -> void:
	if stats:
		stats.stamina = stats.current_max_stamina

# Call this BEFORE starting a move
func leave_current_cells() -> void:
	var current_cell = map_manager.world_to_cell(global_position)
	_set_occupancy(current_cell, false)

# Call this AFTER finishing a move
func occupy_new_cells() -> void:
	var current_cell = map_manager.world_to_cell(global_position)
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
