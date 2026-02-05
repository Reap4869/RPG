extends Resource
class_name ObjectStats

var active_buffs: Array = [] # Stores { "resource": BuffResource, "remaining": int }

signal request_log(message: String, color: Color)
signal health_depleted
signal health_changed(cur_health: float, max_health: float)


# --- Identity ---
@export_group("Identity")
@export var object_name: String = "Object"

@export_group("Combat Attributes")
@export var base_crit_chance: float = 0.0 # Percentage
@export var base_crit_multiplier: float = 0.0 # 2.0x damage
@export var base_evasion: float = 0.1
@export var base_accuracy: float = 0.1
@export var base_graze_chance: float = 20.0 # Base 20%
@export var base_graze_multiplier: float = 0.5 # 50% damage

@export_group("Spell Attributes")
@export var base_spell_accuracy: float = 100.0
@export var base_spell_resistance: float = 10.0 # This is the "Evasion" for spells
@export var base_spell_graze_chance: float = 40.0
@export var base_spell_graze_multiplier: float = 0.5

# Current Calculated Attributes
var current_strength: float
var current_agility: float
var current_intelligence: float
var current_crit_chance: float
var current_crit_multiplier: float
var current_accuracy: float
var current_evasion: float
var current_graze_chance: float
var current_graze_multiplier: float

var current_spell_accuracy: float
var current_spell_resistance: float
var current_spell_graze_chance: float
var current_spell_graze_multiplier: float

# Derived Stats (The ones using your formulas)
var current_max_health: float

# Resource Meters
var health: float = 0.0: set = _on_health_set


@export_group("Base Stats")
@export var base_max_health: float = 20.0

# 0.2 means 20% damage reduction.
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

func _init() -> void:
	setup_stats.call_deferred()

func setup_stats() -> void:
	recalculate_stats()
	health = current_max_health

func recalculate_stats() -> void:

	# 3. Calculate Derived Stats using your formulas

	current_max_health = base_max_health
	current_crit_chance = base_crit_chance
	current_crit_multiplier = base_crit_multiplier
	current_accuracy = base_accuracy
	current_evasion = base_evasion
	current_graze_chance = base_graze_chance
	current_graze_multiplier = base_graze_multiplier
	current_spell_accuracy = base_spell_accuracy
	current_spell_resistance = base_spell_resistance
	current_spell_graze_chance = base_spell_graze_chance
	current_spell_graze_multiplier = base_graze_multiplier
	
	# Ensure resources don't exceed new maximums
	health = health


func add_buff(buff_res: BuffResource, is_graze: bool = false):
	var dur = buff_res.duration
	if is_graze: dur = floori(dur / 2.0)
	
	# Check if buff already exists (Refresh duration)
	for b in active_buffs:
		if b.resource.buff_name == buff_res.buff_name:
			b.remaining = max(b.remaining, dur)
			return
	active_buffs.append({ "resource": buff_res, "remaining": dur })

func apply_turn_start_buffs(victim_obj: WorldObject, game_ref: Node) -> void:
	var to_remove = []
	for b in active_buffs:
		# Tick Damage logic
		if b.resource.damage_per_tick > 0:
			# Now we use the game_ref we just passed in!
			game_ref._apply_tick_damage(victim_obj, b.resource.damage_per_tick, b.resource.damage_type)
		
		# Duration logic
		if not b.resource.is_permanent:
			b.remaining -= 1
			if b.remaining <= 0:
				to_remove.append(b)
				# Trigger the custom "Expired" message
				var msg = b.resource.on_expired_message % object_name
				_send_to_combat_log(msg, Color.GRAY)
				print("%s" % [msg])
				
	for b in to_remove:
		active_buffs.erase(b)

func take_damage(amount: float) -> void:
	health -= amount

func get_resistance(type: Globals.DamageType) -> float:
	var total_resist = resistances.get(type, 0.0)
	var stat_key = Globals.DamageType.keys()[type].to_lower() + "_resistance"
	
	var add_sum = 0.0
	var mult_total = 1.0
	
	for b in active_buffs:
		if b.resource.stat_modifiers.has(stat_key):
			if b.resource.buff_type == BuffResource.BuffType.ADD:
				add_sum += b.resource.stat_modifiers[stat_key]
			else:
				# This treats 1.1 as a 10% increase to the stat
				mult_total *= b.resource.stat_modifiers[stat_key]
				
	return (total_resist * mult_total) + add_sum
	
func _send_to_combat_log(msg: String, color: Color):
	request_log.emit(msg, color)
	
	# --- Setters ---

func _on_health_set(value: float) -> void:
	health = clampf(value, 0.0, current_max_health)
	health_changed.emit(health, current_max_health)
	if health <= 0:
		health_depleted.emit()
