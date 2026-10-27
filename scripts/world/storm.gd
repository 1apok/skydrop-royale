class_name Storm
extends Node3D
## Shrinking safe zone with phases, damage and visuals.

# [wait seconds, shrink seconds, end radius, damage per second]
const PHASES := [
	[50.0, 40.0, 240.0, 1.0],
	[40.0, 35.0, 150.0, 2.0],
	[35.0, 30.0, 90.0, 4.0],
	[30.0, 25.0, 50.0, 6.0],
	[25.0, 20.0, 24.0, 8.0],
	[20.0, 20.0, 8.0, 10.0],
	[15.0, 25.0, 0.0, 12.0],
]

var center := Vector2.ZERO
var radius := 520.0
var next_center := Vector2.ZERO
var next_radius := 520.0
var _from_center := Vector2.ZERO
var _from_radius := 520.0
var phase_i := -1
var timer := 0.0
var shrinking := false
var damage := 1.0
var active := false
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var wall: MeshInstance3D
var _mat: ShaderMaterial


func setup(t: Terrain, seed_value: int) -> void:
	terrain = t
	rng.seed = seed_value + 5
	center = Vector2.ZERO
	radius = 520.0
	next_center = center
	next_radius = radius
	wall = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	wall.mesh = cm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/storm.gdshader")
	var nt := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.02
	n.fractal_octaves = 4
	nt.noise = n
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	_mat.set_shader_parameter("noise_tex", nt)
	wall.material_override = _mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	add_child(wall)
	_update_wall()


func start() -> void:
	active = true
	_next_phase()


func _next_phase() -> void:
	phase_i += 1
	if phase_i >= PHASES.size():
		shrinking = false
		timer = 9999.0
		return
	var ph: Array = PHASES[phase_i]
	_from_center = center
	_from_radius = radius
	next_radius = float(ph[2])
	# Pick the next center inside the current circle, on land.
	var best := center
	for i in 40:
		var a := rng.randf() * TAU
		var d := rng.randf() * maxf(radius - next_radius, 0.0) * (0.85 if phase_i > 0 else 0.4)
		var c := center + Vector2(cos(a), sin(a)) * d
		if terrain.is_land(c.x, c.y, 1.5) and terrain.height_at(c.x, c.y) < 45.0:
			best = c
			break
	next_center = best
	damage = float(ph[3])
	shrinking = false
	timer = float(ph[0])


func _process(delta: float) -> void:
	if not active:
		return
	timer -= delta
	if not shrinking:
		if timer <= 0.0 and phase_i < PHASES.size():
			shrinking = true
			timer = float(PHASES[phase_i][1])
	else:
		var total := float(PHASES[phase_i][1])
		var k := 1.0 - clampf(timer / total, 0.0, 1.0)
		center = _from_center.lerp(next_center, k)
		radius = lerpf(_from_radius, next_radius, k)
		if timer <= 0.0:
			center = next_center
			radius = next_radius
			_next_phase()
	_update_wall()


func _update_wall() -> void:
	var r := maxf(radius, 0.5)
	wall.visible = r < 470.0
	wall.scale = Vector3(r, 420.0, r)
	wall.position = Vector3(center.x, 150.0, center.y)


func is_outside(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(center) > radius


func distance_outside(p: Vector3) -> float:
	return Vector2(p.x, p.z).distance_to(center) - radius


func status_text() -> String:
	if phase_i >= PHASES.size():
		return "Финальная зона"
	var t := int(ceil(maxf(timer, 0.0)))
	var mm := t / 60
	var ss := t % 60
	if shrinking:
		return "Шторм сужается %d:%02d" % [mm, ss]
	return "Шторм через %d:%02d" % [mm, ss]
