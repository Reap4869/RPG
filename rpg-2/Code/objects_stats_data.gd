extends Resource
class_name ObjectStats

# Signals updated to pass floats
signal health_depleted
#signal health_changed(cur_health: float, max_health: float)

# --- Identity ---
@export_group("Identity")
@export var Object_name: String = "Object"
@export var base_max_health: float = 15.0
@export var health: float = 10.0

@export_group("Combat Attributes")
@export var base_crit_chance: float = 0.0 # Percentage
@export var base_crit_multiplier: float = 0.0 # 2.0x damage
@export var base_evasion: float = 0.1
@export var base_accuracy: float = 0.1
@export var base_graze_chance: float = 20.0 # Base 20%
@export var base_graze_multiplier: float = 0.5 # 50% damage

@export_group("Resistances")
@export var resistances: Dictionary[Globals.DamageType, float] = {
	Globals.DamageType.PHYSICAL: 0.0,
	Globals.DamageType.FIRE: 0.0,
	Globals.DamageType.WATER: 0.0,
	Globals.DamageType.EARTH: 0.0,
	Globals.DamageType.AIR: 0.0
}
@export_group("Misc")
@export_multiline var description: String = "Just a thing."

var current_max_health: float
var current_strength: float
var current_agility: float
var current_intelligence: float
var current_crit_chance: float
var current_crit_multiplier: float
var current_accuracy: float = base_accuracy
var current_evasion: float = base_evasion
var current_graze_chance: float = base_graze_chance
var current_graze_multiplier: float

func setup_stats() -> void:
	health = current_max_health

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0:
		health_depleted.emit()
