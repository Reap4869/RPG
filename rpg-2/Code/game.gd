extends Node

signal attack_finished

@export var starting_map: MapData 
@export var fire_vfx_resource: VisualEffectData
@export var water_vfx_resource: VisualEffectData

@onready var world = $World
@onready var map_manager = $World/MapManager
@onready var units_manager = $World/UnitsManager
@onready var objects_manager = $World/Objects
@onready var player_team: PlayerGroup = $World/UnitsManager/PlayerGroup
@onready var enemy_team: EnemyGroup = $World/UnitsManager/EnemyGroup
@onready var neutral_team: NeutralGroup = $World/UnitsManager/NeutralGroup
@onready var selector = $Selector
@onready var highlights = $World/CellHighlights
@onready var main_ui = $UI/MainUI
@onready var unit_info_panel = $UI/MainUI/UnitInfoPanel
@onready var combat_input = $CombatInput
@onready var player_controller = $PlayerController
@export var footstep_sounds: Array[AudioStream] = []

var step_interval: float = 0.22 # Minimum time between sounds
var last_step_time: float = 0.0
var occupancy_grid: Dictionary = {}
var active_unit: Unit = null
var selected_unit: Unit = null
var enemy_queue: Array = []
var multi_target_selection: Array[Vector2i] = []
var current_attack_index: int = -1
var active_hold_sfx: AudioStreamPlayer2D = null
var active_hold_vfx: Node = null
var is_attack_in_progress: bool = false # The "Lock"
var all_units: Array[Unit]:
	get:
		return units_manager.get_all_units()
var movement_history: Array[Vector2i] = []
var current_mode := InteractionMode.SELECT
enum InteractionMode { SELECT, ATTACK }

const WORLD_VFX_SCENE = preload("uid://pc6usvw46jfj")

func _ready() -> void:
	add_to_group("Game")  # <-- ensure other nodes can find the Game node by group
	if units_manager.player_group.has_signal("player_defeated"):
		units_manager.player_group.player_defeated.connect(_trigger_game_over)
	if units_manager.enemy_group.has_signal("enemies_defeated"):
		units_manager.enemy_group.enemies_defeated.connect(_trigger_victory)
	selector.cell_clicked.connect(_on_selector_clicked)
	if $MusicPlayer.stream:
		$MusicPlayer.play()
	$UI/MainUI.end_turn_requested.connect(_on_end_turn_button_pressed)
	$UI/MainUI.attack_requested.connect(_on_attack_requested)
	
	combat_input.cursor_moved.connect(_on_cursor_moved)
	combat_input.confirm.connect(_on_combat_confirm)
	combat_input.cancel.connect(_on_combat_cancel)
	
	# FORCE Exploration mode at the very start
	Globals.current_mode = Globals.GameMode.EXPLORATION
	#main_ui.show_combat_elements(false) # Hide end turn buttons, etc.
	
	if starting_map:
		_initialize_battle(starting_map)
	else:
		print("Warning: No starting_map assigned!")
# --- INITIALIZATION ---

func _initialize_battle(map_resource: MapData) -> void:
	# 1. Clear the "Boss's" record
	occupancy_grid.clear()
	# 2. Tell the MapManager to build the walls and start the music
	map_manager.setup_map(map_resource)
	# 3. Ensure the Boss is listening for new units
	if not units_manager.unit_spawned.is_connected(_on_unit_registered):
		units_manager.unit_spawned.connect(_on_unit_registered)
	# 4. Tell the other Managers to spawn their things
	units_manager.setup_units(map_resource)
#	objects_manager.setup_objects(map_resource) # Pass the whole resource!
	# 5. Position the camera
	_setup_camera(map_resource)
	if not objects_manager.object_spawned.is_connected(_on_object_registered):
		objects_manager.object_spawned.connect(_on_object_registered)
		
	objects_manager.setup_objects(map_resource)
	
	# Ensure we stay in exploration
	Globals.current_mode = Globals.GameMode.EXPLORATION
	print("[SYSTEM] Map initialized. Mode: EXPLORATION")
	_setup_exploration_party()
	
	# Ensure PlayerController.active_unit is set for exploration movement
	if player_team.get_child_count() > 0:
		var lead = player_team.get_child(0)
		_set_active_unit(lead)
		_set_selected_unit(lead)
		
	var pc = _get_player_controller()
	if pc: pc.game = self # Only thing _set_active_unit doesn't do

# --- MAP & QUEST STUFF ---
func change_map(new_map_resource: MapData) -> void:
	print("[DEBUG] Players at start of change_map: ", player_team.get_child_count())
	print("[SYSTEM] Changing map to: ", new_map_resource.resource_path)
	selector.set_process(false)
	
	occupancy_grid.clear()
	
	for unit in enemy_team.get_children(): unit.queue_free()
	for unit in neutral_team.get_children(): unit.queue_free()
	for obj in objects_manager.get_children(): obj.queue_free()
	
	await get_tree().process_frame
	
	_initialize_battle(new_map_resource)
	
	# WAIT: Give the MapManager and TileMap a frame to settle
	await get_tree().process_frame
	
	var start_cell = Vector2i(5, 5) 
	var players = player_team.get_children()
	
	print("[DEBUG] Found %d player units to teleport" % players.size())
	
	for i in range(players.size()):
		var p = players[i] as Unit
		if not p: continue
		
		var target_cell = start_cell + Vector2i(0, i)
		var world_pos = map_manager.cell_to_floor(target_cell)
		
		# LOGGING THE STATE
		print("[DEBUG] Teleporting %s to Cell %s (World Pos: %s)" % [p.name, target_cell, world_pos])
		
		p.global_position = world_pos
		p.visible = true
		p.z_index = 10 # Force them above the tilemap
		
		# Check if the unit is actually in the tree
		if not p.is_inside_tree():
			print("[ERROR] %s is NOT in the scene tree!" % p.name)
		
		register_unit_position(p, target_cell)
	
	# Verify camera
	_setup_camera(new_map_resource)
	
	await get_tree().process_frame
	selector.set_process(true)
	print("--- MAP CHANGE FINISHED ---\n")

func _handle_npc_interaction(npc: Unit):
	# Stop player movement if they were moving
	if active_unit:
		active_unit.path.clear()
		active_unit.is_moving = false

	if npc.stats.character_name == "Elder":
		_process_quest_logic()
	# Inside _handle_npc_interaction
	if npc.stats.character_name == "GateGuard":
		var field_map = load("res://Resources/Maps/FieldMap.tres")
		change_map(field_map)

func _process_quest_logic():
	var state = Globals.quests["slime_hunt"]
	var npc_name = "Elder"
	
	match state:
		Globals.QuestState.NOT_STARTED:
			main_ui.show_dialogue(npc_name, "Welcome! A blue slime is terrorizing the fields. Can you help?")
			Globals.quests["slime_hunt"] = Globals.QuestState.ACTIVE
			print("Quest Started")
		
		Globals.QuestState.ACTIVE:
			main_ui.show_dialogue(npc_name, "The slime is still in the fields to the East.")
			print("Quest OnGoing")
			
		Globals.QuestState.COMPLETED:
			main_ui.show_dialogue(npc_name, "Incredible! You've saved us. Take this experience.")
			award_quest_xp(500)
			Globals.quests["slime_hunt"] = Globals.QuestState.REWARDED
			print("Quest Reward")
			
		Globals.QuestState.REWARDED:
			main_ui.show_dialogue(npc_name, "Enjoy your stay in our town.")
			print("Quest Ended")

