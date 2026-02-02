extends Control

@onready var show_paths: CheckBox = %ShowPaths
@onready var show_cells: CheckBox = %ShowCells
@onready var show_ocupancy: CheckBox = %ShowOcupancy

func _ready() -> void:
	show_paths.button_pressed = Globals.show_unit_paths
	show_paths.toggled.connect(_on_show_paths_toggled)
	
	show_cells.button_pressed = Globals.show_cell_outlines
	show_cells.toggled.connect(_on_show_cell_outlines)
	
	show_ocupancy.button_pressed = Globals.show_cell_outlines
	show_ocupancy.toggled.connect(_on_show_paths_toggled)

func _on_show_ocupancy_toggled(value: bool) -> void:
	Globals.show_cell_ocupancy = value

func _on_show_paths_toggled(value: bool) -> void:
	Globals.show_unit_paths = value

func _on_show_cell_outlines(value: bool) -> void:
	Globals.show_cell_outlines = value
	
	# NEW LOGIC: Find the CellHighlights node instead of DebugOverlay
	# Since CellHighlights is under World, we can find it via group or name
	var highlights = get_tree().get_first_node_in_group("Highlights") 
	
	# If you haven't added it to a group yet, you can also use find_child:
	if not highlights:
		highlights = get_tree().root.find_child("CellHighlights", true, false)
		
	if highlights:
		highlights.queue_redraw()
