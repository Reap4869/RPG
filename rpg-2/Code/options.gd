extends Button

@export var normal_text: String = "Normal Text"
@export var hover_text: String = "Hover Text"

@onready var audio_file: AudioStreamPlayer = $AudioStreamPlayer

var is_b_hovered := false

func _ready() -> void:
	self.text = normal_text

func _on_pressed() -> void:
	print("Options Button pressed!")

func _on_mouse_entered() -> void:
	is_b_hovered = true
	if Input.is_key_pressed(KEY_CTRL):
		text = hover_text
	
func _on_mouse_exited() -> void:
	is_b_hovered = false
	text = normal_text

func _unhandled_input(event: InputEvent) -> void:
	if not is_b_hovered:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_CTRL:
		self.text = hover_text
	elif not event.pressed and event.keycode == KEY_CTRL:
			text = normal_text

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		audio_file.play()
