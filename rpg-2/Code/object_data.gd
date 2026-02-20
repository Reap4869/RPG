extends Resource
class_name ObjectData

@export_group("Identity")
@export var object_name: String = "Object"
@export var sprite_texture: Texture2D
@export var world_region: Rect2
@export var visual_scale: float = 1.0
@export var sprite_offset: Vector2 = Vector2.ZERO

@export_group("Logic")
@export var stats: ObjectStats
@export var is_blocking: bool = true # Does it stop movement?
@export var movement_cost_mult: float = 1.0 # 1.5 for Bushes
@export var is_destructible: bool = true
@export var death_skill: AttackResource # For Explosive Barrels
@export var grid_size: Vector2i = Vector2i(1, 1)
