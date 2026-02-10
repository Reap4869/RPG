extends RefCounted
class_name SkillAction

# This is called by Game.gd when the attack connects
func execute_skill(_attacker: Unit, _victim: Unit, _target_cell: Vector2i, _attack: AttackResource, _game: Node) -> void:
	pass
