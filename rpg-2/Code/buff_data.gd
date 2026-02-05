extends Resource
class_name BuffResource

enum BuffType {
	MULTIPLY,
	ADD,
}

@export var buff_name: String = "Buff"
@export var icon: Texture2D
@export var is_permanent: bool = false
@export var duration: int = 3 # Turns
@export var is_positive: bool = false
@export var buff_type: BuffType

@export_group("Flavor Text")
# Use %s as a placeholder for the character's name
@export var on_applied_message: String = "%s is on Fire!" 
@export var on_expired_message: String = "%s is no longer burning."

@export_group("Stat Changes")
#In the Dic store what stats_data will use
@export var stat_modifiers: Dictionary[String, float] = {}

@export_group("Tick Logic")
@export var damage_per_tick: int = 0
@export var damage_type: Globals.DamageType = Globals.DamageType.FIRE
