extends Node

# This creates a pool of players so sounds don't cut each other off
var pool_size = 8
var pool = []
var next_player = 0

func _ready() -> void:
	for i in range(pool_size):
		var p = AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)

func play_sfx(stream: AudioStream, pitch_range: float = 0.1) -> void:
	var p = pool[next_player]
	p.stream = stream
	# Add a little variety to the pitch so footsteps don't sound robotic
	p.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
	p.play()
	
	next_player = (next_player + 1) % pool_size
