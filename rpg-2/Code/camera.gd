extends Camera2D

@export var speed := 500.0
@export var edge_margin := 20.0
@export var allow_edge_panning := true

var limit_min := Vector2.ZERO
var limit_max := Vector2(10000, 10000)

func _ready() -> void:
	# Ensure the camera starts at a valid position before first frame
	_clamp_to_limits.call_deferred()

func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	
	if allow_edge_panning:
		var mouse_pos = get_viewport().get_mouse_position()
		var screen_size = get_viewport().get_visible_rect().size
		
		if mouse_pos.x < edge_margin:
			input_dir.x = -1
		elif mouse_pos.x > screen_size.x - edge_margin:
			input_dir.x = 1
			
		if mouse_pos.y < edge_margin:
			input_dir.y = -1
		elif mouse_pos.y > screen_size.y - edge_margin:
			input_dir.y = 1

	if input_dir != Vector2.ZERO:
		global_position += input_dir.normalized() * (speed / zoom.x) * delta
		_clamp_to_limits()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = (zoom + Vector2(0.1, 0.1)).clamp(Vector2(0.5, 0.5), Vector2(2, 2))
			_clamp_to_limits()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = (zoom - Vector2(0.1, 0.1)).clamp(Vector2(0.5, 0.5), Vector2(2, 2))
			_clamp_to_limits()

func force_clamp() -> void:
	_clamp_to_limits()

func _clamp_to_limits() -> void:
	var view_size = get_viewport_rect().size / zoom
	var half_view = view_size / 2.0
	
	var min_x = limit_min.x + half_view.x
	var max_x = limit_max.x - half_view.x
	var min_y = limit_min.y + half_view.y
	var max_y = limit_max.y - half_view.y
	
	if min_x > max_x:
		global_position.x = (limit_min.x + limit_max.x) / 2.0
	else:
		global_position.x = clampf(global_position.x, min_x, max_x)
		
	if min_y > max_y:
		global_position.y = (limit_min.y + limit_max.y) / 2.0
	else:
		global_position.y = clampf(global_position.y, min_y, max_y)

func apply_impact_zoom(type: Globals.ZoomType, target_pos: Vector2) -> void:
	if type == Globals.ZoomType.NONE: return

	var target_zoom_val: float = 1.0
	match type:
		Globals.ZoomType.SMALL: target_zoom_val = 1.1
		Globals.ZoomType.MID: target_zoom_val = 1.2
		Globals.ZoomType.BIG: target_zoom_val = 1.4

	var original_zoom = zoom
	var original_pos = global_position

	var tween = create_tween().set_parallel(true)
	
	# Zoom in and pan to target
	tween.tween_property(self, "zoom", Vector2(target_zoom_val, target_zoom_val), 0.15)
	tween.tween_property(self, "global_position", target_pos, 0.15)
	
	# We use a custom step to ensure clamping happens DURING the move
	tween.set_parallel(false)
	tween.tween_callback(_clamp_to_limits) 
	
	# Wait for impact duration (matches your hit stop)
	await get_tree().create_timer(0.2, true, false, true).timeout
	
	# Return to normal
	var reset = create_tween().set_parallel(true)
	reset.tween_property(self, "zoom", original_zoom, 0.3)
	reset.tween_property(self, "global_position", original_pos, 0.3)
	reset.set_parallel(false)
	reset.tween_callback(_clamp_to_limits)