# --- COMBAT TRANSITION ---
func start_combat(_initiator: Unit):
	if Globals.current_mode == Globals.GameMode.COMBAT: 
		return
	
	Globals.current_mode = Globals.GameMode.COMBAT
	# Disable exploration movement, Enable combat grid
	_get_player_controller().set_process(false)
	combat_input.set_process(true)
	
	_stop_all_unit_movement()
	
	# FIX: Ensure we know which player character was "active" in exploration
	var pc = _get_player_controller()
	var player_to_focus = pc.active_unit if pc and pc.active_unit else player_team.get_child(0)

	# This one call handles: pc sync, skill bar update, and grid cursor snapping!
	_set_active_unit(player_to_focus)
	_set_selected_unit(player_to_focus)
	
	_start_player_turn()

func _stop_all_unit_movement():
	for unit in all_units:
		unit.path.clear()
		unit.is_moving = false
		# Snap them to the nearest cell so they aren't stuck between tiles
		unit.snap_to_cell(unit.get_cell())

# --- COMBAT LOGIC ---

func _on_attack_requested(index: int) -> void:
	if active_unit and not active_unit.is_moving:
		_stop_hold_effects() # Clean up any previous loops first
		
		current_attack_index = index
		multi_target_selection.clear()
		active_unit.switch_attack(index)
		
		var attack = active_unit.equipped_attack
		
		# Start Hold SFX
		if attack.hold_sfx:
			active_hold_sfx = AudioStreamPlayer2D.new()
			active_hold_sfx.stream = attack.hold_sfx
			active_unit.add_child(active_hold_sfx)
			active_hold_sfx.play()
			
		# Start Hold VFX (Like a glow in the hand)
		if attack.hold_vfx:
			active_hold_vfx = WORLD_VFX_SCENE.instantiate()
			active_unit.add_child(active_hold_vfx)
			# CALCULATE OFFSET:
			# Since active_unit's origin (0,0) is the floor, 
			# we move the VFX up to the chest area.
			#var chest_offset = (active_unit.sprite.offset.y / 2.0) * active_unit.data.visual_scale
			#active_hold_vfx.position = Vector2(0, chest_offset) # Use local position!
			active_hold_vfx.position = Vector2(0, -16) # Use local position!
			active_hold_vfx.setup(attack.hold_vfx)

		_set_interaction_mode(InteractionMode.ATTACK)
		_update_highlights()

# Helper function to clean up
func _stop_hold_effects() -> void:
	if is_instance_valid(active_hold_sfx):
		active_hold_sfx.queue_free()
	if is_instance_valid(active_hold_vfx):
		active_hold_vfx.queue_free()

func _handle_attack_input(cell: Vector2i) -> void:
	var attack = active_unit.equipped_attack
	var stats = active_unit.stats
	var attacker_cell = active_unit.get_cell()
	
	# --- 1. PRE-CHECK DISTANCE ---
	# Check distance using your footpint function
	var dist = _get_footprint_distance(attacker_cell, active_unit.data.grid_size, cell)
	if dist > attack.attack_range:
		print("Out of range!")
		return
	
	# --- NEW: LINE OF SIGHT CHECK ---
	# We check from the attacker to the specific cell they just clicked
	if not map_manager.is_line_clear(attacker_cell, cell): # Added 'true' to ignore target cell
		_send_to_log("Target out of sight!", Color.GRAY)
		return
	
	# --- 2. CHECK COOLDOWNS & CHARGES ---
	if stats.attack_cooldowns.has(attack.attack_name):
		print("Attack on cooldown! %d turns left." % stats.attack_cooldowns[attack.attack_name])
		return
		
	if attack.requires_charge and not stats.has_charge(attack.charge_type_needed):
		print("Requires %s charge!" % attack.charge_type_needed)
		return
	
	# Add target
	multi_target_selection.append(cell)
	
	var progress_text = "%s (%d/%d)" % [attack.attack_name, multi_target_selection.size(), attack.max_targets]
	main_ui.skill_bar.set_button_text(current_attack_index, progress_text)
	
	if multi_target_selection.size() >= attack.max_targets:
		# CHECK COSTS RIGHT BEFORE EXECUTION
		if active_unit.stats.stamina < attack.stamina_cost or active_unit.stats.mana < attack.mana_cost:
			print("Not enough resources!")
			multi_target_selection.clear()
			return
			
		# --- 3. CONSUME EVERYTHING ---
		active_unit.stats.stamina -= attack.stamina_cost
		active_unit.stats.mana -= attack.mana_cost
		active_unit.stats.health -= attack.health_cost # Added health cost!
		
		# Consume Charge
		if attack.requires_charge:
			stats.consume_charge(attack.charge_type_needed)
		
		# Trigger Cooldown
		if attack.cooldown_turns > 0:
			stats.attack_cooldowns[attack.attack_name] = attack.cooldown_turns
		
		var targets_to_fire = multi_target_selection.duplicate()
		multi_target_selection.clear()
		main_ui.skill_bar.set_button_text(current_attack_index, attack.attack_name)
		_execute_multi_target_attack(targets_to_fire)

