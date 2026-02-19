extends Resource
class_name MapData

enum TerrainType { NORMAL = 0, WALL = 9, MUD = 1, WATER = 2 }
@export var map_name := "Test Map"
@export var size := Vector2i(32, 23)

@export_group("Spawns")
# We use a Dictionary now: Key = Vector2i, Value = UnitData (The template)
@export var player_spawns: Dictionary[Vector2i, UnitData] = {} 
@export var enemy_spawns: Dictionary[Vector2i, UnitData] = {}
@export var neutral_spawns: Dictionary[Vector2i, UnitData] = {}
@export var object_spawns : Dictionary[Vector2i, ObjectData] = {}
@export_group("Assets")
@export var map_scene: PackedScene # The visual TileMap layout
@export var unit_scene: PackedScene
@export var object_base_scene: PackedScene
@export var music: AudioStream

@export_group("Data")
@export var terrain: Dictionary[Vector2i, TerrainType] = {}

# Helper to check if a tile is walkable according to this data
func is_walkable(cell: Vector2i) -> bool:
	if not (cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y):
		return false
	# Walls (ID 9) are never walkable
	return terrain.get(cell, TerrainType.NORMAL) != TerrainType.WALL
