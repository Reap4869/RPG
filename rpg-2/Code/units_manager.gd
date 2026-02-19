extends Node2D

# Signal to tell Game.gd a unit is ready
signal unit_spawned(unit: Unit, cell: Vector2i)

@onready var player_group = $PlayerGroup
@onready var enemy_group = $EnemyGroup
@onready var neutral_group = $NeutralGroup
@onready var map_manager = $"../MapManager"
var spawn_counts: Dictionary = {}

func _ready() -> void:
	y_sort_enabled = true # Ensure all units depth-sort against each other
	player_group.y_sort_enabled = true
	enemy_group.y_sort_enabled = true
	neutral_group.y_sort_enabled = true

func setup_units(data: MapData) -> void:
	clear_battlefield()
	
	# 1. Spawn from Dictionary (for fixed/story spawns)
	for cell in data.player_spawns:
		_spawn_from_template(data.unit_scene, data.player_spawns[cell], cell, true)
	for cell in data.enemy_spawns:
		_spawn_from_template(data.unit_scene, data.enemy_spawns[cell], cell, false)
	for cell in data.neutral_spawns:
		_spawn_from_template(data.unit_scene, data.neutral_spawns[cell], cell, false)

	# 2. Spawn from Visual Markers
	var markers = get_tree().get_nodes_in_group("SpawnMarkers")
	for marker in markers:
		if marker is SpawnMarker and marker.unit_data != null:
			var cell = map_manager.world_to_cell(marker.global_position)
			_spawn_from_template(data.unit_scene, marker.unit_data, cell, marker.is_player)
			
			# IMPORTANT: Remove the marker so it doesn't stay in the game world
			marker.queue_free()

func clear_battlefield() -> void:
	# Include neutral_group here so NPCs are wiped on map change!
	for team in [enemy_group, neutral_group]:
		for unit in team.get_children():
			unit.queue_free()
	spawn_counts.clear()

func spawn_unit(unit_scene: PackedScene, template: UnitData, cell: Vector2i, is_player: bool) -> Unit:
	var new_unit = unit_scene.instantiate() as Unit
	new_unit.data = template
	
	# Determine role from template
	var role = template.role
	
	var base_name = template.base_stats.character_name
	if not spawn_counts.has(base_name):
		spawn_counts[base_name] = 1
	else:
		spawn_counts[base_name] += 1
	
	var current_count = spawn_counts[base_name]
	new_unit.name = base_name if current_count == 1 else base_name + " " + str(current_count)
	
	# team assignment based on Role
	if is_player or role == Globals.UnitRole.PLAYER:
		player_group.add_child(new_unit)
	elif role == Globals.UnitRole.NEUTRAL:
		neutral_group.add_child(new_unit)
	else:
		enemy_group.add_child(new_unit)
		
	var map = get_tree().get_first_node_in_group("MapManager")
	new_unit.global_position = map.cell_to_unit_pos(cell)
	
	return new_unit

func _spawn_from_template(scene: PackedScene, template: UnitData, cell: Vector2i, is_player: bool) -> void:
	var new_unit = spawn_unit(scene, template, cell, is_player)
	unit_spawned.emit(new_unit, cell)

# A helper to get every unit in the game regardless of team
func get_all_units() -> Array[Unit]:
	var list: Array[Unit] = []
	for team in [player_group, enemy_group, neutral_group]:
		for child in team.get_children():
			if child is Unit:
				list.append(child)
	return list
