extends Resource
class_name AttackResource

enum TargetType { SINGLE, AOE, SELF }
enum HitResult { MISS, GRAZE, HIT, CRIT }

@export_group("Identity")
@export var attack_name: String = "Basic Attack"
@export var category: Globals.AttackCategory = Globals.AttackCategory.PHYSICAL
@export var attack_desc: String = "Description" 
@export var icon: Texture2D

@export_group("Costs")
@export var health_cost: float = 0.0
@export var stamina_cost: float = 20.0
@export var mana_cost: float = 10.0
@export var cooldown_turns: int = 0
@export var requires_charge: bool = false
@export var charge_type_needed: String = "Arcane"

@export_group("Damage Logic")
@export var damage_type: Globals.DamageType = Globals.DamageType.PHYSICAL
@export var scaling_stat: Globals.ScalingStat = Globals.ScalingStat.STRENGTH
@export var multiplier: float = 1.0 # The "2x" from your formula
@export var dice_type: Globals.DieType = Globals.DieType.D6
@export var dice_count: int = 2 # Allow for 2d8, etc.
@export var crit_chance_bonus: float = 0.0
@export var crit_multiplier_bonus: float = 0.0 # Added to base (e.g., +0.5x)

@export_group("Logic")
@export var target_type: TargetType = TargetType.SINGLE
@export var max_targets: int = 1 # New: How many times can we click?
@export var attack_range: int = 1
@export var aoe_shape: Globals.AreaShape = Globals.AreaShape.SQUARE
@export var aoe_range: int = 0 # If SINGLE, we just leave this at 0
@export var has_projectile: bool = false
@export var projectile_speed: float = 200.0
@export var is_healing: bool = false

@export_group("Hit Roll Logic")
@export var accuracy_bonus: float = 0.0 # Attack-specific bonus/penalty
@export var graze_chance_bonus: float = 0.0 # Becomes 20% total with base
@export var graze_multiplier_bonus: float = 0.0

@export_group("Effects")
@export var buff_to_apply: BuffResource # Optional buff resource
@export var skill_script: GDScript # Drag and drop
@export var knockback_distance: int = 0
@export var surface_to_create: SurfaceData
@export var surface_duration: int = 0 # How many turns it lasts

@export_group("Visual Effects")
@export var hold_vfx: VisualEffectData
@export var casting_vfx: VisualEffectData  # Hand/Body glow
@export var target_cast_vfx: VisualEffectData # Plays on the target during casting  
@export var projectile_vfx: VisualEffectData # projectile sprite
@export var impact_vfx: VisualEffectData   # Explosion on the ground
@export var hit_vfx: VisualEffectData # unit effect on being hit

@export_group("Sound Effects")
@export var hold_sfx: AudioStream 
@export var casting_sfx: AudioStream  
@export var projectile_sfx: AudioStream 
@export var impact_sfx: AudioStream     
@export var hit_sfx: AudioStream   
@export var surface_sfx: AudioStream   

@export_group("Screen Effects")
@export var use_screen_flash: bool = false
@export var screen_shake_type: Globals.ShakeType = Globals.ShakeType.NONE
@export var screen_freeze_type: Globals.FreezeType = Globals.FreezeType.NONE
@export var screen_zoom_type: Globals.ZoomType = Globals.ZoomType.NONE

