extends Node2D
class_name WorldObject

@export var data: ObjectData

@onready var sprite: Sprite2D = $Sprite2D
var map_manager: MapManager
var current_health: int
var stats: ObjectStats

func _ready() -> void:
	add_to_group("Objects")
	map_manager = get_tree().get_first_node_in_group("MapManager")
	
	if data:
		_setup_from_data()

func _setup_from_data() -> void:
	if data.stats:
		# We DUPLICATE the stats so each barrel has its own health, 
		# otherwise hitting one barrel hurts ALL barrels of that type!
		stats = data.stats.duplicate() 
		
		# Connect the signal from the Resource to a function in this script
		if not stats.health_depleted.is_connected(_on_health_depleted):
			stats.health_depleted.connect(_on_health_depleted)
	
	sprite.texture = data.sprite_texture
	sprite.region_enabled = true
	sprite.region_rect = data.world_region
	sprite.scale = Vector2(data.visual_scale, data.visual_scale)
	sprite.offset = data.sprite_offset


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
	stats.health -= amount # If this line is missing, the health bar never moves!
	play_hit_flash()

func destroy_object() -> void:
	# Tell the map we are no longer here
	var cell = map_manager.world_to_cell(global_position)
	var cell_data = map_manager.grid_data.get(cell)
	if cell_data:
		cell_data.is_occupied = false
		cell_data.occupant = null
	
	# Play a sound or effect here if you want
	queue_free()
