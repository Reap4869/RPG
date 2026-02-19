extends Node
class_name CombatInput

signal cursor_moved(new_cell: Vector2i)
signal confirm(cell: Vector2i)
signal cancel()

@export var initial_repeat_delay := 0.25
@export var repeat_interval := 0.08
@export var analog_deadzone := 0.5
@export var analog_repeat_delay := 0.15

var current_cell: Vector2i = Vector2i.ZERO
var _repeat_timer := 0.0
var _axis_last := Vector2.ZERO
var _using_analog := false
var global_position: Vector2i

@onready var map_manager = get_tree().get_first_node_in_group("MapManager")
@onready var game = get_tree().get_first_node_in_group("Game")
@onready var selector = get_tree().get_first_node_in_group("CellHighlights") # or your selector node

func _ready() -> void:
	# Make sure the node exists in scene and is ready
	if map_manager == null:
		print("[CombatInput] Warning: MapManager missing")
	if game == null:
		print("[CombatInput] Warning: Game missing")

func set_cursor_cell(cell: Vector2i) -> void:
	current_cell = cell
	_draw_cursor()
	emit_signal("cursor_moved", current_cell)

func _draw_cursor() -> void:
	# Prefer using your Selector node; if you have a selector API, call it.
	# Fallback: position a visual using map_manager.cell_to_world
	if selector and selector.has_method("set_cursor"):
		selector.set_cursor(current_cell)
	else:
		# Example: move this node to the world pos for debug
		if map_manager:
			global_position = map_manager.cell_to_world(current_cell)

func _process(delta: float) -> void:
	# Keep the TurnState check so the cursor freezes during enemy turns
	if Globals.current_state != Globals.TurnState.PLAYER_TURN: return

	_handle_direction_input(delta)
	_handle_confirm_cancel()

func _handle_direction_input(delta: float) -> void:
	# Digital (WASD/arrow keys) via actions: move_up/move_down/move_left/move_right
	var dir_vec := Vector2.ZERO
	dir_vec.x = int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	dir_vec.y = int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))

	# Analog (joystick axes) example: use Input.get_vector or direct axis
	var analog := Input.get_vector("move_left", "move_right", "move_up", "move_down") # remap in Input Map
	# If you use separate axis mappings change to Input.get_action_strength checks
	if analog.length() > analog_deadzone:
		_using_analog = true
		dir_vec = analog
	else:
		_using_analog = false

	if dir_vec == Vector2.ZERO:
		_repeat_timer = 0.0
		_axis_last = Vector2.ZERO
		return

	# On initial press (or axis cross), move immediately then start repeat
	if _repeat_timer <= 0.0 or (_using_analog and _axis_last != dir_vec):
		_move_cursor_by_direction(dir_vec)
		_repeat_timer = initial_repeat_delay
		_axis_last = dir_vec
	else:
		_repeat_timer -= delta
		if _repeat_timer <= 0.0:
			_move_cursor_by_direction(dir_vec)
			_repeat_timer = repeat_interval

func _move_cursor_by_direction(dir_vec: Vector2) -> void:
	# Convert vector to integer step. Prefer cardinal priority when both pressed.
	var step := Vector2i.ZERO
	if abs(dir_vec.x) > 0.5 and abs(dir_vec.y) > 0.5:
		# diagonal -> choose dominant axis or allow diagonal if desired
		if abs(dir_vec.x) > abs(dir_vec.y):
			step.x = sign(dir_vec.x)
		else:
			step.y = sign(dir_vec.y)
	else:
		step.x = int(sign(dir_vec.x))
		step.y = int(sign(dir_vec.y))

	if step == Vector2i.ZERO:
		return

	var target = current_cell + step
	# clamp to map bounds
	if map_manager and not map_manager.is_within_bounds(target):
		return
	set_cursor_cell(target)

func _handle_confirm_cancel() -> void:
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("ui_accept"):
		emit_signal("confirm", current_cell)
	if Input.is_action_just_pressed("cancel") or Input.is_action_just_pressed("ui_cancel"):
		emit_signal("cancel")
