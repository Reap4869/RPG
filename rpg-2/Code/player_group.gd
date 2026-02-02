# UnitGroup.gd
extends Node2D
class_name PlayerGroup

signal player_defeated

@export var team_name: String = "Player"

func _ready() -> void:
	# This built-in signal fires whenever a child is removed (queue_free)
	child_exiting_tree.connect(_on_child_exiting)

func _on_child_exiting(_child: Node) -> void:
	# We use 'callable.call_deferred' or a quick timer because queue_free 
	# takes a moment to actually remove the node from the count.
	_check_defeat.call_deferred()

func _check_defeat() -> void:
	if is_team_defeated():
		player_defeated.emit()

func get_units() -> Array[Unit]:
	var list: Array[Unit] = []
	for child in get_children():
		if child is Unit:
			list.append(child)
	return list

func replenish_all_stamina() -> void:
	for unit in get_units():
		unit.replenish_stamina()

func is_team_defeated() -> bool:
	return get_units().size() == 0
