extends Control

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
	
	var next_level_xp = Stats.BASE_LEVEL_XP * (s.level + 1)
	_update_bar(exp_bar, float(s.experience), next_level_xp)
	
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

func _disconnect_signals(stats: Stats) -> void:
	if stats.health_changed.is_connected(_on_health_changed):
		stats.health_changed.disconnect(_on_health_changed)
	if stats.stamina_changed.is_connected(_on_stamina_changed):
		stats.stamina_changed.disconnect(_on_stamina_changed)
	if stats.mana_changed.is_connected(_on_mana_changed):
		stats.mana_changed.disconnect(_on_mana_changed)
	if stats.health_depleted.is_connected(_on_unit_death):
		stats.health_depleted.disconnect(_on_unit_death)

# --- Callbacks ---

func _on_health_changed(cur: float, m: float) -> void:
	_update_bar(health_bar, cur, m)

func _on_stamina_changed(cur: float, m: float) -> void:
	_update_bar(stamina_bar, cur, m)

func _on_mana_changed(cur: float, m: float) -> void:
	_update_bar(mana_bar, cur, m)

func _on_unit_death() -> void:
	modulate = Color(0.5, 0.5, 0.5, 1.0)
