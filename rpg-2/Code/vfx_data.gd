extends Resource
class_name VisualEffectData

enum DurationType { ONE_SHOT, TURN_BASED, PERMANENT, MANUAL }

@export var effect_name: String = "New Effect"
@export var effect_scene: PackedScene # The actual Particles or AnimatedSprite
@export var duration_type: DurationType = DurationType.ONE_SHOT
@export var visual_scale: float = 1.0 # NEW: Default scale is 1.0
