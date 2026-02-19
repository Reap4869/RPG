extends Node2D
class_name WorldObject

signal cell_entered(cell: Vector2i)
signal movement_finished(object: WorldObject, final_cell: Vector2i)

@export var data: ObjectData

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

var map_manager: MapManager
var stats: ObjectStats
var game_ref: Node = null
var highlights_ref: Node2D = null

var selected: bool = false

func _ready() -> void:
	add_to_group("Objects")
	map_manager = get_tree().get_first_node_in_group("MapManager")
	if data:
		_setup_from_data()

func _setup_from_data() -> void:
	if data.stats:
		# 1. Stats Setup (Duplicated to avoid shared HP)
		# otherwise hitting one barrel hurts ALL barrels of that type!
		stats = data.stats.duplicate() 
		# Connect the signal from the Resource to a function in this script
		if not stats.health_depleted.is_connected(_on_health_depleted):
			stats.health_depleted.connect(_on_health_depleted)
	
	# 2. Visuals Setup
	sprite.texture = data.sprite_texture
	sprite.region_enabled = true
	sprite.region_rect = data.world_region
	sprite.scale = Vector2(data.visual_scale, data.visual_scale)
	
	# 3. Pivot/Offset Logic (Standardized to Bottom-Center like Units)
	var w = data.world_region.size.x
	var h = data.world_region.size.y
	var auto_offset = Vector2(-w / 2.0, -h)
	
	# Handle multi-tile objects (2x2 barrels, etc)
	if data.grid_size.x > 1 or data.grid_size.y > 1:
		var shift = (Vector2(data.grid_size) - Vector2.ONE) * 16.0
		auto_offset += shift
		
	sprite.offset = auto_offset
	
	# 4. Collision Alignment
	if collision_shape:
		collision_shape.position = Vector2(0, (auto_offset.y / 2.0) * data.visual_scale)

# --- Helpers (Now matching Unit.gd interface) ---

func get_cell() -> Vector2i:
	return map_manager.world_to_cell(global_position - Vector2(0, 8))

func _on_health_depleted() -> void:
	# This function runs when the resource signal fires
	var game = get_tree().get_first_node_in_group("Game")
	if game:
		game._handle_object_death(self)

func play_hit_flash() -> void:
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.RED, 0.1)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

func take_damage(amount: int):
	if stats:
		stats.health -= amount
		play_hit_flash()

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

# Call this BEFORE starting a move
func leave_current_cells() -> void:
	var current_cell = get_cell()
	_set_occupancy(current_cell, false)

# Call this AFTER finishing a move
func occupy_new_cells(_object: WorldObject = null, _cell: Vector2i = Vector2i.ZERO) -> void:
	var current_cell = get_cell()
	_set_occupancy(current_cell, true)
