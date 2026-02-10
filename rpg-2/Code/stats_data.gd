extends Resource
class_name Stats

signal buffs_updated(active_buffs: Array)
signal charges_updated(new_charges: Dictionary)
signal cooldowns_updated() # Useful for graying out UI buttons
signal request_log(message: String, color: Color)
signal health_depleted
signal health_changed(cur_health: float, max_health: float)
signal stamina_changed(cur_stamina: float, max_stamina: float)
signal mana_changed(cur_mana: float, max_mana: float)
signal leveled_up(new_level: int)

var active_buffs: Array = [] # Stores { "resource": BuffResource, "remaining": int }
var caster_unit: Unit  # Store the person who applied the buff
# Stores { "Attack_Name": remaining_turns }
var attack_cooldowns: Dictionary = {}
# Stores { "Charge_Name": count }

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
@export var base_xp_value: int = 50

@export_group("Combat Attributes")
@export var base_crit_chance: float = 5.0 # Percentage
@export var base_crit_multiplier: float = 2.0 # 2.0x damage
# Evasion: How likely this unit is to dodge (Base 5%)
@export var base_evasion: float = 5.0
# Accuracy: How likely this unit is to hit (Base 95%)
@export var base_accuracy: float = 95.0
@export var base_graze_chance: float = 20.0 # Base 20%
@export var base_graze_multiplier: float = 0.5 # 50% damage
@export var special_charges: Dictionary = {
	"Knives": 0,
	"Bolts": 0,
	"Bombs": 0,
}

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
var current_evasion: float
var current_accuracy: float
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
@export var base_max_health: float = 15.0
@export var base_max_stamina: float = 15.0
@export var base_max_mana: float = 10.0
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

const BASE_LEVEL_XP: float = 100.0
var level: int:
	get(): return floor(max(1.0, sqrt(experience / BASE_LEVEL_XP) + 0.5))
	

func _init() -> void:
	setup_stats.call_deferred()

func setup_stats() -> void:
	recalculate_stats()
	health = current_max_health
	stamina = current_max_stamina
	mana = current_max_mana

func recalculate_stats() -> void:
	# Use the function to get the TOTAL value, not just the sum
	current_strength = _get_modifier_sum(base_strength, "strength")
	current_agility = _get_modifier_sum(base_agility, "agility")
	current_intelligence = _get_modifier_sum(base_intelligence, "intelligence")
	
	current_crit_chance = _get_modifier_sum(base_crit_chance, "")
	current_crit_multiplier= _get_modifier_sum(base_crit_multiplier, "")
	current_accuracy = _get_modifier_sum(base_accuracy, "accuracy")
	current_evasion = _get_modifier_sum(base_evasion, "evasion")
	current_graze_chance = _get_modifier_sum(base_graze_chance, "")
	current_graze_multiplier = _get_modifier_sum(base_graze_multiplier, "")

	current_spell_accuracy = _get_modifier_sum(base_spell_accuracy, "")
	current_spell_resistance = _get_modifier_sum(base_spell_resistance, "")
	current_spell_graze_chance = _get_modifier_sum(base_spell_graze_chance, "")
	current_spell_graze_multiplier = _get_modifier_sum(base_spell_graze_multiplier, "")

	
	# Recalculate derived health/stamina based on the NEW current attributes
	current_max_health = base_max_health + (5.0 * current_strength)
	current_max_stamina = base_max_stamina + (5.0 * current_agility)
	current_max_mana = base_max_mana + (10.0 * current_intelligence)

	# Ensure resources don't exceed new maximums
	health = health
	stamina = stamina
	mana = mana

func add_buff(buff_res: BuffResource, is_graze: bool = false, caster: Unit = null):
	# --- ELEMENTAL INTERACTIONS ---
	if buff_res.buff_name == "Wet":
		_remove_buff_by_name("Burn")
		# Optional: if you want Wet and Burn to cancel each other out:
		# return 
	
	if buff_res.buff_name == "Burn" and _has_buff("Wet"):
		print("Burn fizzled! Object is Wet.")
		_send_to_combat_log("%s's fire was put out by water!" % character_name, Color.CYAN)
		return
	# ------------------------
	
	var dur = buff_res.duration
	if is_graze: dur = floori(dur / 2.0)
	
	for b in active_buffs:
		if b.resource.buff_name == buff_res.buff_name:
			# If it's the Stacking Poison, we ADD the stats instead of just refreshing
			if buff_res.buff_name == "Toxin":
				# We store 'stacks' in the dictionary to multiply the effect
				b.stacks = b.get("stacks", 1) + 1
				b.remaining = max(b.remaining, dur) # Also refresh duration
				print("[Toxin] Stacked! Total stacks: %d" % b.stacks)
			else:
				# Normal behavior for other buffs
				b.remaining = max(b.remaining, dur)
				b.caster = caster
			
			recalculate_stats()
			buffs_updated.emit(active_buffs)
			return
	
	# New buff entry (initialize stacks to 1)
	active_buffs.append({ 
		"resource": buff_res, 
		"remaining": dur,
		"caster": caster,
		"stacks": 1 
	})
	
	# In your stats script, you might not have access to the CombatLog directly,
	# so we can emit a signal or use a Global call.
	var msg = buff_res.on_applied_message % character_name
	_send_to_combat_log(msg, Color.ORANGE_RED if not buff_res.is_positive else Color.GREEN_YELLOW)

	print("[BUFF] Added %s for %d turns!" % [buff_res.buff_name, dur])
	# IMPORTANT: Update stats so +STR or +Agility buffs take effect now
	recalculate_stats()
	buffs_updated.emit(active_buffs)