func _execute_multi_target_attack(target_cells: Array[Vector2i]) -> void:
	# Add a safety check: if we return early, we MUST still emit the signal 
	# or the AI will hang forever.
	if not active_unit: 
		print("Error: No active unit for attack execution!")
		attack_finished.emit() 
		return
	is_attack_in_progress = true
	var attack = active_unit.equipped_attack
	_stop_hold_effects()

	# --- 1. CASTING PHASE ---
	var active_vfx_nodes: Array[Node] = []
	
	# Visual on the Unit
	if attack.casting_vfx:
		var vfx = WORLD_VFX_SCENE.instantiate()
		world.add_child(vfx)
		vfx.global_position = active_unit.global_position
		vfx.setup(attack.casting_vfx)
		active_vfx_nodes.append(vfx)

	# Visual on the TARGETED CELLS (The new part!)
	if attack.target_cast_vfx:
		for cell in target_cells:
			var target_vfx = WORLD_VFX_SCENE.instantiate()
			world.add_child(target_vfx)
			target_vfx.global_position = map_manager.cell_to_center(cell)
			target_vfx.setup(attack.target_cast_vfx)
			active_vfx_nodes.append(target_vfx)

	# Wait for casting sound
	if attack.casting_sfx:
		var p = play_sfx(attack.casting_sfx, active_unit.global_position)
		if p: await p.finished

	# --- 2. CLEANUP CASTING LOOPS ---
	for node in active_vfx_nodes:
		if is_instance_valid(node):
			node.queue_free()

	# 2. TARGET LOOP
	for i in range(target_cells.size()):
		var target_cell = target_cells[i]
		#var target_pos = map_manager.cell_to_world(target_cell)
		var tile_center = map_manager.cell_to_center(target_cell)
		
		# PROJECTILE PHASE
		if attack.has_projectile:
			var proj_scene = load("uid://nlir0s34c32o")
			if proj_scene:
				var proj = proj_scene.instantiate()
				get_parent().add_child(proj)
				# Use your working chest height math
				var chest_height = (active_unit.sprite.offset.y / 2.0) * active_unit.data.visual_scale
				var launch_pos = active_unit.global_position + Vector2(0, chest_height)
				
				# Target the top-left of the tile (matching old version)
				proj.launch(attack.projectile_vfx, launch_pos, tile_center, attack.projectile_speed, attack.projectile_sfx)
				await proj.arrived
		
		# IMPACT PHASE (Only once at the CENTER of the target_cell)
		if attack.impact_sfx:
			play_sfx(attack.impact_sfx, tile_center)
		
		if attack.impact_vfx:
			var vfx = WORLD_VFX_SCENE.instantiate()
			world.add_child(vfx)
			vfx.global_position = tile_center
			vfx.setup(attack.impact_vfx)
		
		
		# 1. HIT STOP (Freeze)
		if attack.screen_freeze_type != Globals.FreezeType.NONE:
			await _apply_hit_stop(attack.screen_freeze_type) 

		# 2. CAMERA ZOOM (Now separate!)
		if attack.screen_zoom_type != Globals.ZoomType.NONE:
			var cam = get_viewport().get_camera_2d()
			if cam:
				cam.apply_impact_zoom(attack.screen_zoom_type, tile_center)

		# 3. SCREEN FLASH
		if attack.use_screen_flash:
			_apply_screen_flash(Color(1, 1, 1, 0.5), 0.15)

		# 4. SCREEN SHAKE
		if attack.screen_shake_type != Globals.ShakeType.NONE:
			_apply_screen_shake(attack.screen_shake_type)
		
		# --- NEW: TRIGGER TILE-BASED SKILLS ---
		if attack.skill_script:
			var action = attack.skill_script.new()
			# 1:attacker, 2:victim, 3:cell, 4:attack, 5:game_ref
			# We pass null for victim because we are targeting the GROUND here
			action.execute_skill(active_unit, null, target_cell, attack, self)
		
		# 3. AOE LOGIC (Apply hits to victims)
		var attacker_cell = active_unit.get_cell()
		# PASS attacker_cell HERE:
		var affected_tiles = _get_aoe_tiles(target_cell, attack.aoe_range, attack.aoe_shape, attacker_cell)
		for cell in affected_tiles:
			var victim = _get_occupant_at_cell(cell)
			if victim:
				# SFX on the unit
				if attack.hit_sfx:
					play_sfx(attack.hit_sfx, victim.global_position)
				
				# NEW: Add hit_vfx if you have one in your Resource
				if attack.hit_vfx:
					var h_vfx = WORLD_VFX_SCENE.instantiate()
					world.add_child(h_vfx)
					var chest_offset = -20 * victim.data.visual_scale
					h_vfx.global_position =  victim.global_position + Vector2(0, chest_offset)
					h_vfx.setup(attack.hit_vfx)
					
				_apply_attack_damage(attack, active_unit, victim, target_cell) # Pass target_cell here too
			# SURFACE LOGIC
			if attack.surface_to_create != null:
				map_manager.apply_surface_to_cell(cell, attack.surface_to_create, attack.surface_duration)

	# 3. UNLOCK
	print("[COMBAT] Execution complete. Cleaning up.")
	is_attack_in_progress = false # UNLOCK INPUT
	# Give the engine one frame to catch up
	await get_tree().process_frame
	# Only switch back to SELECT mode and update UI if it's the player's turn
	if Globals.current_state == Globals.TurnState.PLAYER_TURN:
		_set_interaction_mode(InteractionMode.SELECT)
		if active_unit and active_unit.data.is_player_controlled:
			main_ui.update_buttons(active_unit)
	else:
		# If it's the ENEMY turn, we should NOT be updating the skill bar 
		# or setting the enemy as an "active" unit for the player UI.
		main_ui.skill_bar.update_buttons(null)
	attack_finished.emit()

func _apply_attack_damage(attack: AttackResource, attacker: Node2D, victim: Node2D, impact_cell: Vector2i) -> void:
	# 1. Get Math and Result
	var data = attack.get_damage_data(attacker.stats, victim.stats)
	var damage = data[0]
	var result = data[1]
	if attack.skill_script:
		var action = attack.skill_script.new()
		action.execute_skill(attacker, victim, impact_cell, attack, self)
	# Handle the "Resisted" text override for Spells
	var label_override = ""
	if result == attack.HitResult.MISS and attack.category == Globals.AttackCategory.SPELL:
		label_override = "RESISTED"

	# 2. VFX & Damage Numbers
	if damage < 0:
		var heal_val = abs(damage)
		#victim.stats.health += heal_val 
		_spawn_damage_number(roundi(heal_val), victim.global_position, attack.damage_type, result, "HEAL")
	else:
		_spawn_damage_number(roundi(damage), victim.global_position, attack.damage_type, result, label_override)
	
	if attack.hit_vfx:
		var vfx = WORLD_VFX_SCENE.instantiate()
		world.add_child(vfx)
		vfx.global_position = victim.global_position
		vfx.setup(attack.hit_vfx)

	# 3. Logic Exit on Miss
	if result == attack.HitResult.MISS:
		var msg = "%s resisted %s!" % [victim.name, attack.attack_name] if label_override != "" else "%s missed!" % attacker.name
		_send_to_log(msg, Color.GRAY)
		return

	# 4. Apply Health Change (Works for Units and Objects)
	if victim.has_method("take_damage"):
		victim.take_damage(damage)
		
	# 5. Restore Detailed Combat Log (From Old Version)
	var type_color = Globals.DAMAGE_COLORS.get(attack.damage_type, Color.WHITE)
	var prefix = ""
	match result:
		attack.HitResult.GRAZE: prefix = "GRAZE! "
		attack.HitResult.CRIT: prefix = "CRITICAL HIT! "
	if damage < 0:
		type_color = Color.GREEN 
		var heal_msg = "%s%s used %s! %s heals for" % [prefix, attacker.name, attack.attack_name, victim.name]
		var log_node = get_tree().get_first_node_in_group("CombatLog")
		if log_node:
			# Changed "damage" to "HP"
			log_node.add_combat_entry(heal_msg, str(abs(roundi(damage))) + " HP", type_color)
	else:
		var main_msg = "%s%s used %s! %s takes" % [prefix, attacker.name, attack.attack_name, victim.name]
		var log_node = get_tree().get_first_node_in_group("CombatLog")
		if log_node:
			# Using 'damage' from data[0] and the type_color
			log_node.add_combat_entry(main_msg, str(roundi(damage)), type_color)

	# 6. Apply Buffs (Restoring the Graze Duration penalty)
	if attack.buff_to_apply:
		var is_graze = (result == attack.HitResult.GRAZE)
		if victim.stats.has_method("add_buff"):
			victim.stats.add_buff(attack.buff_to_apply, is_graze, attacker)

	# 7. Death Check
	if victim.stats.health <= 0:
		if victim is Unit:
			_handle_unit_death(victim)
		else:
			_handle_object_death(victim)

