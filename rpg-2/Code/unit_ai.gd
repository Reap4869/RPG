extends Resource
class_name UnitAI

@warning_ignore("unused_signal")
signal decision_completed # The Game will listen for this

func make_decision(_unit: Unit, _game: Node, _map_manager: MapManager) -> void:
	# This is the base function
	pass
