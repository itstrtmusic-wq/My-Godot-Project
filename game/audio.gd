extends RefCounted


static func tone(length: float, frequency: float, fall: float, noise: float, noise_seed: int) -> AudioStreamWAV:
	const RATE := 22050
	var random := RandomNumberGenerator.new()
	random.seed = noise_seed
	var samples := int(length * RATE)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var phase := 0.0
	var filtered := 0.0
	for index in range(samples):
		var time := float(index) / RATE
		phase += TAU * (frequency / (1.0 + fall * time)) / RATE
		filtered = lerpf(filtered, random.randf_range(-1.0, 1.0), 0.45)
		var envelope := minf(time * 600.0, 1.0) * pow(1.0 - time / length, 2.2)
		var value := ((sin(phase) + sin(phase * 2.07) * 0.2) * (1.0 - noise) + noise * filtered) * envelope
		pcm.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 28500.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	sound.data = pcm
	return sound


static func breeze() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 6.0
	var pcm := PackedByteArray()
	var samples := int(DURATION * RATE)
	pcm.resize(samples * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 3910
	var soft := 0.0
	var tail := 0.0
	for index in range(samples):
		var time := float(index) / RATE
		soft = lerpf(soft, random.randf_range(-1.0, 1.0), 0.07)
		tail = lerpf(tail, soft, 0.085)
		var gust := (0.49 + 0.27 * cos(TAU * time / DURATION) + 0.13 * sin(TAU * time / (DURATION * 0.5)))
		var seam := smoothstep(0.0, 0.12, minf(time, DURATION - time))
		pcm.encode_s16(index * 2, int(tail * gust * seam * 20500.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	sound.data = pcm
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = samples
	return sound