func _apply_tick_damage(victim: Node2D, amount: int, type: Globals.DamageType, buff_res: BuffResource = null, caster: Node2D = null) -> void:
	var base_amount = float(amount)
	var dice_sum = 0
	var stat_val = 0.0
	var scaling_info = "None"
	
	# Find the buff entry to get the stack count
	var stack_multiplier = 1
	for b in victim.stats.active_buffs:
		if b.resource == buff_res:
			stack_multiplier = b.get("stacks", 1)
			break
	# ... (your existing Dice and Scaling math) ...
	if buff_res:
		# 1. Dice Logic
		var dice_rolls = []
		for i in range(buff_res.dice_count):
			var r = Globals.roll(buff_res.dice_type)
			dice_rolls.append(r)
			dice_sum += r
		
		# 2. Scaling Logic (Only if caster exists and isn't NONE)
		if caster and buff_res.scaling_stat != Globals.ScalingStat.NONE:
			var source_stats = caster.stats
			match buff_res.scaling_stat:
				Globals.ScalingStat.STRENGTH: 
					stat_val = source_stats.current_strength
					scaling_info = "STR"
				Globals.ScalingStat.INTELLIGENCE: 
					stat_val = source_stats.current_intelligence
					scaling_info = "INT"
				Globals.ScalingStat.AGILITY: 
					stat_val = source_stats.current_agility
					scaling_info = "AGI"
		
		# 3. Calculate Final Amount
		var stat_bonus = stat_val * buff_res.scaling_multiplier
		var total_tick = (base_amount + dice_sum + stat_bonus) * stack_multiplier
		#var total_tick = base_amount + dice_sum + stat_bonus
		
		# IMPORTANT: If the buff is positive, it should be healing (negative damage)
		var final_amount_raw = total_tick
		if buff_res.is_positive:
			final_amount_raw = -total_tick # Flip to negative for healing
		
		# 4. Resistance
		var resist_pct = victim.stats.get_resistance(type)
		var final_amount = roundi(final_amount_raw * (1.0 - resist_pct))
		
		# --- EXPANDED CONSOLE LOG ---
		var _type_name = Globals.DamageType.keys()[type]
		var stack_str = " (x%d Stacks)" % stack_multiplier if stack_multiplier > 1 else ""
		
		print("--- [TICK: %s%s] ---" % [buff_res.buff_name.to_upper(), stack_str])
		
		if buff_res.scaling_stat != Globals.ScalingStat.NONE:
			print("Scaling: %s (%.1f) * %.1f = %.1f" % [scaling_info, stat_val, buff_res.scaling_multiplier, stat_bonus])
		
		var dice_str = "%dd%s (%d)" % [buff_res.dice_count, buff_res.dice_type, dice_sum]
		print("Base: %d | Dice: %s | Bonus: %.1f" % [amount, dice_str, stat_bonus])
	
		var total_pre_stack = amount + dice_sum + stat_bonus
		if stack_multiplier > 1:
			print("Subtotal: %.1f * %d Stacks = %.1f" % [total_pre_stack, stack_multiplier, total_tick])
		
		if resist_pct != 0:
			print("Resist: -%d%%" % roundi(resist_pct * 100))
		
		var final_word = "HEAL" if buff_res.is_positive else "DAMAGE"
		print(">> %s: %d" % [final_word, abs(final_amount)])
		print("-------------------------")

		# 5. Apply to Health and UI
		_process_tick_effects(victim, final_amount, type)

func _process_tick_effects(victim: Node2D, final_amount: int, type: Globals.DamageType):
	var log_node = get_tree().get_first_node_in_group("CombatLog")
	if final_amount < 0:
		var heal_val = abs(final_amount)
		victim.stats.health += heal_val
		if log_node:
			log_node.add_combat_entry("%s heals for" % victim.name, str(heal_val) + " HP", Color.GREEN)
		_spawn_damage_number(heal_val, victim.global_position, type, AttackResource.HitResult.HIT, "HEAL")
	else:
		victim.stats.health -= final_amount
		if log_node:
			log_node.add_combat_entry("%s takes" % victim.name, str(final_amount) + " damage", Globals.DAMAGE_COLORS.get(type, Color.WHITE))
		_spawn_damage_number(final_amount, victim.global_position, type, AttackResource.HitResult.HIT)
		if victim.has_method("play_hit_flash"): victim.play_hit_flash()
		if victim.stats.health <= 0:
			_handle_unit_death(victim)
# --- SELECTION & HIGHLIGHTS ---

func _handle_selection(cell: Vector2i) -> void:
	var occupant = _get_occupant_at_cell(cell)
	
	if occupant is Unit:
		# 1. Check Role
		match occupant.data.role:
			Globals.UnitRole.NEUTRAL:
				_handle_npc_interaction(occupant)
				_set_selected_unit(occupant) # Still show stats if you want
			
			Globals.UnitRole.PLAYER:
				_set_selected_unit(occupant)
				_set_active_unit(occupant)
				main_ui.hide_dialogue() # Close dialogue if we switch to a player
				
			Globals.UnitRole.ENEMY:
				_set_selected_unit(occupant)
				_set_active_unit(null)
	else:
		_set_active_unit(null)
		_set_selected_unit(null)
		main_ui.hide_dialogue()

func _set_selected_unit(unit: Unit) -> void:
	if selected_unit == unit: return # Optimization: don't repeat
	
	# Clean up previous selection visual
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
		
	selected_unit = unit
	
	if unit_info_panel:
		unit_info_panel.display_unit(unit)
	
	if selected_unit:
		selected_unit.set_selected(true)
		print("[UI] Selected Unit: ", unit.name)
	else:
		print("[UI] Selection Cleared")

func _set_active_unit(unit: Unit) -> void:
	# 1. Clean up old active unit signals
	if active_unit and is_instance_valid(active_unit):
		if active_unit.stats.cooldowns_updated.is_connected(_on_stats_updated):
			active_unit.stats.cooldowns_updated.disconnect(_on_stats_updated)

	active_unit = unit
	
	# 2. Update UI & Controller
	var pc = _get_player_controller()
	
	if active_unit and active_unit.data.is_player_controlled:
		main_ui.skill_bar.update_buttons(active_unit)
		active_unit.stats.cooldowns_updated.connect(_on_stats_updated)
		if pc: pc.active_unit = active_unit
	else:
		main_ui.skill_bar.update_buttons(null)
		if pc: pc.active_unit = null
	
	# 3. Handle Highlights
	if highlights:
		highlights.active_unit = unit
		highlights.cached_move_range.clear() 
		highlights.cached_path.clear()       
		_update_highlights()
	
	# 4. Snap Cursor (Combat Only)
	if Globals.current_mode == Globals.GameMode.COMBAT and unit != null:
		var cell = unit.get_cell()
		if combat_input:
			combat_input.set_cursor_cell(cell)

func _on_stats_updated():
	main_ui.skill_bar.update_buttons(active_unit)

func _update_highlights() -> void:
	if not highlights: return
	highlights.active_unit = active_unit
	highlights.display_mode = "attack" if current_mode == InteractionMode.ATTACK else "move"
	highlights.queue_redraw()

func _set_interaction_mode(new_mode: InteractionMode) -> void:
	current_mode = new_mode
	_update_highlights()

# --- UTILITY ---

func _on_unit_registered(unit: Unit, cell: Vector2i) -> void:
	register_unit_position(unit, cell)
	unit.movement_finished.connect(_on_unit_movement_finished)
	if not unit.stats.request_log.is_connected(_send_to_log):
		unit.stats.request_log.connect(_send_to_log)

func _on_object_registered(obj: WorldObject, cell: Vector2i) -> void:
	# Just like register_unit_position, but for objects!
	register_object_position(obj, cell)
	if obj.stats and not obj.stats.request_log.is_connected(_send_to_log):
		obj.stats.request_log.connect(_send_to_log)

