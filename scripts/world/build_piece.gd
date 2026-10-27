class_name BuildPiece
extends StaticBody3D
## A destructible building piece: wall / floor / ramp / cone (+ wall variants for houses).

const TILE := 4.0
const THICK := 0.24

const MAT_HP := {"wood": 150.0, "stone": 300.0, "metal": 500.0, "plaster": 260.0, "brick": 380.0, "steel": 600.0}
const MAT_BUILD_TIME := {"wood": 2.5, "stone": 6.0, "metal": 9.0}
const MAT_START := {"wood": 0.33, "stone": 0.25, "metal": 0.2}
const HARVEST := {"wood": "wood", "plaster": "stone", "stone": "stone", "brick": "stone", "metal": "metal", "steel": "metal"}

static var _meshes := {}
static var _shapes := {}
static var _materials := {}
static var _noise_tex: Texture2D

var piece_type := "wall"
var mat := "wood"
var hp := 100.0
var max_hp := 100.0
var target_hp := 100.0
var player_built := false
var team := -1
var grid_key := ""
var build_rate := 0.0
var world: Node
var mesh_inst: MeshInstance3D
var _dead := false


static func make(type: String, material: String, built_by_player: bool, start_full := false) -> BuildPiece:
	var p := BuildPiece.new()
	p.piece_type = type
	p.mat = material
	p.player_built = built_by_player
	p.max_hp = float(MAT_HP.get(material, 200.0))
	if built_by_player and not start_full:
		p.hp = p.max_hp * float(MAT_START.get(material, 0.3))
		p.build_rate = (p.max_hp - p.hp) / float(MAT_BUILD_TIME.get(material, 3.0))
	else:
		p.hp = p.max_hp
	p.collision_layer = 1
	p.collision_mask = 0
	p._setup()
	return p


static func ensure_noise() -> void:
	if _noise_tex != null:
		return
	var nt := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	nt.noise = n
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	nt.generate_mipmaps = true
	_noise_tex = nt


static func get_material(material: String) -> ShaderMaterial:
	if _materials.has(material):
		return _materials[material]
	ensure_noise()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/build.gdshader")
	var types := {"wood": 0, "brick": 1, "stone": 1, "metal": 2, "steel": 2, "plaster": 3}
	var cols := {
		"wood": Color(0.78, 0.58, 0.36), "brick": Color(0.78, 0.4, 0.3), "stone": Color(0.62, 0.6, 0.58),
		"metal": Color(0.66, 0.7, 0.74), "steel": Color(0.4, 0.55, 0.66), "plaster": Color(0.9, 0.86, 0.78),
	}
	m.set_shader_parameter("mat_type", types.get(material, 0))
	m.set_shader_parameter("base", cols.get(material, Color.WHITE))
	m.set_shader_parameter("noise_tex", _noise_tex)
	_materials[material] = m
	return m


func _setup() -> void:
	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = get_mesh(piece_type)
	mesh_inst.material_override = get_material(mat)
	mesh_inst.visibility_range_end = 380.0
	add_child(mesh_inst)
	for s in get_shapes(piece_type):
		var cs := CollisionShape3D.new()
		cs.shape = s["shape"]
		cs.transform = s["xf"]
		add_child(cs)
	_update_visual()
	set_process(build_rate > 0.0)


func _process(delta: float) -> void:
	if build_rate <= 0.0:
		set_process(false)
		return
	var before := hp
	hp = minf(max_hp, hp + build_rate * delta)
	if hp >= max_hp - 0.01 or before > hp:
		build_rate = 0.0
	_update_visual()


func _update_visual() -> void:
	if mesh_inst == null:
		return
	var progress := 1.0
	if build_rate > 0.0:
		progress = clampf(hp / max_hp, 0.0, 1.0)
	mesh_inst.set_instance_shader_parameter("progress", progress)
	mesh_inst.set_instance_shader_parameter("damage", 1.0 - clampf(hp / max_hp, 0.0, 1.0))


func take_damage(amount: float, _attacker = null) -> bool:
	if _dead:
		return false
	hp -= amount
	if build_rate > 0.0:
		build_rate = 0.0 # damaged pieces stop growing
		_update_visual()
	_update_visual()
	if hp <= 0.0:
		destroy()
		return true
	return false


func destroy(cascade := true) -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	if world and world.has_method("on_piece_destroyed"):
		world.on_piece_destroyed(self, cascade)
	Sfx.play3d("break", global_position + Vector3(0, 1.5, 0), -6.0)
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	var t := create_tween()
	t.tween_property(mesh_inst, "scale", Vector3(1.0, 0.02, 1.0), 0.18)
	t.tween_callback(queue_free)


func is_dead() -> bool:
	return _dead


func harvest_type() -> String:
	return String(HARVEST.get(mat, "wood"))


## World AABB (approximate, unrotated pieces use yaw only).
func world_aabb() -> AABB:
	var a: AABB = get_mesh(piece_type).get_aabb()
	return global_transform * a


