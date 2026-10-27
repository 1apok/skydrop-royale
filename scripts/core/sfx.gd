extends Node
## Procedurally synthesized sound effects (no external audio assets) with a 3D player pool.

const RATE := 22050

var streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next := 0
var _next_2d := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1337
	streams["ar"] = _gunshot(0.22, 900.0, 0.55, 0.9)
	streams["smg"] = _gunshot(0.14, 1300.0, 0.45, 0.8)
	streams["pistol"] = _gunshot(0.18, 1100.0, 0.5, 0.85)
	streams["pump"] = _gunshot(0.45, 420.0, 0.8, 1.0)
	streams["sniper"] = _gunshot(0.75, 650.0, 0.9, 1.0, true)
	streams["pickaxe"] = _impact(0.16, 1800.0)
	streams["hit_wood"] = _impact(0.18, 700.0)
	streams["build"] = _impact(0.22, 450.0)
	streams["break"] = _noise_burst(0.5, 300.0, 0.7)
	streams["hitmarker"] = _tone([2200.0, 2800.0], 0.07, 0.5)
	streams["headshot"] = _tone([3000.0, 3800.0], 0.12, 0.55)
	streams["shield_hit"] = _tone([1400.0, 1900.0, 2500.0], 0.15, 0.35)
	streams["chest"] = _tone([880.0, 1108.0, 1318.0, 1760.0], 0.9, 0.35, true)
	streams["pickup"] = _tone([660.0, 990.0], 0.18, 0.35)
	streams["reload"] = _clicks()
	streams["heal"] = _tone([523.0, 659.0, 784.0], 0.5, 0.3, true)
	streams["step"] = _noise_burst(0.07, 1400.0, 0.25)
	streams["land"] = _noise_burst(0.2, 500.0, 0.5)
	streams["glider"] = _noise_burst(0.6, 2500.0, 0.3)
	streams["storm"] = _noise_loop(2.0, 300.0)
	streams["eliminate"] = _tone([440.0, 660.0, 880.0], 0.35, 0.4, true)
	streams["ui"] = _tone([1200.0], 0.05, 0.3)
	streams["victory"] = _tone([523.0, 659.0, 784.0, 1046.0], 1.6, 0.4, true)
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0
		p.max_distance = 180.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_pool.append(p)
	for i in 8:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool_2d.append(p2)


func play3d(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(pos) > 200.0 * 200.0:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = streams[name]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


# --- synthesis helpers -------------------------------------------------------

func _make(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s


func _gunshot(dur: float, cutoff: float, body: float, gain: float, crack := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := clampf(cutoff / RATE * 6.28, 0.01, 1.0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * (9.0 / dur))
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * a
		var thump := sin(phase) * exp(-t * 30.0) * body
		phase += TAU * lerpf(160.0, 50.0, minf(t * 8.0, 1.0)) / RATE
		var v := (lp * 1.6 + thump) * env
		if crack and t < 0.012:
			v += noise * 0.9
		if t < 0.004:
			v += noise * 0.6
		out[i] = tanh(v * 1.8) * gain
	return _make(out)


func _impact(dur: float, freq: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 28.0)
		out[i] = (sin(TAU * freq * t) * 0.4 + sin(TAU * freq * 1.47 * t) * 0.25 + _rng.randf_range(-1, 1) * 0.35 * exp(-t * 60.0)) * env
	return _make(out)


func _noise_burst(dur: float, cutoff: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := clampf(cutoff / RATE * 6.28, 0.01, 1.0)
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * a
		out[i] = lp * 2.0 * exp(-t * (6.0 / dur)) * gain
	return _make(out)


func _noise_loop(dur: float, cutoff: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := clampf(cutoff / RATE * 6.28, 0.01, 1.0)
	for i in n:
		var t := float(i) / n
		lp += (_rng.randf_range(-1, 1) - lp) * a
		out[i] = lp * 2.5 * (0.6 + 0.4 * sin(t * TAU * 2.0))
	return _make(out, true)


func _tone(freqs: Array, dur: float, gain: float, arpeggio := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if arpeggio:
			var step := dur / freqs.size()
			for k in freqs.size():
				var tt := t - k * step * 0.6
				if tt > 0.0:
					v += sin(TAU * float(freqs[k]) * tt) * exp(-tt * 5.0)
			v /= sqrt(float(freqs.size()))
		else:
			for f in freqs:
				v += sin(TAU * float(f) * t)
			v /= freqs.size()
			v *= exp(-t * (5.0 / dur))
		out[i] = v * gain
	return _make(out)


func _clicks() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for c in [0.02, 0.22, 0.4]:
			var tt: float = t - c
			if tt > 0.0:
				v += _rng.randf_range(-1, 1) * exp(-tt * 120.0) + sin(TAU * 2400.0 * tt) * exp(-tt * 80.0) * 0.5
		out[i] = v * 0.5
	return _make(out)