func _send_to_log(msg: String, color: Color = Color.WHITE) -> void:
	var log_node = get_tree().get_first_node_in_group("CombatLog")
	if log_node:
		log_node.add_message(msg, color)

# Change '-> Unit' to '-> Node2D' or remove the type hint entirely
func _get_occupant_at_cell(cell: Vector2i) -> Node2D:
	if occupancy_grid.has(cell):
		var occupant = occupancy_grid[cell]
		# Check if the node still exists and hasn't been deleted
		if is_instance_valid(occupant) and not occupant.is_queued_for_deletion():
			return occupant
		else:
			occupancy_grid.erase(cell) # Clean up the ghost entry
	return null

func _handle_unit_death(unit: Unit) -> void:
	if not is_instance_valid(unit): return
	
	# QUEST CHECK: If the unit that died is a specific target
	if unit.stats.character_name == "QuestSlime":
		if Globals.quests["slime_hunt"] == Globals.QuestState.ACTIVE:
			Globals.quests["slime_hunt"] = Globals.QuestState.COMPLETED
			_send_to_log("Quest Objective Complete! Return to Town.", Color.AQUA)
			print("You kill your target!")
	
	_send_to_log("%s has been slain!" % unit.name, Color.ORANGE_RED)
	print("%s has been slain!" % unit.name)
	print("stats name is %s" % unit.stats.character_name)
	_award_kill_xp(unit)
	# 1. Clear the tiles
	unregister_unit(unit)
	
	# 2. Safety: Clear UI references
	if active_unit == unit:
		_set_active_unit(null)
	if selected_unit == unit:
		_set_selected_unit(null)
	
	if unit.data.role == Globals.UnitRole.PLAYER:
		# GRAVEYARD LOGIC: Don't delete, just hide
		unit.visible = false
		unit.process_mode = PROCESS_MODE_DISABLED # Stop AI/Movement
		# Move them far away so they don't accidentally get clicked
		unit.global_position = Vector2(-9999, -9999) 
		print("%s in Graveyard!" % unit.name)
	else:
		# Enemies/Neutrals still die for real
		unit.queue_free()
	
	# MANUALLY TRIGGER CHECK
	#_check_end_conditions()
	# Small delay to let the tree update, then check if someone won
	get_tree().create_timer(0.1).timeout.connect(_check_end_conditions)

func _handle_object_death(obj: WorldObject) -> void:
	_send_to_log("%s was destroyed!" % obj.name, Color.GRAY)
	_award_kill_xp(obj)
	unregister_object(obj)
	obj.queue_free()
	get_tree().create_timer(0.1).timeout.connect(_check_end_conditions)

func _award_kill_xp(killed_unit: Node2D) -> void:
	var xp_to_give = killed_unit.stats.base_xp_value
	
	# If an enemy is killed, we want to reward all players (alive or dead)
	if killed_unit.get_parent() == units_manager.enemy_group:
		# Note: If you want to include dead units, you need a 'all_player_units' array
		# that doesn't get cleared on death, OR award it right before queue_free
		for member in units_manager.player_group.get_children():
			if member is Unit:
				member.stats.experience += xp_to_give
	else:
		# If a player is killed, enemies gain XP
		for member in units_manager.enemy_group.get_children():
			if member is Unit:
				member.stats.experience += xp_to_give

# Function for Quest completions
func award_quest_xp(amount: int) -> void:
	for member in units_manager.player_group.get_children():
		member.stats.experience += amount
	_send_to_log("Quest Complete! Party gained %d XP." % amount, Color.GOLD)

func _setup_camera(map_resource: MapData) -> void:
	var map_width_px = map_resource.size.x * map_manager.cell_size.x
	var map_height_px = map_resource.size.y * map_manager.cell_size.y
	var cam = get_viewport().get_camera_2d()
	if cam and cam.has_method("set"):
		cam.limit_min = Vector2.ZERO
		cam.limit_max = Vector2(map_width_px, map_height_px)

# --- MOVEMENT ---

func _handle_movement(target_cell: Vector2i) -> void:
	if not active_unit or active_unit.is_moving:
		return
		
	var start_cell = active_unit.get_cell()
	
	# NEW: Instead of just clearing a dictionary, we tell the map the unit "lifted"
	# its entire footprint off the grid.
	unregister_unit(active_unit) 
	
	var result = map_manager.get_path_with_stamina(
		start_cell, 
		target_cell, 
		active_unit.stats.stamina, 
		active_unit.data.grid_size,
		active_unit # Pass self to ignore own "ghost" during calculation
	)
	
	var grid_path = result[0]
	
	if grid_path.is_empty(): 
		register_unit_position(active_unit, start_cell)
		return
		
	var world_path := PackedVector2Array()
	for c in grid_path:
		world_path.append(map_manager.cell_to_floor(c))
		
	if not active_unit.cell_entered.is_connected(_on_unit_stepped_on_cell):
		active_unit.cell_entered.connect(_on_unit_stepped_on_cell.bind(active_unit))
		
	active_unit.follow_path(world_path, result[1])

# The function that actually applies the "Hazard" logic
func _on_unit_stepped_on_cell(cell: Vector2i, unit: Node2D) -> void:
	# This uses the MapManager function we updated earlier to handle large units
	map_manager.apply_surface_gameplay_effect(cell, unit)
	
	# 2. Handle Sound Logic
	if Globals.play_footstep_sounds and not footstep_sounds.is_empty():
		var now = Time.get_ticks_msec() / 1000.0
		
		if now - last_step_time >= step_interval:
			_play_random_footstep()
			last_step_time = now

func _play_random_footstep() -> void:
	# Pick a random sound from your list of 3
	var random_index = randi() % footstep_sounds.size()
	var sound_to_play = footstep_sounds[random_index]
	
	# Use the SoundManager we built earlier
	SoundManager.play_sfx(sound_to_play)

func _on_unit_movement_finished(unit: Node2D, final_cell: Vector2i) -> void:
	# Clean up the signal connection
	if unit.cell_entered.is_connected(_on_unit_stepped_on_cell):
		unit.cell_entered.disconnect(_on_unit_stepped_on_cell)
	
	register_unit_position(unit, final_cell)
	print(unit.name," ", final_cell)
	if highlights:
		highlights.cached_move_range.clear()
		highlights.cached_path.clear() # <--- Add this to hide the ghost
		highlights.queue_redraw()
	var cell = unit.get_cell()
	map_manager.apply_surface_gameplay_effect(cell, unit)
	
	if Globals.current_mode == Globals.GameMode.EXPLORATION and Globals.player_count == 1:
		var players = player_team.get_children()
		
		# Only run if the unit that just moved is the Leader (Player 1)
		if unit == players[0]:
			_update_follower_positions(final_cell)

func _update_follower_positions(leader_cell: Vector2i):
	# 1. Update the trail. Lead cell goes to the front.
	movement_history.push_front(leader_cell)
	
	# 2. Keep the history only as long as we have followers
	var players = player_team.get_children()
	if movement_history.size() > players.size():
		movement_history.pop_back()
		
	# 3. Tell followers to move to the history slots
	# Player 0 is Leader, Player 1 follows Leader's previous spot, etc.
	for i in range(1, players.size()):
		if movement_history.size() > i:
			var follower = players[i]
			var target_cell = movement_history[i]
			
			# CHANGE: Use cell_to_floor here as well so the 
			# followers don't "snap" to corners while walking.
			var path = PackedVector2Array([map_manager.cell_to_floor(target_cell)])
			follower.leave_current_cells()
			follower.follow_path(path, 0.0)
			
			# Ensure they register their new spot when they arrive
			if not follower.movement_finished.is_connected(follower.occupy_new_cells):
				follower.movement_finished.connect(follower.occupy_new_cells, CONNECT_ONE_SHOT)

