@tool # This allows the script to run in the editor!
extends Node2D
class_name SpawnMarker

@export var unit_data: UnitData:
	set(value):
		unit_data = value
		_update_preview()

@export var is_player: bool = false:
	set(value):
		is_player = value
		_update_preview()

@onready var preview_sprite: Sprite2D = $PreviewSprite

# This built-in function runs whenever the node is moved or changed in the editor
func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		if what == NOTIFICATION_TRANSFORM_CHANGED:
			_snap_to_grid()

func _snap_to_grid() -> void:
	# 1. Take current position and divide by 32
	var sn_x = floor(global_position.x / 32.0) * 32.0
	var sn_y = floor(global_position.y / 32.0) * 32.0
	
	# 2. Add 16 to offset it to the center of the 32x32 cell
	global_position = Vector2(sn_x + 16, sn_y + 16)

func _ready() -> void:
	# Ensure the node can receive transform notifications in the editor
	if Engine.is_editor_hint():
		set_notify_transform(true)
	
	add_to_group("SpawnMarkers")
	_update_preview()
	
	if not Engine.is_editor_hint():
		visible = false

func _update_preview() -> void:
	# This part ensures we don't crash if the sprite isn't ready yet
	if not is_inside_tree(): 
		await ready
		
	if unit_data and unit_data.sprite_sheet:
		preview_sprite.texture = unit_data.sprite_sheet
		preview_sprite.region_enabled = true
		preview_sprite.region_rect = unit_data.world_region
		preview_sprite.scale = Vector2(unit_data.visual_scale, unit_data.visual_scale)
		
		# Modulate it so you can easily tell players from enemies at a glance
		if is_player:
			preview_sprite.modulate = Color(0.5, 0.8, 1.0, 0.8) # Blueish
		else:
			preview_sprite.modulate = Color(1.0, 0.5, 0.5, 0.8) # Reddish
	else:
		# Fallback if no data is assigned yet
		preview_sprite.texture = preload("res://icon.svg") # Or any placeholder
		preview_sprite.region_enabled = false
		preview_sprite.scale = Vector2(0.2, 0.2)
		preview_sprite.modulate = Color.WHITE
