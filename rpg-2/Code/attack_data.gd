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
func get_damage_data(attacker_stats: Stats, defender_stats: Resource) -> Array:
	if category == Globals.AttackCategory.SPELL:
		return _get_spell_result(attacker_stats, defender_stats)
	var roll = randf() * 100.0
	var result = HitResult.MISS
	
	# 1. CALCULATE THRESHOLDS (High is Good)
	# Miss ceiling: If Acc=95 and Eva=5, miss is 100-95+5 = 10. Rolls 0-10 miss.
	var miss_ceiling = (100.0 - attacker_stats.current_accuracy) + defender_stats.current_evasion - accuracy_bonus
	
	# Graze is the slice immediately above Miss. 
	var total_graze_chance = attacker_stats.current_graze_chance + graze_chance_bonus
	var graze_ceiling = miss_ceiling + total_graze_chance
	
	# Crit is the top slice (e.g., if crit chance is 10%, rolls 90-100 crit)
	var total_crit_chance = attacker_stats.current_crit_chance + crit_chance_bonus
	var crit_threshold = 100.0 - total_crit_chance

	# 2. DETERMINE RESULT
	if roll <= miss_ceiling:
		result = HitResult.MISS
	elif roll <= graze_ceiling:
		result = HitResult.GRAZE
	else:
		result = HitResult.HIT
		
	if result == HitResult.HIT and roll >= crit_threshold:
		result = HitResult.CRIT

	# 3. DAMAGE CALCULATION
	var stat_bonus = _get_scaling_bonus(attacker_stats)
	var flat_damage = stat_bonus * multiplier
	
	var dice_roll = 0
	var rolls_array = []
	for i in range(dice_count):
		var r = Globals.roll(dice_type)
		dice_roll += r
		rolls_array.append(str(r))
	
	var final_dice_damage = float(dice_roll)
	var multiplier_used = 1.0
	
	match result:
		HitResult.GRAZE:
			multiplier_used = attacker_stats.current_graze_multiplier + graze_multiplier_bonus
			final_dice_damage = dice_roll * multiplier_used
			flat_damage *= multiplier_used
		HitResult.CRIT:
			multiplier_used = attacker_stats.current_crit_multiplier + crit_multiplier_bonus
			final_dice_damage = dice_roll * multiplier_used

	var total_pre_resist = flat_damage + final_dice_damage
	
	# 4. RESISTANCES
	var resist_pct = defender_stats.resistances.get(damage_type, 0.0)
	var damage_blocked = total_pre_resist * resist_pct
	var final_damage = total_pre_resist - damage_blocked

	# --- CONSOLE DEBUG PRINT ---
	print("\n--- ATTACK BY: %s ---" % attacker_stats.character_name)
	print("RESULT: %s (Roll: %d | Miss: <%.0f, Graze: <%.0f, Crit: >%.0f)" % [
		HitResult.keys()[result], roll, miss_ceiling, graze_ceiling, crit_threshold
	])
	
	if result != HitResult.MISS:
		var dice_str = " + ".join(rolls_array)
		var mult_str = " (x%.1f %s)" % [multiplier_used, HitResult.keys()[result]] if multiplier_used != 1.0 else ""
		print("MATH: (Dice: %s) %d + (Stat: %.0f) = %.1f total %s" % [
			dice_str, dice_roll, stat_bonus * multiplier, total_pre_resist, mult_str
		])
		print("RESIST: %s (%d%%) blocked %.1f" % [
			Globals.DamageType.keys()[damage_type], resist_pct * 100, damage_blocked
		])
		print("FINAL DMG: %d" % roundi(final_damage))
	print("-----------------------\n")
	
	return [maxf(1.0, final_damage), result]

func _get_scaling_bonus(s: Stats) -> float:
	match scaling_stat:
		ScalingStat.STRENGTH: return s.current_strength
		ScalingStat.INTELLIGENCE: return s.current_intelligence
		ScalingStat.AGILITY: return s.current_agility
	return 0.0

func _get_spell_result(attacker: Resource, defender: Resource) -> Array:
	var roll = randf() * 100.0
	
	# 1. Check for flat Resistance (10% base)
	var resist_chance = defender.spell_resistance_chance
	if roll <= resist_chance:
		return [0.0, HitResult.MISS] # Resisted!
		
	# 2. Check for Graze (40% chance)
	# Roll is now between 10 and 100. 
	# If we want a 40% chance of the total, we check the next slice.
	var graze_ceiling = resist_chance + defender.base_spell_graze_chance
	if roll <= graze_ceiling:
		return [0.5, HitResult.GRAZE] # Half effect
		
	# 3. Full Success (Remaining 50%)
	return [1.0, HitResult.HIT]
