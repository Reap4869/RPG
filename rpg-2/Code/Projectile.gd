# Projectile.gd
extends Node2D

signal arrived

var visual_instance: Node = null

func launch(vfx_data: VisualEffectData, start_pos: Vector2, end_pos: Vector2, speed: float, loop_sfx: AudioStream = null) -> void:
	if vfx_data == null:
		print("ERROR: Projectile vfx_data is NULL!")
		arrived.emit()
		queue_free()
		return
		
	global_position = start_pos
	look_at(end_pos)
	
	visual_instance = vfx_data.effect_scene.instantiate()
	add_child(visual_instance)
	visual_instance.scale = Vector2(vfx_data.visual_scale, vfx_data.visual_scale)
	
	if visual_instance is AnimatedSprite2D:
		visual_instance.play("default")
	
	# Play Looping SFX if one was provided
	if loop_sfx:
		var sfx_player = AudioStreamPlayer2D.new()
		sfx_player.stream = loop_sfx
		add_child(sfx_player)
		sfx_player.play()
	
	var distance = start_pos.distance_to(end_pos)
	var duration = distance / speed
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", end_pos, duration)
	
	await tween.finished
	arrived.emit()
	queue_free()