# Initialize the history with the starting positions so they don't teleport
func _setup_exploration_party():
	movement_history.clear()
	var players = player_team.get_children()
	for p in players:
		var cell = map_manager.world_to_cell(p.global_position)
		movement_history.push_back(cell)

func is_cell_vacant(cell: Vector2i, ignore_unit: Unit = null) -> bool:
	if not occupancy_grid.has(cell):
		return true
	
	# If there is a unit there, but it's the one we told the game to ignore...
	if occupancy_grid[cell] == ignore_unit:
		return true
		
	return false

func register_unit_position(unit: Unit, start_cell: Vector2i) -> void:
	unregister_unit(unit) # Always clear first
	
	var size = unit.data.grid_size
	for x in range(size.x):
		for y in range(size.y):
			var cell = start_cell + Vector2i(x, y)
			
			# 1. Update Game's internal tracking
			occupancy_grid[cell] = unit
			
			# 2. Update MapManager's CellData for Divinity-style interaction
			if map_manager.grid_data.has(cell):
				var cell_info = map_manager.grid_data[cell]
				cell_info.is_occupied = true
				cell_info.occupant = unit

func unregister_unit(unit: Unit) -> void:
	if not unit: return
	
	var keys_to_remove = []
	for cell in occupancy_grid.keys():
		if occupancy_grid[cell] == unit:
			keys_to_remove.append(cell)
			
			# NEW: Clear the MapManager data too
			if map_manager.grid_data.has(cell):
				map_manager.grid_data[cell].is_occupied = false
				map_manager.grid_data[cell].occupant = null
	
	for key in keys_to_remove:
		occupancy_grid.erase(key)

func register_object_position(obj: WorldObject, cell: Vector2i) -> void:
	occupancy_grid[cell] = obj
	
	# Also tell the MapManager so AStar knows it's blocked
	if map_manager.grid_data.has(cell):
		var cell_data = map_manager.grid_data[cell]
		cell_data.is_occupied = true
		cell_data.occupant = obj
	
	# Update AStar weights so pathfinding avoids the object
	map_manager.update_astar_weights()

func unregister_object(obj: WorldObject) -> void:
	var keys_to_remove = []
	for cell in occupancy_grid.keys():
		if occupancy_grid[cell] == obj:
			keys_to_remove.append(cell)
			if map_manager.grid_data.has(cell):
				map_manager.grid_data[cell].is_occupied = false
				map_manager.grid_data[cell].occupant = null
	for key in keys_to_remove:
		occupancy_grid.erase(key)

func _get_footprint_distance(origin: Vector2i, size: Vector2i, target: Vector2i) -> int:
	var shortest_dist = 9999
	for x in range(size.x):
		for y in range(size.y):
			var occupied_tile = origin + Vector2i(x, y)
			# Use max() here so the AI understands diagonal attacks!
			var d = max(abs(occupied_tile.x - target.x), abs(occupied_tile.y - target.y))
			if d < shortest_dist:
				shortest_dist = d
	return shortest_dist
	
func _get_aoe_tiles(center: Vector2i, radius: int, shape: Globals.AreaShape, origin: Vector2i = Vector2i.ZERO, fov_deg := 90.0, facing_override := Vector2.ZERO) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	
	if radius <= 0: return [center]

	# Determine facing
	var facing_vec: Vector2
	if facing_override != Vector2.ZERO:
		facing_vec = facing_override.normalized()
	else:
		var diff = center - origin
		facing_vec = Vector2(clampi(diff.x, -1, 1), clampi(diff.y, -1, 1)).normalized()
	
	# Used for LINE and CLEAVE
	var dir = Vector2i(roundi(facing_vec.x), roundi(facing_vec.y))

	match shape:
		Globals.AreaShape.SQUARE:
			# Traditional radius (Radius 1 = 3x3, Radius 2 = 5x5)
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					tiles.append(center + Vector2i(x, y))

		Globals.AreaShape.SQUARESIZE:
			# Your specific offset logic for even/odd total sizes
			var start_offset: int
			var end_offset: int
			
			if radius % 2 == 0: # EVEN (e.g., 2 becomes a 2x2 box)
				start_offset = -(radius / 2) + 1
				end_offset = (radius / 2)
			else: # ODD (e.g., 3 becomes a 3x3 box)
				start_offset = -(radius / 2)
				end_offset = (radius / 2)

			for x in range(start_offset, end_offset + 1):
				for y in range(start_offset, end_offset + 1):
					tiles.append(center + Vector2i(x, y))

		Globals.AreaShape.DIAMOND:
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					if abs(x) + abs(y) <= radius:
						tiles.append(center + Vector2i(x, y))

		Globals.AreaShape.LINE:
			for i in range(radius):
				tiles.append(center + (dir * i))

		Globals.AreaShape.CLEAVE:
			tiles.append(center)
			if abs(dir.x) == 1 and abs(dir.y) == 1:
				tiles.append(center - Vector2i(dir.x, 0))
				tiles.append(center - Vector2i(0, dir.y))
			else:
				var side_dir = Vector2i(-dir.y, dir.x) 
				tiles.append(center + side_dir)
				tiles.append(center - side_dir)

		Globals.AreaShape.CONE:
			var half_fov = fov_deg * 0.5
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					var offset = Vector2i(x, y)
					if offset == Vector2i.ZERO:
						tiles.append(center)
						continue
					
					var t = center + offset
					var dir_to = Vector2(offset).normalized()
					var angle = rad_to_deg(facing_vec.angle_to(dir_to))
					
					if abs(angle) <= half_fov:
						if map_manager.is_line_clear(center, t):
							tiles.append(t)
	
	return tiles

func apply_knockback(victim: Node2D, direction: Vector2i, distance: int) -> void:
	if distance <= 0: return
	
	var current_cell = map_manager.world_to_cell(victim.global_position)
	var final_cell = current_cell
	
	# Check each tile in the path
	for i in range(1, distance + 1):
		var test_cell = current_cell + (direction * i)
		if map_manager.is_area_walkable(test_cell, victim.data.grid_size, victim):
			final_cell = test_cell
		else:
			# Hit a wall/unit, stop early
			break
			
	if final_cell != current_cell:
		register_unit_position(victim, final_cell)
		# CHANGE: Use cell_to_floor (the one with the +Vector2(16,16) offset)
		# to ensure the unit stays centered in the tile after being pushed.
		victim.global_position = map_manager.cell_to_floor(final_cell)
		victim.cell_entered.emit(final_cell)
		_send_to_log("%s was knocked back!" % victim.name, Color.GOLD)

# --- TURNS ---

