@tool
extends Node2D
class_name ObjectMarker

@export var object_data: ObjectData:
	set(value):
		object_data = value
		_update_preview()

@onready var preview_sprite: Sprite2D = $PreviewSprite

func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_TRANSFORM_CHANGED:
		_snap_to_grid()

func _snap_to_grid() -> void:
	var sn_x = floor(global_position.x / 32.0) * 32.0
	var sn_y = floor(global_position.y / 32.0) * 32.0
	global_position = Vector2(sn_x + 16, sn_y + 16)

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	add_to_group("ObjectMarkers")
	_update_preview()
	if not Engine.is_editor_hint():
		visible = false

func _update_preview() -> void:
	if not is_inside_tree(): await ready
	if object_data and object_data.sprite_texture:
		preview_sprite.texture = object_data.sprite_texture
		preview_sprite.region_enabled = true
		preview_sprite.region_rect = object_data.world_region
		preview_sprite.scale = Vector2(object_data.visual_scale, object_data.visual_scale)
		preview_sprite.modulate = Color(1, 1, 1, 0.8)
