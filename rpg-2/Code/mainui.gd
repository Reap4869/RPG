extends Control

# This signal now tells the Game WHICH attack index was clicked
signal attack_requested(index: int)
signal end_turn_requested

@onready var skill_bar: GridContainer = %SkillBar
@onready var end_turn_button: Button = %EndTurn
@onready var gm_tools: CheckBox = %GMTools

func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	gm_tools.toggled.connect(_on_gm_toggle_toggled)
	skill_bar.attack_requested.connect(_on_attack_requested)

func _on_end_turn_pressed() -> void:
	end_turn_requested.emit()

func _on_gm_toggle_toggled(button_pressed: bool) -> void:
	Globals.gm_mode = button_pressed
	print("GM Tools ON")

func _on_attack_requested(index: int) -> void:
	attack_requested.emit(index)

func update_buttons(unit: Unit) -> void:
	# Simply tell the skill buttons node to refresh itself
	skill_bar.update_buttons(unit)