func apply_turn_start_buffs(victim_unit: Unit, game_ref: Node) -> void:
	var to_remove = []
	for b in active_buffs:
		# Tick Damage logic
		if b.resource.damage_per_tick != 0 or b.resource.dice_count > 0:
			# Safety check: if caster is missing, default to null
			var buff_caster = b.get("caster", null) 
			game_ref._apply_tick_damage(victim_unit, b.resource.damage_per_tick, b.resource.damage_type, b.resource, buff_caster)
		
		# Duration logic
		if not b.resource.is_permanent:
			b.remaining -= 1
			if b.remaining <= 0:
				to_remove.append(b)
				# Trigger the custom "Expired" message
				var msg = b.resource.on_expired_message % character_name
				_send_to_combat_log(msg, Color.GRAY)
				print("%s" % [msg])
				
	for b in to_remove:
		active_buffs.erase(b)
	
	if to_remove.size() > 0:
		recalculate_stats()
		buffs_updated.emit(active_buffs)
	
	# --- NEW: Process Cooldowns ---
	var cd_changed = false
	for attack_name in attack_cooldowns.keys():
		attack_cooldowns[attack_name] -= 1
		if attack_cooldowns[attack_name] <= 0:
			attack_cooldowns.erase(attack_name)
		cd_changed = true
	
	if cd_changed:
		cooldowns_updated.emit()

# Helper to find if a buff exists
func _has_buff(b_name: String) -> bool:
	for b in active_buffs:
		if b.resource.buff_name == b_name: return true
	return false

# Helper to remove a buff (useful for cleansing)
func _remove_buff_by_name(b_name: String) -> void:
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].resource.buff_name == b_name:
			var msg = active_buffs[i].resource.on_expired_message % character_name
			_send_to_combat_log(msg, Color.GRAY)
			active_buffs.remove_at(i)
			buffs_updated.emit(active_buffs)
	recalculate_stats()

# Helper function to parse the Dictionary in your BuffResources
func _get_modifier_sum(base_value: float, stat_key: String) -> float:
	var flat_mod = 0.0
	var mult_mod = 1.0
	
	for b in active_buffs:
		if b.resource.stat_modifiers.has(stat_key):
			if b.resource.buff_type == BuffResource.BuffType.ADD:
				flat_mod += b.resource.stat_modifiers[stat_key]
			else:
				mult_mod *= b.resource.stat_modifiers[stat_key]
				
	return (base_value * mult_mod) + flat_mod

# Helper for your Skills/Charges
func add_charge(charge_name: String, amount: int = 1) -> void:
	special_charges[charge_name] = special_charges.get(charge_name, 0) + amount
	print("Added charge: %s (Total: %d)" % [charge_name, special_charges[charge_name]])
	charges_updated.emit(special_charges) # Force UI refresh

func has_charge(charge_name: String) -> bool:
	return special_charges.get(charge_name, 0) > 0

func consume_charge(charge_name: String) -> void:
	if has_charge(charge_name):
		special_charges[charge_name] -= 1
		# We removed the erase() and the early return. 
		# We want to emit the signal even if it just hit 0.
		charges_updated.emit(special_charges)

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

func get_curse_score(stack_modifier: float = 1.0) -> float:
	var total_curses = 0.0
	for b in active_buffs:
		# Check the @export var is_positive from the resource
		if not b.resource.is_positive:
			# Count the buff itself (1)
			total_curses += 1.0
			
			# Add negative stacks multiplied by the modifier
			var stacks = b.get("stacks", 1)
			if stacks > 1:
				# Subtract 1 because the first stack is already counted in 'total_curses += 1'
				total_curses += (stacks - 1) * stack_modifier
				
	return total_curses

func debug_print_buffs() -> void:
	print("=== DEBUG BUFFS FOR %s ===" % character_name)
	
	var positive = []
	var negative = []
	
	for b in active_buffs:
		if b.resource.is_positive:
			positive.append(b)
		else:
			negative.append(b)
			
	print("--- BOONS (+) ---")
	if positive.is_empty(): print("  None")
	for b in positive:
		_print_buff_line(b)
		
	print("--- CURSES (-) ---")
	if negative.is_empty(): print("  None")
	for b in negative:
		_print_buff_line(b)
		
	print("=====================")

# Private helper to keep the code clean
func _print_buff_line(b: Dictionary) -> void:
	var caster_name = b.get("caster").name if b.get("caster") else "Env"
	var stacks = b.get("stacks", 1)
	var stack_str = " (x%d)" % stacks if stacks > 1 else ""
	print("  [%s%s] | From: %s | Ends in: %d" % [b.resource.buff_name, stack_str, caster_name, b.remaining])
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
	var old_level = level
	experience = new_value
	recalculate_stats()
	
	if level > old_level:
		print("Level Up! Now level %d" % level)
		leveled_up.emit(level)
		# You can emit a signal here for level-up VFX/SFX
