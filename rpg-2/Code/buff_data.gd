extends Resource
class_name BuffResource

@export var buff_name: String = "Burn"
@export var icon: Texture2D
@export var is_permanent: bool = false
@export var duration: int = 3 # Turns
@export var is_positive: bool = false

@export_group("Stat Changes")
@export var stat_modifiers: Dictionary = {
	"water_resistance": 0.1 # +10%
}

@export_group("Tick Logic")
@export var damage_per_tick: int = 5
@export var damage_type: Globals.DamageType = Globals.DamageType.FIRE
