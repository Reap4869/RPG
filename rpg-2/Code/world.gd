extends Node2D

@onready var map: MapManager = $MapManager
@onready var units: Node = $UnitsManager
@onready var highlights: Node2D = $CellHighlights
@onready var objects: Node2D = $Objects

func _ready() -> void:
	# Enable Y-Sorting via code to ensure it's always on
	y_sort_enabled = true
	
	# Ensure all children that contain moving parts are also Y-Sorted
	units.y_sort_enabled = true
	objects.y_sort_enabled = true
	

# Optional: A helper to get all units in the world for the Game script
func get_all_units() -> Array[Unit]:
	var all_units: Array[Unit] = []
	for group in units.get_children():
		for unit in group.get_children():
			if unit is Unit:
				all_units.append(unit)
	return all_units