# This function handles the "How much damage?" logic
func get_damage_data(attacker_stats: Resource, defender_stats: Resource) -> Array:
	var roll = randf() * 100.0
	var result = HitResult.MISS
	var multiplier_used = 1.0
	var ceilings_info = "" # For the console log
	
	# --- 1. ACCURACY BRANCHING ---
	if category == Globals.AttackCategory.SPELL:
		var miss_ceiling = (100.0 - attacker_stats.current_spell_accuracy) + defender_stats.current_spell_resistance
		var graze_ceiling = miss_ceiling + defender_stats.base_spell_graze_chance
		ceilings_info = "Miss < %.1f | Graze < %.1f" % [miss_ceiling, graze_ceiling]
		
		if roll <= miss_ceiling:
			result = HitResult.MISS
			multiplier_used = 0.0
		elif roll <= graze_ceiling:
			result = HitResult.GRAZE
			multiplier_used = defender_stats.base_spell_graze_multiplier
		else:
			result = HitResult.HIT
			multiplier_used = 1.0
	else:
		# Physical Logic
		var miss_ceiling = (100.0 - attacker_stats.current_accuracy) + defender_stats.current_evasion - accuracy_bonus
		var total_graze_chance = attacker_stats.current_graze_chance + graze_chance_bonus
		var graze_ceiling = miss_ceiling + total_graze_chance
		var total_crit_chance = attacker_stats.current_crit_chance + crit_chance_bonus
		var crit_threshold = 100.0 - total_crit_chance
		ceilings_info = "Miss < %.1f | Graze < %.1f | Crit > %.1f" % [miss_ceiling, graze_ceiling, crit_threshold]

		if roll <= miss_ceiling:
			result = HitResult.MISS
			multiplier_used = 0.0
		elif roll <= graze_ceiling:
			result = HitResult.GRAZE
			multiplier_used = attacker_stats.current_graze_multiplier + graze_multiplier_bonus
		else:
			result = HitResult.HIT
			multiplier_used = 1.0 # Default Hit
			if roll >= crit_threshold:
				result = HitResult.CRIT
				multiplier_used = attacker_stats.current_crit_multiplier + crit_multiplier_bonus

	# --- 2. SHARED DAMAGE FORMULA ---
	var stat_bonus = _get_scaling_bonus(attacker_stats)
	var stat_label = Globals.ScalingStat.keys()[scaling_stat].to_upper() # Gets "STRENGTH", "AGILITY", etc.
	# Note: using 'multiplier' (from resource) * 'multiplier_used' (from roll)
	var flat_damage = (stat_bonus * multiplier) #Flat dmg is static * multiplier_used
	
	# Dice Logic with Breakdown
	var dice_rolls = []
	var dice_sum = 0
	for i in range(dice_count):
		var r = Globals.roll(dice_type)
		dice_rolls.append(r)
		dice_sum += r
	
	var final_dice_damage = float(dice_sum) * multiplier_used
	var total_pre_resist = flat_damage + final_dice_damage
	
	# Resistances (Fire, Water, etc.)
	var resist_pct = defender_stats.get_resistance(damage_type)
	var final_damage = total_pre_resist * (1.0 - resist_pct)
	
	# 3. IF HEALING: Flip the entire result to negative
	if is_healing:
		final_damage = -final_damage
	
	# --- 4. UPDATED CONSOLE LOGGING ---
	#var attacker_name = attacker_stats.character_name if "character_name" in attacker_stats else "Attacker"
	#var target_name = defender_stats.character_name if "character_name" in defender_stats else defender_stats.object_name
	var result_name = "RESISTED" if (result == HitResult.MISS and category == Globals.AttackCategory.SPELL) else HitResult.keys()[result]
	
	print("--- [COMBAT: %s] ---" % attack_name.to_upper())
	print("Result: %s (Roll: %d | %s)" % [result_name, roundi(roll), ceilings_info])

	var dice_details = str(dice_rolls).replace("[", "").replace("]", "").replace(",", " +")
	var dice_math_str = "(%s) * %.1fx" % [dice_details, multiplier_used]

	print("Base Stat: %s (%d) * %.1f = %.1f" % [stat_label, roundi(stat_bonus), multiplier, flat_damage])
	print("Dice Roll: %dd%s -> %s = %.1f" % [dice_count, dice_type, dice_math_str, final_dice_damage])

	if resist_pct != 0:
		print("Resisted: -%d%% damage" % roundi(resist_pct * 100))

	var final_word = "HEAL" if final_damage < 0 else "TOTAL"
	print(">> %s: %d" % [final_word, abs(roundi(final_damage))])
	print("-------------------")

	return [final_damage, result]

func _get_scaling_bonus(s: Stats) -> float:
	match scaling_stat:
		Globals.ScalingStat.STRENGTH: return s.current_strength
		Globals.ScalingStat.INTELLIGENCE: return s.current_intelligence
		Globals.ScalingStat.AGILITY: return s.current_agility
	return 0.0

func _get_spell_result(attacker: Resource, defender: Resource) -> Array:
	var roll = randf() * 100.0
	
	# 1. CALCULATE THRESHOLDS
	# Logic: If Acc is 100 and Resist is 10, miss_ceiling is 10.
	# If Acc is 110 (Buffed), miss_ceiling becomes 0 (Can't miss).
	var miss_ceiling = (100.0 - attacker.current_spell_accuracy) + defender.current_spell_resistance
	var graze_ceiling = miss_ceiling + defender.base_spell_graze_chance
	
	var dmg_multiplier = 1.0
	var result = HitResult.HIT
	
	# 2. DETERMINE RESULT
	if roll <= miss_ceiling:
		result = HitResult.MISS
		dmg_multiplier = 0.0
	elif roll <= graze_ceiling:
		result = HitResult.GRAZE
		dmg_multiplier = defender.base_spell_graze_multiplier
	else:
		result = HitResult.HIT
		dmg_multiplier = 1.0
		
	return [dmg_multiplier, result]
