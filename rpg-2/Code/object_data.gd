extends Resource
class_name ObjectData

@export var object_name: String = "Destructible Object"
@export var sprite_texture: Texture2D
@export var world_region: Rect2
@export var visual_scale: float = 1.0
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var is_destructible: bool = true
@export var grid_size: Vector2i = Vector2i(1, 1)

@export_group("Stats")
@export var stats: ObjectStats
@export var is_blocking: bool = true # Does it stop movement?
