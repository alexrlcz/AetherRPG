class_name PlaceholderSfx
## Synthesised stand-in combat sounds, generated once and cached, used until
## real sound files are assigned (ImpactFeedbackComponent's AudioStream
## exports). Deterministic: same sound every run.

const MIX_RATE := 22050

static var _cache: Dictionary = {}


## Meaty hit: a falling low thump under a short noise crack.
static func hit(heavy: bool) -> AudioStreamWAV:
	var key := "hit_heavy" if heavy else "hit_light"
	if not _cache.has(key):
		var duration := 0.28 if heavy else 0.16
		var start_hz := 150.0 if heavy else 210.0
		var end_hz := 45.0 if heavy else 80.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 if heavy else 3
		var phase := 0.0
		var samples := PackedFloat32Array()
		samples.resize(int(duration * MIX_RATE))
		for i in samples.size():
			var t := float(i) / MIX_RATE
			var k := t / duration
			phase += TAU * lerpf(start_hz, end_hz, sqrt(k)) / MIX_RATE
			var thump := sin(phase) * exp(-k * 5.0)
			var crack := rng.randf_range(-1.0, 1.0) * exp(-t * (55.0 if heavy else 80.0))
			samples[i] = thump * 0.8 + crack * 0.55
		_cache[key] = _to_wav(samples)
	return _cache[key]


## Swing whoosh: noise swept through a moving low-pass, swelling and fading.
static func whoosh(heavy: bool) -> AudioStreamWAV:
	var key := "whoosh_heavy" if heavy else "whoosh_light"
	if not _cache.has(key):
		var duration := 0.26 if heavy else 0.18
		var rng := RandomNumberGenerator.new()
		rng.seed = 11 if heavy else 5
		var low := 0.0
		var samples := PackedFloat32Array()
		samples.resize(int(duration * MIX_RATE))
		for i in samples.size():
			var k := float(i) / samples.size()
			var cutoff := lerpf(0.04, 0.22, sin(k * PI))
			low += (rng.randf_range(-1.0, 1.0) - low) * cutoff
			samples[i] = low * sin(k * PI) * 1.8
		_cache[key] = _to_wav(samples)
	return _cache[key]


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