# --- shared meshes / shapes ----------------------------------------------------

static func get_mesh(type: String) -> Mesh:
	if _meshes.has(type):
		return _meshes[type]
	var st := MeshKit.begin()
	var c := Color.WHITE
	match type:
		"wall":
			MeshKit.box(st, Vector3(0, TILE * 0.5, 0), Vector3(TILE, TILE, THICK), c)
		"wall_window":
			for b in _window_boxes():
				MeshKit.box(st, b[0], b[1], c)
		"wall_door":
			for b in _door_boxes():
				MeshKit.box(st, b[0], b[1], c)
		"floor":
			MeshKit.box(st, Vector3(0, 0, 0), Vector3(TILE, THICK, TILE), c)
		"ramp":
			var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(45.0)), Vector3(0, TILE * 0.5, 0))
			MeshKit.box(st, Vector3.ZERO, Vector3(TILE, THICK, TILE * sqrt(2.0)), c, xf)
			# Steps to read as stairs.
			for i in 8:
				var t := (i + 0.5) / 8.0
				var z := TILE * 0.5 - t * TILE
				MeshKit.box(st, Vector3(0, t * TILE + 0.1, z), Vector3(TILE * 0.96, 0.16, 0.16), c.darkened(0.1))
		"cone":
			var h := 1.6
			var hs := TILE * 0.5
			var top := Vector3(0, h, 0)
			var p0 := Vector3(-hs, 0, -hs)
			var p1 := Vector3(hs, 0, -hs)
			var p2 := Vector3(hs, 0, hs)
			var p3 := Vector3(-hs, 0, hs)
			MeshKit._tri(st, p0, top, p1, c)
			MeshKit._tri(st, p1, top, p2, c)
			MeshKit._tri(st, p2, top, p3, c)
			MeshKit._tri(st, p3, top, p0, c)
			MeshKit.quad(st, p0, p1, p2, p3, c)
		"crate":
			MeshKit.box(st, Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), c)
		"foundation":
			MeshKit.box(st, Vector3(0, -1.0, 0), Vector3(TILE, 2.0, TILE), c)
	var m := st.commit()
	_meshes[type] = m
	return m


static func _window_boxes() -> Array:
	var w := 1.6
	var y0 := 1.3
	var y1 := 2.7
	var side := (TILE - w) * 0.5
	return [
		[Vector3(-(w + side) * 0.5, TILE * 0.5, 0), Vector3(side, TILE, THICK)],
		[Vector3((w + side) * 0.5, TILE * 0.5, 0), Vector3(side, TILE, THICK)],
		[Vector3(0, y0 * 0.5, 0), Vector3(w, y0, THICK)],
		[Vector3(0, (y1 + TILE) * 0.5, 0), Vector3(w, TILE - y1, THICK)],
	]


static func _door_boxes() -> Array:
	var w := 1.6
	var y1 := 2.8
	var side := (TILE - w) * 0.5
	return [
		[Vector3(-(w + side) * 0.5, TILE * 0.5, 0), Vector3(side, TILE, THICK)],
		[Vector3((w + side) * 0.5, TILE * 0.5, 0), Vector3(side, TILE, THICK)],
		[Vector3(0, (y1 + TILE) * 0.5, 0), Vector3(w, TILE - y1, THICK)],
	]


static func _box_shape(center: Vector3, size: Vector3, basis := Basis()) -> Dictionary:
	var s := BoxShape3D.new()
	s.size = size
	return {"shape": s, "xf": Transform3D(basis, center)}


static func get_shapes(type: String) -> Array:
	if _shapes.has(type):
		return _shapes[type]
	var out := []
	match type:
		"wall":
			out.append(_box_shape(Vector3(0, TILE * 0.5, 0), Vector3(TILE, TILE, THICK)))
		"wall_window":
			for b in _window_boxes():
				out.append(_box_shape(b[0], b[1]))
		"wall_door":
			for b in _door_boxes():
				out.append(_box_shape(b[0], b[1]))
		"floor":
			out.append(_box_shape(Vector3.ZERO, Vector3(TILE, THICK, TILE)))
		"ramp":
			out.append(_box_shape(Vector3(0, TILE * 0.5, 0), Vector3(TILE, THICK, TILE * sqrt(2.0)), Basis(Vector3.RIGHT, deg_to_rad(45.0))))
		"cone":
			var cs := ConvexPolygonShape3D.new()
			var hs := TILE * 0.5
			cs.points = PackedVector3Array([Vector3(-hs, 0, -hs), Vector3(hs, 0, -hs), Vector3(hs, 0, hs), Vector3(-hs, 0, hs), Vector3(0, 1.6, 0)])
			out.append({"shape": cs, "xf": Transform3D.IDENTITY})
		"crate":
			out.append(_box_shape(Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2)))
		"foundation":
			out.append(_box_shape(Vector3(0, -1.0, 0), Vector3(TILE, 2.0, TILE)))
	_shapes[type] = out
	return out
