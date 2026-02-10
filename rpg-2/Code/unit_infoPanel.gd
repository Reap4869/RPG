extends Control

# Map the Charge Name to the X/Y coordinates on your spritesheet (in pixels)
const CHARGE_REGIONS = {
	"Knives": Rect2(20, 0, 20, 20),    # x, y, width, height
	"Bolts": Rect2(40, 0, 20, 20),
	"Bombs": Rect2(0, 0, 20, 20),
	"Placeholder": Rect2(60, 0, 20, 20)
}

# Load your charge spritesheet once
var charge_sheet = preload("res://Art/VFX/Charges.png")

@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var exp_bar: ProgressBar = %ExpBar
@onready var desc_container: PanelContainer = %DescContainer
@onready var name_label: Label = %NameLabel
@onready var stats_label: Label = %StatsLabel
@onready var identity_label: Label = %IdentityLabel # Renamed/Added for Race/Class
@onready var description_label: Label = %DescriptionLabel 
@onready var portrait_rect: TextureRect = %PortraitIcon
@onready var buff_container: HBoxContainer = %BuffContainer
@onready var charge_container: HBoxContainer = %ChargeContainer

var displayed_unit: Unit

func _ready() -> void:
	hide()

func display_unit(unit: Unit) -> void:
	if displayed_unit and is_instance_valid(displayed_unit):
		_disconnect_signals(displayed_unit.stats)
	
	displayed_unit = unit
	
	if not unit or not unit.stats: 
		hide()
		return
		
	show()
	modulate = Color.WHITE # Reset grey-out from death
	_connect_signals(unit.stats)

	# Setup Portrait (Only needs to happen once per selection)
	var atlas = AtlasTexture.new()
	atlas.atlas = unit.data.sprite_sheet
	atlas.region = unit.data.portrait_region
	portrait_rect.texture = atlas
	
	# All text and bar values are handled here:
	_update_all_ui()

func _update_all_ui() -> void:
	if not displayed_unit or not displayed_unit.stats: return
	var s = displayed_unit.stats
	var is_player = displayed_unit.data.is_player_controlled
	
	# 1. Bars
	_update_bar(health_bar, s.health, s.current_max_health)
	_update_bar(stamina_bar, s.stamina, s.current_max_stamina)
	_update_bar(mana_bar, s.mana, s.current_max_mana)
	
	var current_lvl = s.level
	# XP required to HAVE reached the current level
	var prev_level_total_xp = s.BASE_LEVEL_XP * pow(current_lvl - 1, 2) if current_lvl > 1 else 0.0
	# XP required to REACH the next level
	var next_level_total_xp = s.BASE_LEVEL_XP * pow(current_lvl, 2)
	
	# How much XP we have gained ONLY within this level
	var current_progress = s.experience - prev_level_total_xp
	# How much total XP is needed to clear this level
	var level_bracket_total = next_level_total_xp - prev_level_total_xp
	
	_update_bar(exp_bar, current_progress, level_bracket_total)
	exp_bar.get_node("Label").text = "Lv.%d: %d / %d" % [current_lvl, roundi(current_progress), roundi(level_bracket_total)]
	
	# --- VISIBILITY TOGGLES ---
	# EXP bar is for players only
	exp_bar.visible = is_player
	
	# Identity and Description are for enemies/NPCs only
	if has_node("%IdentityLabel"):
		%IdentityLabel.visible = not is_player
	description_label.visible = not is_player
	desc_container.visible = not is_player
	# --------------------------

	# 2. Name Header
	name_label.text = displayed_unit.name 

	# 3. Stats Label (Always show for both)
	stats_label.text = "LVL: %d
	STR: %d
	AGI: %d
	INT: %d" % [
		s.level,
		roundi(s.current_strength), 
		roundi(s.current_agility), 
		roundi(s.current_intelligence)
	]

	# 4. Identity & Description (Only update if they are visible)
	if not is_player:
		if has_node("%IdentityLabel"):
			%IdentityLabel.text = "%s
			%s
			%s" % [s.race, s.character_class, s.background]
		
		description_label.text = "%s" % s.description

# --- Internal Helpers ---

#var resist_text = ""
#for type in s.resistances:
#	var val = s.resistances[type]
#	if val != 0:
#		# Converts 0.2 to "20%"
#		resist_text += str(Globals.DamageType.keys()[type]) + ": " + str(val * 100) + "% "

func _update_bar(bar: ProgressBar, current: float, max_val: float) -> void:
	bar.max_value = max_val
	bar.value = current
	bar.get_node("Label").text = "%d / %d" % [roundi(current), roundi(max_val)]

