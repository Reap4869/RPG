# CombatLog.gd
extends PanelContainer

@onready var rich_label: RichTextLabel = %RichTextLabel
@onready var scroll: ScrollContainer = %ScrollContainer

func _ready() -> void:
	add_to_group("CombatLog")
	# Clear any placeholder text from the editor
	rich_label.text = "" 

# Standard message (one color)
func add_message(text: String, color: Color = Color.WHITE) -> void:
	var hex = color.to_html(false)
	rich_label.append_text("[color=#%s]%s[/color]\n" % [hex, text])
	_scroll_to_bottom()

# The fancy two-color combat entry
func add_combat_entry(main_text: String, value_text: String, type_color: Color) -> void:
	var type_hex = type_color.to_html(false)
	var damage_red = Color.RED.to_html(false)
	
	var bbcode = "%s [color=#%s]%s[/color] [color=#%s]damage[/color].\n" % [
		main_text, 
		damage_red, 
		value_text, 
		type_hex
	]
	
	
	rich_label.append_text(bbcode)
	_scroll_to_bottom()

func _scroll_to_bottom() -> void:
	# Small delay to let the label update its height before scrolling
	await get_tree().process_frame 
	var scroll_bar = scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(scroll_bar.max_value)