func _start_unit_turn(unit: Node2D) -> void:
	# 1. Check the surface beneath the unit
	var cell = unit.get_cell()
	map_manager.apply_surface_gameplay_effect(cell, unit)
	
	# 2. Now process the buffs (This will include the burn they just got from the floor)
	if unit.stats.has_method("apply_turn_start_buffs"):
		unit.stats.apply_turn_start_buffs(unit, self)
	
	# 3. Death check (in case the burn killed them)
	if unit.stats.health <= 0:
		_handle_unit_death(unit)

func _start_player_turn() -> void:
	print("--- PLAYER TURN ---")
	print("[TRACE] _start_player_turn() BEFORE - game.active_unit:", active_unit, " pc.active_unit:", _get_player_controller())
	_send_to_log("--- PLAYER TURN ---", Color.WHITE)
	Globals.current_state = Globals.TurnState.PLAYER_TURN
	
	# If we already have an active unit which is a valid, living player-controlled Unit,
	# keep it as the active one. Otherwise, select the first available player unit.
	var keep_active := false
	if active_unit and is_instance_valid(active_unit) and active_unit is Unit:
		if active_unit.data and active_unit.data.is_player_controlled and active_unit.stats and active_unit.stats.health > 0:
			keep_active = true

	if not keep_active:
		select_player_unit()

	# Sync PlayerController.active_unit so input binds to the same unit
	var pc = _get_player_controller()
	if pc:
		if active_unit and active_unit.data and active_unit.data.is_player_controlled:
			pc.active_unit = active_unit
		else:
			pc.active_unit = null

	# Process buffs / start-of-turn logic
	for unit in player_team.get_children():
		if unit is Unit:
			if unit.stats.has_method("apply_turn_start_buffs"):
				unit.stats.apply_turn_start_buffs(unit, self)
			if unit.stats.health <= 0:
				_handle_unit_death(unit)
		
	#Then for objects
	#for obj in objects_manager.get_children():
	#	if obj is WorldObject and obj.stats.has_method("apply_turn_start_buffs"):
			# Pass obj as the 'victim' so tick damage knows where to hit
	#		obj.stats.apply_turn_start_buffs(obj, self)
	
	#map_manager.tick_surfaces()
	print("[TRACE] _start_player_turn() AFTER - game.active_unit:", active_unit, " pc.active_unit:", _get_player_controller())
	player_team.replenish_all_stamina()

func _on_end_turn_button_pressed() -> void:
	if Globals.current_state == Globals.TurnState.PLAYER_TURN:
		_end_player_turn()

func _end_player_turn() -> void:
	# If we just won, don't start the enemy phase!
	if Globals.current_mode == Globals.GameMode.EXPLORATION:
		return
	print("--- TURN ENDED ---")
	Globals.current_state = Globals.TurnState.ENEMY_TURN
	_set_active_unit(null)
	_run_enemy_phase() 

func _run_enemy_phase() -> void:
	print("--- ENEMY TURN ---")
	_send_to_log("--- ENEMY TURN ---", Color.WHITE)
	enemy_team.replenish_all_stamina()
	# Get all enemies and put them in a queue
	enemy_queue = enemy_team.get_children()
	print("[AI] Found ", enemy_queue.size(), " enemies to process.")
	_process_next_enemy()

func _process_next_enemy() -> void:
	# Always clear selection visuals before the next enemy acts
	_set_active_unit(null)
	_set_selected_unit(null)
	
	if enemy_queue.is_empty():
		print("[TURN] All enemies processed. Returning to Player.")
		_start_player_turn()
		return

	var current_enemy = enemy_queue.pop_front()
	print("[AI] Processing: ", current_enemy.name)
	
	if current_enemy is Unit:
		_start_unit_turn(current_enemy)
		
		if current_enemy.stats.health <= 0:
			print("[AI] Unit ", current_enemy.name, " died at start of turn. Skipping.")
			_process_next_enemy()
			return

		if current_enemy.data and current_enemy.data.ai_behavior:
			# AI will set game.active_unit = self inside make_decision
			var ai = current_enemy.data.ai_behavior
			if not ai.decision_completed.is_connected(_process_next_enemy):
				ai.decision_completed.connect(_process_next_enemy, CONNECT_ONE_SHOT)
			print("[AI] Requesting decision from behavior: ", ai.resource_name)
			ai.make_decision(current_enemy, self, map_manager)
	else:
		print("[AI] Warning: ", current_enemy.name, " has no behavior assigned. Skipping.")
		_process_next_enemy()

# --- END CONDITIONS ---

func _check_end_conditions() -> void:
	if units_manager.enemy_group.get_children().size() == 0:
		_trigger_victory()
	elif units_manager.player_group.get_children().size() == 0:
		_trigger_game_over()

func _trigger_victory() -> void:
	# Only trigger victory if we are currently in COMBAT and not already ended
	if Globals.current_mode != Globals.GameMode.COMBAT: return
	if Globals.current_state == Globals.TurnState.VICTORY: return

	Globals.current_state = Globals.TurnState.VICTORY
	
	print("VICTORY!")
	_send_to_log("--- VICTORY! ---", Color.GOLD)
	
	# RESPAWN DEFEATED PLAYERS
	var survivors = player_team.get_children().filter(func(u): return u.visible)
	if survivors.size() > 0:
		var spawn_pos = survivors[0].global_position
		var spawn_cell = map_manager.world_to_cell(spawn_pos)
		
		for p in player_team.get_children():
			if not p.visible: # This was a "dead" player
				p.visible = true
				p.process_mode = PROCESS_MODE_INHERIT
				p.stats.current_hp = 1 # Respawn with 1 HP (or half?)
				
				# Place them near the survivor
				var free_cell = spawn_cell + Vector2i(1, 0) 
				p.global_position = map_manager.cell_to_world(free_cell)
				register_unit_position(p, free_cell)
				_send_to_log("%s has been revived!" % p.name, Color.GREEN)
	
	# Transition back to Exploration
	Globals.current_mode = Globals.GameMode.EXPLORATION
	# Swap back
	# CRITICAL: Reset state so _on_selector_clicked isn't blocked by 
	# the 'if state != PLAYER_TURN' check. 
	# Or, update the input check (see step 2).
	Globals.current_state = Globals.TurnState.PLAYER_TURN 

	_get_player_controller().set_process(true)
	combat_input.set_process(false)
	
	_set_active_unit(null)
	player_team.replenish_all_stamina()
	
	if player_team.get_child_count() > 0:
		_set_active_unit(player_team.get_child(0))

func _trigger_game_over() -> void:
	if Globals.current_mode != Globals.GameMode.COMBAT: return
	if Globals.current_state == Globals.TurnState.GAME_OVER: return

	Globals.current_state = Globals.TurnState.GAME_OVER
	
	print("GAME OVER")
	_send_to_log("--- DEFEAT... ---", Color.RED)
	# Change mode back
	Globals.current_mode = Globals.GameMode.EXPLORATION

# --- EFFECTS VFX SFX ---

func _apply_screen_shake(type: Globals.ShakeType) -> void:
	if not Globals.screen_effects_enabled or type == Globals.ShakeType.NONE:
		return
		
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	var intensity: float = 0.0
	var duration: float = 0.0
	var amount: float = 0.0
	var some: float = 0.0
	
	# Setting different values for each type
	match type:
		Globals.ShakeType.SMALL:
			intensity = 4
			duration = 0.1
			amount = 3
			some = 3
		Globals.ShakeType.MID:
			intensity = 8.0
			duration = 0.2
			amount = 0.15
			some = 6
		Globals.ShakeType.BIG:
			intensity = 8
			duration = 0.4
			amount = 12
			some = 12
	
	var original_offset = camera.offset
	var tween = create_tween()
	
	for i in range(amount):
		var shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity
		tween.tween_property(camera, "offset", shake_offset, duration / some)
	
	tween.tween_property(camera, "offset", original_offset, 0.05)