func _connect_signals(stats: Stats) -> void:
	if not stats.health_changed.is_connected(_on_health_changed):
		stats.health_changed.connect(_on_health_changed)
	if not stats.stamina_changed.is_connected(_on_stamina_changed):
		stats.stamina_changed.connect(_on_stamina_changed)
	if not stats.mana_changed.is_connected(_on_mana_changed):
		stats.mana_changed.connect(_on_mana_changed)
	if not stats.health_depleted.is_connected(_on_unit_death):
		stats.health_depleted.connect(_on_unit_death)
	if not stats.buffs_updated.is_connected(_update_buff_icons):
		stats.buffs_updated.connect(_update_buff_icons)
	if not stats.charges_updated.is_connected(_update_charge_icons):
		stats.charges_updated.connect(_update_charge_icons)
	
	# Trigger it once immediately on display
	_update_buff_icons(stats.active_buffs)
	_update_charge_icons(stats.special_charges)

func _disconnect_signals(stats: Stats) -> void:
	if stats.health_changed.is_connected(_on_health_changed):
		stats.health_changed.disconnect(_on_health_changed)
	if stats.stamina_changed.is_connected(_on_stamina_changed):
		stats.stamina_changed.disconnect(_on_stamina_changed)
	if stats.mana_changed.is_connected(_on_mana_changed):
		stats.mana_changed.disconnect(_on_mana_changed)
	if stats.health_depleted.is_connected(_on_unit_death):
		stats.health_depleted.disconnect(_on_unit_death)
	if stats.buffs_updated.is_connected(_update_buff_icons):
		stats.buffs_updated.disconnect(_update_buff_icons)
	if stats.charges_updated.is_connected(_update_charge_icons):
		stats.charges_updated.disconnect(_update_charge_icons)

func _update_buff_icons(active_buffs: Array) -> void:
	# 1. Clear old icons immediately
	for child in buff_container.get_children():
		#buff_container.remove_child(child) # Unparent immediately
		child.queue_free() # Delete later
	
	for buff_data in active_buffs:
		var buff_res = buff_data.resource
		var stacks = buff_data.get("stacks", 1)
		# Create a new TextureRect for the icon
		var icon_rect = TextureRect.new()
		
		# Set the texture from the resource
		if buff_res.icon:
			icon_rect.texture = buff_res.icon
		
		# Styling
		icon_rect.custom_minimum_size = Vector2(20, 20)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# --- DYNAMIC TOOLTIP ---
		icon_rect.tooltip_text = "%s (%d turns) (x%d)" % [buff_res.buff_name, buff_data.remaining, stacks]

		# --- DURATION LABEL (Big, Center) ---
		var dur_label = Label.new()
		dur_label.text = str(buff_data.remaining)
		dur_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dur_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dur_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Fill the icon
		dur_label.add_theme_font_size_override("font_size", 18)
		dur_label.add_theme_color_override("font_outline_color", Color.BLACK)
		dur_label.add_theme_constant_override("outline_size", 6)
		icon_rect.add_child(dur_label)

		# --- STACK LABEL (Small, Bottom-Right) ---
		if stacks > 1:
			var stack_label = Label.new()
			stack_label.text = "%dX" % stacks
			stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			stack_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			stack_label.add_theme_font_size_override("font_size", 12)
			stack_label.add_theme_color_override("font_color", Color.YELLOW)
			stack_label.add_theme_color_override("font_outline_color", Color.BLACK)
			stack_label.add_theme_constant_override("outline_size", 4)
			icon_rect.add_child(stack_label)
		
		buff_container.add_child(icon_rect)

func _update_charge_icons(special_charges: Dictionary) -> void:
	for child in charge_container.get_children():
		child.queue_free()
	
	# This forces the HBox to build from right to left
	charge_container.layout_direction = Control.LAYOUT_DIRECTION_RTL
	
	for charge_name in special_charges:
		var amount = special_charges[charge_name]
		#if amount <= 0: continue # Don't show icons for 0 charges
		
		var icon_rect = TextureRect.new()
		
		# --- ATLAS LOGIC ---
		var atlas = AtlasTexture.new()
		atlas.atlas = charge_sheet
		# Get the region from our dictionary, or use Placeholder if not found
		atlas.region = CHARGE_REGIONS.get(charge_name, CHARGE_REGIONS["Placeholder"])
		icon_rect.texture = atlas
		
		icon_rect.custom_minimum_size = Vector2(20, 20)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.tooltip_text = "%s: %d" % [charge_name, amount]
		
		# --- AMOUNT LABEL (3/3 style as requested) ---
		var amount_label = Label.new()
		amount_label.text = str(amount) # Or "%d/%d" if you have a max
		amount_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		amount_label.add_theme_font_size_override("font_size", 18)
		amount_label.add_theme_color_override("font_outline_color", Color.BLACK)
		amount_label.add_theme_constant_override("outline_size", 6)
		icon_rect.add_child(amount_label)
		
		charge_container.add_child(icon_rect)
# --- Callbacks ---

func _on_health_changed(cur: float, m: float) -> void:
	_update_bar(health_bar, cur, m)

func _on_stamina_changed(cur: float, m: float) -> void:
	_update_bar(stamina_bar, cur, m)

func _on_mana_changed(cur: float, m: float) -> void:
	_update_bar(mana_bar, cur, m)

func _on_unit_death() -> void:
	modulate = Color(0.5, 0.5, 0.5, 1.0)
