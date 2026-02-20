extends Resource
class_name UnitData

@export_group("Visuals")
@export var sprite_sheet: Texture2D # We only need ONE texture reference
@export var visual_scale: float = 1.0
@export var world_region: Rect2    # The body on the map
@export var portrait_region: Rect2 # The face in the UI
@export var sprite_offset: Vector2 = Vector2(0, 0)

@export_group("Logic")
@export var is_player_controlled: bool = false
@export var ai_behavior: UnitAI
@export var role: Globals.UnitRole = Globals.UnitRole.ENEMY
@export var is_blocking: bool = true # Does it stop movement?
@export var movement_cost_mult: float = 1.0 # 1.5 for Bushes
@export var is_destructible: bool = true
@export var grid_size: Vector2i = Vector2i(1, 1) # 1x1, 2x2, or 3x3

@export_group("Stats & Skills")
@export var base_stats: Stats
@export var attacks: Array[AttackResource] = [] 
@export var default_attack_index: int = 0
@export var death_skill: AttackResource # For Explosive Barrels
