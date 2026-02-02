extends Resource
class_name Stats

var active_buffs: Array = [] # Stores { "resource": BuffResource, "remaining": int }

enum BuffableStats {
	MAX_HEALTH,
	ATTACK,
	STRENGTH,
	AGILITY,
	INTELLIGENCE,
	MAX_STAMINA,
	MAX_MANA,
}

const STAT_CURVES: Dictionary[BuffableStats, Curve] = {
	BuffableStats.MAX_HEALTH: preload("uid://b2adyunahql7j"),
	BuffableStats.ATTACK: preload("uid://gycpns8hll7u"),
	BuffableStats.MAX_STAMINA: preload("uid://ca0lby74n756k"),
	BuffableStats.MAX_MANA: preload("uid://1x811moyuv5e"),
	BuffableStats.STRENGTH: preload("uid://cr3piexrfce1c"),
	BuffableStats.AGILITY: preload("uid://de5ssgwxwb73f"),
	BuffableStats.INTELLIGENCE: preload("uid://boonfkle4i7cd"),
}

const BASE_LEVEL_XP: float = 100.0

# Signals updated to pass floats
signal health_depleted
signal health_changed(cur_health: float, max_health: float)
signal stamina_changed(cur_stamina: float, max_stamina: float)
signal mana_changed(cur_mana: float, max_mana: float)

# --- Identity ---
@export_group("Identity")
@export var character_name: String = "Name: Unknown"
@export var race: String = "Race: Unknown"
@export var background: String = "Background: Unknown"
@export var character_class: String = "Class: Unknown"

# Attributes
@export_group("Base Attributes")
@export var base_strength: float = 5.0
@export var base_agility: float = 5.0
@export var base_intelligence: float = 5.0

@export_group("Combat Attributes")
@export var base_crit_chance: float = 5.0 # Percentage
@export var base_crit_multiplier: float = 2.0 # 2.0x damage
# Evasion: How likely this unit is to dodge (Base 5%)
@export var base_evasion: float = 5.0
# Accuracy: How likely this unit is to hit (Base 95%)
@export var base_accuracy: float = 95.0
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
var current_attack: float
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
var current_max_mana: float
var current_max_stamina: float

# Resource Meters
var health: float = 0.0: set = _on_health_set
var stamina: float = 0.0: set = _on_stamina_set
var mana: float = 0.0: set = _on_mana_set

@export_group("Base Stats")
@export var base_max_health: float = 20.0
@export var base_max_stamina: float = 50.0
@export var base_max_mana: float = 20.0

@export var experience: int = 0: set = _on_experience_set

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
@export_multiline var description: String = "Description: Unknown"
@export_multiline var lore: String = "Lore: Unknown"

var level: int:
	get(): return floor(max(1.0, sqrt(experience / BASE_LEVEL_XP) + 0.5))
	

var stat_buffs: Array[StatBuff]

func _init() -> void:
	setup_stats.call_deferred()

func setup_stats() -> void:
	recalculate_stats()
	health = current_max_health
	stamina = current_max_stamina
	mana = current_max_mana

func recalculate_stats() -> void:
	var sample_pos: float = clamp((float(level) / 100.0), 0.0, 1.0)
	
	var get_mult = func(stat_type: BuffableStats):
		if STAT_CURVES.has(stat_type) and STAT_CURVES[stat_type] is Curve:
			return STAT_CURVES[stat_type].sample(sample_pos)
		return 1.0

	# 1. Calculate Base Attributes first
	current_strength = base_strength * get_mult.call(BuffableStats.STRENGTH)
	current_agility = base_agility * get_mult.call(BuffableStats.AGILITY)
	current_intelligence = base_intelligence * get_mult.call(BuffableStats.INTELLIGENCE)

	# 2. Process Buffs for Attributes
	_apply_buff_logic()

	# 3. Calculate Derived Stats using your formulas
	# Formula: 20 + 2 * STR
	current_max_health = base_max_health + (2.0 * current_strength)
	current_max_mana = base_max_mana + (2.0 * current_intelligence)
	current_max_stamina = base_max_stamina + (2.0 * current_agility)
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
	stamina = stamina
	mana = mana

func add_buff(buff_res: BuffResource, is_graze: bool = false):
	var dur = buff_res.duration
	if is_graze: dur = floori(dur / 2.0)
	
	# Check if buff already exists (Refresh duration)
	for b in active_buffs:
		if b.resource.buff_name == buff_res.buff_name:
			b.remaining = max(b.remaining, dur)
			return

	active_buffs.append({ "resource": buff_res, "remaining": dur })

func apply_turn_start_buffs(victim_unit: Node2D):
	var to_remove = []
	for b in active_buffs:
		# 1. Deal Tick Damage
		if b.resource.damage_per_tick > 0:
			# Call back to game_node to handle damage/vfx
			var game = victim_unit.get_parent() 
			game._apply_tick_damage(victim_unit, b.resource.damage_per_tick, b.resource.damage_type)
		
		# 2. Reduce Duration
		if not b.resource.is_permanent:
			b.remaining -= 1
			if b.remaining <= 0:
				to_remove.append(b)
				
	for b in to_remove:
		active_buffs.erase(b)

func _apply_buff_logic() -> void:
	var stat_multipliers: Dictionary = {}
	var stat_addends: Dictionary = {}

	for buff in stat_buffs:
		var stat_name: String = BuffableStats.keys()[buff.stat].to_lower()
		match buff.buff_type:
			StatBuff.BuffType.ADD:
				stat_addends[stat_name] = stat_addends.get(stat_name, 0.0) + buff.buff_amount
			StatBuff.BuffType.MULTIPLY:
				stat_multipliers[stat_name] = stat_multipliers.get(stat_name, 1.0) + buff.buff_amount

	for stat_name in stat_multipliers:
		var prop = "current_" + stat_name
		if prop in self:
			set(prop, get(prop) * stat_multipliers[stat_name])

	for stat_name in stat_addends:
		var prop = "current_" + stat_name
		if prop in self:
			set(prop, get(prop) + stat_addends[stat_name])

func take_damage(amount: float) -> void:
	health -= amount

# --- Setters ---

func _on_health_set(value: float) -> void:
	health = clampf(value, 0.0, current_max_health)
	health_changed.emit(health, current_max_health)
	if health <= 0:
		health_depleted.emit()

func _on_stamina_set(value: float) -> void:
	stamina = clampf(value, 0.0, current_max_stamina)
	stamina_changed.emit(stamina, current_max_stamina)

func _on_mana_set(value: float) -> void:
	mana = clampf(value, 0.0, current_max_mana)
	mana_changed.emit(mana, current_max_mana)

func _on_experience_set(new_value: int) -> void:
	experience = new_value
	recalculate_stats()
