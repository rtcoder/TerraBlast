extends Node3D

func play_events(events: Array) -> void:
	for event in events:
		match event.get("type", ""):
			"ShotResolved":
				if event.get("hit", false):
					var point: Array = event.position
					_explosion(Vector3(point[0], point[1], point[2]), float(event.radius))
					_tone(80.0, 0.25, true)
			"PlayerDamaged":
				_tone(240.0, 0.12)
			"TurnStarted":
				_tone(660.0, 0.1)
			"MatchEnded":
				_tone(880.0, 0.4)

func _explosion(position: Vector3, radius: float) -> void:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	visual.mesh = sphere
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.5, 0.1, 0.65)
	visual.material_override = material
	add_child(visual)
	visual.global_position = position
	var tween := create_tween().set_parallel(true)
	tween.tween_property(visual, "scale", Vector3.ONE * maxf(1, radius * 2), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(visual.queue_free)

func _tone(frequency: float, duration: float, noise: bool = false) -> void:
	# Procedural, original short cues; no external audio assets or core side effects.
	if get_child_count() > 20:
		return
	var rate := 22050
	var bytes := PackedByteArray()
	var count := int(rate * duration)
	bytes.resize(count * 2)
	for index in range(count):
		var t := float(index) / rate
		var wave := sin(TAU * frequency * t)
		if noise:
			wave = sin(index * 12.9898) * sin(index * 78.233) + wave * 0.3
		var envelope := pow(1.0 - float(index) / count, 2.0) * minf(1.0, t * 500)
		bytes.encode_s16(index * 2, int(clampf(wave * envelope * 0.22, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -8
	add_child(player)
	player.play()
	get_tree().create_timer(duration + 0.05).timeout.connect(player.queue_free)
