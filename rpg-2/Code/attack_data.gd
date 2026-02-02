extends Resource
class_name AttackResource

enum TargetType { SINGLE, AOE, SELF }
enum ScalingStat { STRENGTH, INTELLIGENCE, AGILITY }
enum HitResult { MISS, GRAZE, HIT, CRIT }

@export_group("Identity")
@export var attack_name: String = "Basic Attack"
@export var category: Globals.AttackCategory = Globals.AttackCategory.PHYSICAL
@export var attack_desc: String = "Description" 
@export var icon: Texture2D

@export_group("Costs")
@export var health_cost: float = 0.0
@export var stamina_cost: float = 10.0
@export var mana_cost: float = 0.0

@export_group("Damage Logic")
@export var damage_type: Globals.DamageType = Globals.DamageType.PHYSICAL
@export var scaling_stat: ScalingStat = ScalingStat.STRENGTH
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

@export_group("Hit Roll Logic")
@export var accuracy_bonus: float = 0.0 # Attack-specific bonus/penalty
@export var graze_chance_bonus: float = 0.0 # Becomes 20% total with base
@export var graze_multiplier_bonus: float = 0.0

@export_group("Effects")
@export var buff_to_apply: StatBuff # Optional buff resource
@export var surface_to_create: Globals.SurfaceType = Globals.SurfaceType.FIRE
@export var surface_duration: int = 0 # How many turns it lasts

@export_group("Visual Effects")
@export var hold_vfx: VisualEffectData
@export var casting_vfx: VisualEffectData  # Hand/Body glow
@export var target_cast_vfx: VisualEffectData # Plays on the target during casting  
@export var projectile_vfx: VisualEffectData # projectile sprite
@export var impact_vfx: VisualEffectData   # Explosion on the ground
@export var hit_vfx: VisualEffectData # unit effect on being hit
@export var surface_vfx: VisualEffectData # The surface it leaves behind

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
	
	# --- 1. ACCURACY BRANCHING ---
	if category == Globals.AttackCategory.SPELL:
		# Spell Logic: Resist (10%) | Graze (40%) | Hit (50%)
		var miss_ceiling = (100.0 - attacker_stats.current_spell_accuracy) + defender_stats.current_spell_resistance
		var graze_ceiling = miss_ceiling + defender_stats.base_spell_graze_chance
		
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
		# Physical Logic (Your existing code)
		var miss_ceiling = (100.0 - attacker_stats.current_accuracy) + defender_stats.current_evasion - accuracy_bonus
		var total_graze_chance = attacker_stats.current_graze_chance + graze_chance_bonus
		var graze_ceiling = miss_ceiling + total_graze_chance
		var total_crit_chance = attacker_stats.current_crit_chance + crit_chance_bonus
		var crit_threshold = 100.0 - total_crit_chance

		if roll <= miss_ceiling:
			result = HitResult.MISS
			multiplier_used = 0.0
		elif roll <= graze_ceiling:
			result = HitResult.GRAZE
			multiplier_used = attacker_stats.current_graze_multiplier + graze_multiplier_bonus
		else:
			result = HitResult.HIT
			if roll >= crit_threshold:
				result = HitResult.CRIT
				multiplier_used = attacker_stats.current_crit_multiplier + crit_multiplier_bonus

	# --- 2. SHARED DAMAGE FORMULA ---
	# (Calculate raw damage using the multiplier we just found)
	var stat_bonus = _get_scaling_bonus(attacker_stats)
	var flat_damage = (stat_bonus * multiplier) * multiplier_used
	
	var dice_roll = 0
	for i in range(dice_count):
		dice_roll += Globals.roll(dice_type)
	
	var final_dice_damage = float(dice_roll) * multiplier_used
	var total_pre_resist = flat_damage + final_dice_damage
	
	# Resistances (Fire, Water, etc. work exactly the same for Spells/Phys)
	var resist_pct = defender_stats.resistances.get(damage_type, 0.0)
	var final_damage = total_pre_resist * (1.0 - resist_pct)

	# --- 3. CONSOLE LOGGING (With "Resisted" Support) ---
	var result_name = "RESISTED" if (result == HitResult.MISS and category == Globals.AttackCategory.SPELL) else HitResult.keys()[result]
	print("[%s] Result: %s | Final Damage: %d" % [category, result_name, roundi(final_damage)])

	return [maxf(0.0, final_damage), result]


func _get_scaling_bonus(s: Stats) -> float:
	match scaling_stat:
		ScalingStat.STRENGTH: return s.current_strength
		ScalingStat.INTELLIGENCE: return s.current_intelligence
		ScalingStat.AGILITY: return s.current_agility
	return 0.0

func _get_spell_result(attacker: Resource, defender: Resource) -> Array:
	var roll = randf() * 100.0
	
	# 1. CALCULATE THRESHOLDS
	# Logic: If Acc is 100 and Resist is 10, miss_ceiling is 10.
	# If Acc is 110 (Buffed), miss_ceiling becomes 0 (Can't miss).
	var miss_ceiling = (100.0 - attacker.current_spell_accuracy) + defender.current_spell_resistance
	var graze_ceiling = miss_ceiling + defender.base_spell_graze_chance
	
	var multiplier = 1.0
	var result = HitResult.HIT
	
	# 2. DETERMINE RESULT
	if roll <= miss_ceiling:
		result = HitResult.MISS
		multiplier = 0.0
	elif roll <= graze_ceiling:
		result = HitResult.GRAZE
		multiplier = defender.base_spell_graze_multiplier
	else:
		result = HitResult.HIT
		multiplier = 1.0
		
	return [multiplier, result]
