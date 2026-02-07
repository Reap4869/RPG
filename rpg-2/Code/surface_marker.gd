@tool
extends Node2D
class_name SurfaceMarker

@export var surface_type: Globals.SurfaceType = Globals.SurfaceType.NONE:
	set(value):
		surface_type = value
		_update_preview()

@export var duration: int = 999:
	set(value):
		duration = value

@onready var preview_sprite: Sprite2D = $PreviewSprite

func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		if what == NOTIFICATION_TRANSFORM_CHANGED:
			_snap_to_grid()

func _snap_to_grid() -> void:
	var sn_x = floor(global_position.x / 32.0) * 32.0
	var sn_y = floor(global_position.y / 32.0) * 32.0
	global_position = Vector2(sn_x + 16, sn_y + 16)

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	
	add_to_group("SurfaceMarkers")
	_update_preview()
	
	# Hide markers when the game actually runs
	if not Engine.is_editor_hint():
		visible = false

func _update_preview() -> void:
	if not is_inside_tree(): 
		await ready
		
	# Update color based on the surface type for easy editor visibility
	match surface_type:
		Globals.SurfaceType.FIRE:
			preview_sprite.modulate = Color(1.0, 0.3, 0.0, 0.7) # Orange
		Globals.SurfaceType.WATER:
			preview_sprite.modulate = Color(0.0, 0.5, 1.0, 0.7) # Blue
		Globals.SurfaceType.POISON:
			preview_sprite.modulate = Color(0.5, 0.0, 0.8, 0.7) # Purple
		#Globals.SurfaceType.OIL:
		#	preview_sprite.modulate = Color(0.2, 0.2, 0.2, 0.8) # Black/Grey
		_:
			preview_sprite.modulate = Color(1, 1, 1, 0.3) # Faint white for NONE

	# Use your engine icon or a specific "S" icon as the base
	if preview_sprite.texture == null:
		preview_sprite.texture = preload("res://icon.svg")
		preview_sprite.scale = Vector2(0.2, 0.2)
