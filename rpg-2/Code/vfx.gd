extends Node2D
class_name WorldVFX

var data: VisualEffectData
var current_turns: int = 0
var visual_instance: Node = null

func setup(vfx_data: VisualEffectData) -> void:
	data = vfx_data
	current_turns = data.turns_to_last
	
	visual_instance = data.effect_scene.instantiate()
	add_child(visual_instance)
	visual_instance.scale = Vector2(data.visual_scale, data.visual_scale)
	
	# FORCE START: Ensure sprites play and particles emit
	if visual_instance is AnimatedSprite2D:
		visual_instance.play("default") # Force play
	elif visual_instance is GPUParticles2D or visual_instance is CPUParticles2D:
		visual_instance.emitting = true
	
	# If it's ONE_SHOT, it kills itself.
	# If it's TURN_BASED, it waits for tick_turn.
	# If it's MANUAL or PERMANENT, it does nothing and stays on screen!
	if data.duration_type == VisualEffectData.DurationType.ONE_SHOT:
		_auto_destruct()

func _auto_destruct() -> void:
	if visual_instance is AnimatedSprite2D:
		# Double check: Is it looping? If so, we fallback to a timer
		if visual_instance.sprite_frames.get_animation_loop("default"):
			await get_tree().create_timer(1.0).timeout
		else:
			await visual_instance.animation_finished
	elif visual_instance is GPUParticles2D or visual_instance is CPUParticles2D:
		await get_tree().create_timer(visual_instance.lifetime).timeout
	else:
		await get_tree().create_timer(1.0).timeout
		
	queue_free()

func tick_turn() -> void:
	# Only care about this if we are a turn-based surface (like fire)
	if data.duration_type == VisualEffectData.DurationType.TURN_BASED:
		current_turns -= 1
		if current_turns <= 0:
			# You could play a "fade out" animation here
			queue_free()
