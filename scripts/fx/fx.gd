class_name FX
extends Node3D
## Pooled visual effects: tracers, muzzle flashes, impacts, damage numbers.

var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
var _sparks: Array[CPUParticles3D] = []
var _spark_i := 0
var _flashes: Array[OmniLight3D] = []
var _flash_i := 0
var _numbers: Array[Label3D] = []
var _num_i := 0
var _tracer_mat: StandardMaterial3D


func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.5)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.8, 0.4)
	_tracer_mat.emission_energy_multiplier = 4.0
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tm := BoxMesh.new()
	tm.size = Vector3(0.025, 0.025, 1.0)
	for i in 40:
		var t := MeshInstance3D.new()
		t.mesh = tm
		t.material_override = _tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracers.append(t)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var sm := QuadMesh.new()
	sm.size = Vector2(0.08, 0.08)
	sm.material = spark_mat
	for i in 16:
		var p := CPUParticles3D.new()
		p.mesh = sm
		p.amount = 10
		p.lifetime = 0.45
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.direction = Vector3(0, 0, 1)
		p.spread = 55.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.4
		p.local_coords = false
		add_child(p)
		_sparks.append(p)
	for i in 6:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.4)
		l.omni_range = 5.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_flashes.append(l)
	for i in 24:
		var lb := Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lb.pixel_size = 0.0018
		lb.font_size = 36
		lb.outline_size = 10
		lb.visible = false
		add_child(lb)
		_numbers.append(lb)


func tracer(from: Vector3, to: Vector3, col := Color(1.0, 0.85, 0.5)) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var t := _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var seg := minf(len, 7.0)
	t.visible = true
	t.scale = Vector3(1, 1, seg)
	t.look_at_from_position(from, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	t.global_position = from + (to - from).normalized() * seg * 0.5
	var tw := create_tween()
	tw.tween_property(t, "global_position", to - (to - from).normalized() * seg * 0.5, clampf(len / 400.0, 0.02, 0.25))
	tw.tween_callback(func(): t.visible = false)


func impact(pos: Vector3, normal: Vector3, col := Color(1.0, 0.8, 0.4)) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(pos) > 120.0 * 120.0:
		return
	var p := _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % _sparks.size()
	p.global_position = pos
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.color = col
	p.restart()
	p.emitting = true


func muzzle(pos: Vector3) -> void:
	var l := _flashes[_flash_i]
	_flash_i = (_flash_i + 1) % _flashes.size()
	l.global_position = pos
	l.light_energy = 2.5
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.06)


## kind: "hp", "shield", "head", "build"
func damage_number(pos: Vector3, amount: float, kind: String) -> void:
	var lb := _numbers[_num_i]
	_num_i = (_num_i + 1) % _numbers.size()
	lb.text = str(int(round(amount)))
	match kind:
		"shield": lb.modulate = Color(0.45, 0.8, 1.0)
		"head": lb.modulate = Color(1.0, 0.85, 0.2)
		"build": lb.modulate = Color(0.85, 0.85, 0.85)
		_: lb.modulate = Color(1, 1, 1)
	lb.font_size = 48 if kind == "head" else 36
	lb.visible = true
	lb.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "global_position", lb.global_position + Vector3(0, 1.0, 0), 0.7)
	tw.tween_property(lb, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(func(): lb.visible = false)
