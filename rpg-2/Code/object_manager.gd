extends Node2D

signal object_spawned(obj: WorldObject, cell: Vector2i)

@export var object_base_scene: PackedScene # The WorldObject.tscn
@export var stats: ObjectStats # Assign your new resource here!
var spawn_counts: Dictionary = {}

func _ready():
	y_sort_enabled = true # Ensure all units depth-sort against each other
	if stats:
		# Connect the signal you made to the manager's death handler
		stats.health_depleted.connect(_on_death)
		
func take_damage(amount: float):
	if stats:
		stats.take_damage(amount)

func _on_death():
	# Find the game node and tell it to clean up the grid
	var game = get_tree().get_first_node_in_group("Game")
	if game:
		game._handle_object_death(self)

func setup_objects(data: MapData) -> void:
	clear_objects()
	
	# 1. From Dictionary (MapData)
	for cell in data.object_spawns:
		# Use the manager's local 'object_base_scene' variable
		_spawn_from_template(object_base_scene, data.object_spawns[cell], cell)
	
	# 2. From Markers (Visual Editor)
	var markers = get_tree().get_nodes_in_group("ObjectMarkers")
	var map_manager = get_tree().get_first_node_in_group("MapManager")
	
	for marker in markers:
		if marker is ObjectMarker and marker.object_data != null:
			var cell = map_manager.world_to_cell(marker.global_position)
			# Use the manager's local 'object_base_scene' variable
			_spawn_from_template(object_base_scene, marker.object_data, cell)
			marker.queue_free()

func _spawn_from_template(scene: PackedScene, template: ObjectData, cell: Vector2i) -> void:
	var new_obj = spawn_object(scene, template, cell)
	object_spawned.emit(new_obj, cell)

func spawn_object(object_scene: PackedScene, template: ObjectData, cell: Vector2i) -> WorldObject:
	var new_obj = object_scene.instantiate() as WorldObject
	new_obj.data = template
	
	var base_name = template.object_name
	spawn_counts[base_name] = spawn_counts.get(base_name, 0) + 1
	new_obj.name = base_name + (str(spawn_counts[base_name]) if spawn_counts[base_name] > 1 else "")
	
	add_child(new_obj)
	
	# FIX: Use cell_to_floor (the unit helper) so origin is at the tile's bottom-center
	var map = get_tree().get_first_node_in_group("MapManager")
	new_obj.global_position = map.cell_to_floor(cell) 
	
	return new_obj

func clear_objects() -> void:
	for obj in get_children():
		obj.queue_free()
	spawn_counts.clear()