func _apply_hit_stop(type: Globals.FreezeType) -> void:
	# FIX: Changed 'FreezeTypeType' to 'FreezeType'
	if not Globals.screen_effects_enabled or type == Globals.FreezeType.NONE:
		return
		
	var duration: float = 0.0
	
	match type:
		Globals.FreezeType.SMALL:
			duration = 0.05
		Globals.FreezeType.MID:
			duration = 0.1
		Globals.FreezeType.BIG:
			duration = 0.2 # Dramatic pause for huge hits
	
	Engine.time_scale = 0.05
	# The last 'true' here is vital—it tells the timer to ignore the slow time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func _apply_screen_flash(color: Color, duration: float) -> void:
	if not Globals.screen_effects_enabled:
		return

	# 1. Create the nodes on the fly
	var canvas = CanvasLayer.new()
	var flash = ColorRect.new()
	
	# 2. Setup the flash appearance
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE # Important: don't block clicks!
	
	# 3. Add to the scene
	add_child(canvas)
	canvas.add_child(flash)
	
	# 4. Animate the fade out
	var tween = create_tween()
	# Animates the 'alpha' (transparency) from current to 0
	tween.tween_property(flash, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE)
	
	# 5. Cleanup
	await tween.finished
	canvas.queue_free()

func play_hit_effect(vfx_resource: VisualEffectData, pos: Vector2):
	var vfx = preload("uid://pc6usvw46jfj").instantiate()
	world.add_child(vfx)
	vfx.global_position = pos + Vector2(0, -16)
	vfx.setup(vfx_resource) # It will delete itself automatically

func play_sfx(stream: AudioStream, position: Vector2 = Vector2.ZERO) -> AudioStreamPlayer2D:
	if not stream: return null
	
	var sfx_player = AudioStreamPlayer2D.new()
	sfx_player.stream = stream
	sfx_player.global_position = position
	sfx_player.pitch_scale = randf_range(0.9, 1.1)
	
	add_child(sfx_player)
	sfx_player.play()
	
	sfx_player.finished.connect(sfx_player.queue_free)
	
	# Return the player so we can await it!
	return sfx_player

func _spawn_damage_number(value: int, pos: Vector2, type: Globals.DamageType, result: AttackResource.HitResult, text_override: String = "") -> void:
	var label = Label.new() # Create the node directly
	add_child(label)
	
	var is_healing = (text_override == "HEAL")
	# If healing, we want "+13 HP". If damage, just "13"
	var display_text = "+" + str(value) + " HP" if is_healing else str(value)
	
	# Setup styling
	label.text = display_text
	label.scale = Vector2(2.0, 2.0)
	# 2. Outline (This makes it readable on any background)
	label.add_theme_constant_override("outline_size", 4) # Thickness of the outline
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100 
	
	if is_healing:
		label.modulate = Color.GREEN
	else:
		label.modulate = Globals.DAMAGE_COLORS.get(type, Color.WHITE)
	
	# If it's a CRIT, make it bigger!
	if result == AttackResource.HitResult.CRIT:
		label.scale = Vector2(3.0, 3.0)
		label.add_theme_constant_override("outline_size", 4)
	
	label.global_position = pos + Vector2(-10, -45) # Start closer to unit head
	
	var tween = create_tween().set_parallel(true)
	
	# Slow, small float: move up only 20 pixels (less than 1 tile) over 1.2 seconds
	tween.tween_property(label, "position:y", label.position.y - 25, 1.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	# Fade out starts later and lasts longer
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.8)
	
	tween.finished.connect(label.queue_free)

# --- INPUT HANDLING ---
func hide_debug_panel() -> void:
	var panel = $UI/MainUI/DebugPanel
	panel.visible = !panel.visible

func select_player_unit() -> void:
	# 1. Find the player unit
	var units = player_team.get_children()
	if units.size() == 0:
		return
		
	var unit_to_select = units[0]
	
	# 2. Select it (updates UI and Highlights)
	_set_active_unit(unit_to_select)
	
	# 3. Move Camera and Clamp it
	var cam = get_viewport().get_camera_2d()
	if cam:
		# CHANGE: Center on the visual middle, not the floor position
		var visual_center = unit_to_select.global_position + Vector2(0, -32)
		cam.global_position = visual_center
		if cam.has_method("force_clamp"):
			cam.force_clamp()
			

func _on_selector_clicked(cell: Vector2i, button: int) -> void:
	if is_attack_in_progress: return # Don't allow canceling mid-animation
		
	# Only enforce turn-based logic if we are actually in COMBAT mode
	if Globals.current_mode == Globals.GameMode.COMBAT:
		if Globals.current_state != Globals.TurnState.PLAYER_TURN:
			return

	if button == MOUSE_BUTTON_LEFT:
		if current_mode == InteractionMode.ATTACK:
			_handle_attack_input(cell)
		else:
			_handle_selection(cell)
	elif button == MOUSE_BUTTON_RIGHT:
		# If we have an active player unit, handle their movement
		if active_unit and active_unit.data.is_player_controlled:
			if current_mode == InteractionMode.ATTACK:
				var attack = active_unit.equipped_attack
				_stop_hold_effects()
				main_ui.skill_bar.set_button_text(current_attack_index, attack.attack_name)
				_set_interaction_mode(InteractionMode.SELECT)
				multi_target_selection.clear()
			else:
				_handle_movement(cell)
				

func _get_player_controller() -> PlayerController:
	if is_instance_valid(player_controller):
		return player_controller
	return null
	
func _on_cursor_moved(new_cell: Vector2i) -> void:
	# Hover logic: Show info but don't "activate" the unit
	var occupant = _get_occupant_at_cell(new_cell)
	if occupant is Unit:
		_set_selected_unit(occupant)
	else:
		_set_selected_unit(null)
	# Optionally center camera on cursor
	# var cam = get_viewport().get_camera_2d(); cam.global_position = map_manager.cell_to_world(new_cell)

func _on_combat_confirm(cell: Vector2i) -> void:
	# Pass the "keyboard click" into your existing mouse click logic
	_on_selector_clicked(cell, MOUSE_BUTTON_LEFT)
	# Or call custom: _handle_grid_confirm(cell)

func _on_combat_cancel() -> void:
	# cancel selection or close UI
	# e.g., exit attack mode or deselect
	_set_active_unit(null) # or other logic
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_unit"):
		_cycle_player_units()

func _cycle_player_units() -> void:
	var players = player_team.get_children()
	if players.is_empty(): return
	
	var next_index = 0
	
	# If we have someone selected, find the next one in the list
	if active_unit and active_unit in players:
		var current_index = players.find(active_unit)
		next_index = (current_index + 1) % players.size()
	
	var unit_to_focus = players[next_index]
	
	# Select them
	_set_active_unit(unit_to_focus)
	_set_selected_unit(unit_to_focus)
	
	# Move the camera to them
	var cam = get_viewport().get_camera_2d()
	if cam:
		cam.global_position = unit_to_focus.global_position
