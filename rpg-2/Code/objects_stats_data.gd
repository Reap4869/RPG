extends Resource
class_name ObjectStats


signal request_log(message: String, color: Color)
signal health_depleted
signal health_changed(cur_health: float, max_health: float)
signal buffs_updated(active_buffs: Array)

var active_buffs: Array = [] # Stores { "resource": BuffResource, "remaining": int }
var caster_object: WorldObject  # Store the person who applied the buff
# Stores { "Attack_Name": remaining_turns }

# --- Identity ---
@export_group("Identity")
@export var object_name: String = "Object"
@export var base_xp_value: int = 1

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
	Globals.DamageType.WATER: 0.0,
	Globals.DamageType.EARTH: 0.0,
	Globals.DamageType.FIRE: 0.0,
	Globals.DamageType.AIR: 0.0,
	Globals.DamageType.GRASS: 0.0,
	Globals.DamageType.POISON: 0.0,
	Globals.DamageType.ELECTRIC: 0.0,
	Globals.DamageType.DARK: 0.0,
	Globals.DamageType.LOVE: 0.0,
	Globals.DamageType.ICE: 0.0,
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


func add_buff(buff_res: BuffResource, is_graze: bool = false, caster: WorldObject = null):
	# --- ELEMENTAL INTERACTIONS ---
	if buff_res.buff_name == "Wet":
		_remove_buff_by_name("Burn")
		# Optional: if you want Wet and Burn to cancel each other out:
		# return 
	
	if buff_res.buff_name == "Burn" and _has_buff("Wet"):
		print("Burn fizzled! Object is Wet.")
		_send_to_combat_log("%s's fire was put out by water!" % object_name, Color.CYAN)
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
	var msg = buff_res.on_applied_message % object_name
	_send_to_combat_log(msg, Color.ORANGE_RED if not buff_res.is_positive else Color.GREEN_YELLOW)

	print("[BUFF] Added %s for %d turns!" % [buff_res.buff_name, dur])
	# IMPORTANT: Update stats so +STR or +Agility buffs take effect now
	recalculate_stats()
	buffs_updated.emit(active_buffs)

func apply_turn_start_buffs(victim_object: WorldObject, game_ref: Node) -> void:
	var to_remove = []
	for b in active_buffs:
		# Tick Damage logic
		if b.resource.damage_per_tick != 0 or b.resource.dice_count > 0:
			# Safety check: if caster is missing, default to null
			var buff_caster = b.get("caster", null) 
			game_ref._apply_tick_damage(victim_object, b.resource.damage_per_tick, b.resource.damage_type, b.resource, buff_caster)
		
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
	
	if to_remove.size() > 0:
		recalculate_stats()
		buffs_updated.emit(active_buffs)


# Helper to find if a buff exists
func _has_buff(b_name: String) -> bool:
	for b in active_buffs:
		if b.resource.buff_name == b_name: return true
	return false

# Helper to remove a buff (useful for cleansing)
func _remove_buff_by_name(b_name: String) -> void:
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].resource.buff_name == b_name:
			var msg = active_buffs[i].resource.on_expired_message % object_name
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
	print("=== DEBUG BUFFS FOR %s ===" % object_name)
	
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
