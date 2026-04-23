class_name ProceduralAudio
extends RefCounted
## Generates small placeholder audio streams so the game ships no
## binary assets. Used by `AudioDirector` for event cues and ambient
## loops.
##
## Cues are short 16-bit PCM `AudioStreamWAV` buffers synthesised from
## sine / square / triangle envelopes. Ambient is a longer, looping
## pink-noise + drone blend, keyed by era id so each age sounds
## subtly different.

const SAMPLE_RATE: int = 22050


static func make_cue(tag: StringName) -> AudioStreamWAV:
	match tag:
		&"letter_arrived":    return _tone(523.25, 0.08, 0.18, "sine",     0.30)
		&"seal_break":        return _tone(220.00, 0.02, 0.35, "square",   0.22)
		&"operative_burned":  return _sweep(660, 220, 0.45, 0.30)
		&"host_lost":         return _sweep(330, 110, 0.60, 0.30)
		&"mandate_offered":   return _chord([440.0, 554.37, 659.25], 0.35, 0.28)
		&"era_transition":    return _chord([196.0, 261.63, 392.0], 0.80, 0.30)
		&"unlock_surfaced":   return _tone(880.0, 0.03, 0.14, "triangle", 0.25)
		&"chronicle_seal":    return _chord([174.61, 261.63, 349.23], 1.1, 0.24)
		_:                    return _tone(440.0, 0.05, 0.18, "sine", 0.20)


static func make_ambient(era_id: StringName) -> AudioStreamWAV:
	# 4-second looping drone + pink noise wash. Frequency and noise
	# gain vary with era; higher eras sound cooler and slightly
	# brighter to hint at urbanisation.
	var f: float = 110.0
	var noise_gain: float = 0.03
	var drone_gain: float = 0.05
	match era_id:
		&"ancient_world":           f = 110.00; noise_gain = 0.020; drone_gain = 0.060
		&"classical_collapse":     f = 98.00;  noise_gain = 0.028; drone_gain = 0.055
		&"medieval_consolidation": f = 82.41;  noise_gain = 0.022; drone_gain = 0.050
		&"early_modern_fracture":  f = 123.47; noise_gain = 0.030; drone_gain = 0.045
		&"modern_era":             f = 146.83; noise_gain = 0.035; drone_gain = 0.040
	var seconds: float = 4.0
	var wav: AudioStreamWAV = _ambient_buffer(f, noise_gain, drone_gain, seconds)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(seconds * SAMPLE_RATE)
	return wav


# --- Synth primitives --------------------------------------------------------

static func _tone(freq: float, attack: float, duration: float, shape: String, gain: float) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var atk: int = clampi(int(attack * SAMPLE_RATE), 1, frames)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float
		if i < atk:
			env = float(i) / float(atk)
		else:
			env = 1.0 - float(i - atk) / float(frames - atk)
		env = clampf(env, 0.0, 1.0)
		var v: float = _osc(shape, freq, t) * gain * env
		_write_i16(data, i * 2, v)
	return _build_wav(data)


static func _sweep(f_start: float, f_end: float, duration: float, gain: float) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var phase: float = 0.0
	for i in range(frames):
		var prog: float = float(i) / float(frames)
		var f: float = lerpf(f_start, f_end, prog)
		phase += TAU * f / float(SAMPLE_RATE)
		var env: float = 1.0 - prog
		var v: float = sin(phase) * gain * env
		_write_i16(data, i * 2, v)
	return _build_wav(data)


static func _chord(freqs: Array, duration: float, gain: float) -> AudioStreamWAV:
	var frames: int = int(duration * SAMPLE_RATE)
	var atk: int = int(0.02 * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float
		if i < atk:
			env = float(i) / float(atk)
		else:
			env = 1.0 - float(i - atk) / float(frames - atk)
		env = clampf(env, 0.0, 1.0)
		var sum_v: float = 0.0
		for f in freqs:
			sum_v += sin(TAU * float(f) * t)
		sum_v = (sum_v / float(max(1, freqs.size()))) * gain * env
		_write_i16(data, i * 2, sum_v)
	return _build_wav(data)


static func _ambient_buffer(freq: float, noise_gain: float, drone_gain: float, seconds: float) -> AudioStreamWAV:
	var frames: int = int(seconds * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(freq * 1000.0)
	var last: float = 0.0
	for i in range(frames):
		var t: float = float(i) / float(SAMPLE_RATE)
		# Long fade-in and fade-out so the loop seam is less audible.
		var edge: float = minf(minf(t, seconds - t), 0.5) / 0.5
		var drone: float = sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 0.5 * t) * 0.4
		var noise: float = (rng.randf() - 0.5) * 2.0
		last = last * 0.85 + noise * 0.15  # crude low-pass toward pink
		var v: float = drone * drone_gain + last * noise_gain
		v *= edge
		_write_i16(data, i * 2, v)
	return _build_wav(data)


static func _osc(shape: String, freq: float, t: float) -> float:
	var phase: float = fmod(freq * t, 1.0)
	match shape:
		"square":   return 1.0 if phase < 0.5 else -1.0
		"triangle": return 4.0 * abs(phase - 0.5) - 1.0
		_:          return sin(TAU * phase)


static func _write_i16(buf: PackedByteArray, offset: int, value: float) -> void:
	var clamped: float = clampf(value, -1.0, 1.0)
	var i: int = int(round(clamped * 32767.0))
	buf[offset] = i & 0xFF
	buf[offset + 1] = (i >> 8) & 0xFF


static func _build_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav
