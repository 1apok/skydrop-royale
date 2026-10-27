class_name Foliage
extends Node3D
## Trees, rocks and bushes as chunked MultiMeshes with harvestable collision bodies.

const CHUNK := 100.0

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var meshes := {}           # type -> Mesh
var mm_nodes := {}         # "type:cx:cz" -> MultiMeshInstance3D
var items: Array = []      # harvestable records
var grass_node: MultiMeshInstance3D
var grass_mat: ShaderMaterial
var foliage_mat: ShaderMaterial
var rock_mat: StandardMaterial3D

const TYPES := {
	"pine": {"hp": 200, "mat": "wood", "radius": 0.45, "height": 7.0},
	"oak": {"hp": 250, "mat": "wood", "radius": 0.55, "height": 6.0},
	"palm": {"hp": 150, "mat": "wood", "radius": 0.35, "height": 7.0},
	"birch": {"hp": 150, "mat": "wood", "radius": 0.35, "height": 6.0},
	"rock_a": {"hp": 300, "mat": "stone", "radius": 1.6, "height": 2.0},
	"rock_b": {"hp": 450, "mat": "stone", "radius": 2.4, "height": 3.0},
	"bush": {"hp": 0, "mat": "", "radius": 0.0, "height": 1.0},
}


func setup(t: Terrain, seed_value: int) -> void:
	terrain = t
	rng.seed = seed_value + 99
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	rock_mat = MeshKit.material_vc(0.9)
	_build_meshes()
	_scatter()
	_build_grass()


func _build_meshes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	# Pine
	var st := MeshKit.begin()
	MeshKit.cylinder(st, Vector3.ZERO, Vector3(0, 2.4, 0), 0.32, 0.22, 7, Color(0.36, 0.24, 0.15))
	var y := 1.6
	var rad := 2.3
	for i in 4:
		MeshKit.cone(st, Vector3(0, y, 0), 2.4, rad, 9, Color(0.12, 0.34, 0.16, 1.0), Color(0.2, 0.5, 0.22, 1.0))
		y += 1.35
		rad *= 0.76
	meshes["pine"] = MeshKit.finish(st)
	# Oak / broadleaf
	st = MeshKit.begin()
	MeshKit.cylinder(st, Vector3.ZERO, Vector3(0, 3.0, 0), 0.42, 0.3, 7, Color(0.38, 0.27, 0.17))
	MeshKit.cylinder(st, Vector3(0, 2.4, 0), Vector3(1.0, 3.6, 0.3), 0.18, 0.1, 5, Color(0.38, 0.27, 0.17))
	MeshKit.cylinder(st, Vector3(0, 2.6, 0), Vector3(-0.8, 3.8, -0.5), 0.18, 0.1, 5, Color(0.38, 0.27, 0.17))
	for i in 6:
		var a := TAU * i / 6.0
		var c := Vector3(cos(a) * 1.3, 4.0 + r.randf_range(-0.3, 0.6), sin(a) * 1.3)
		MeshKit.blob(st, c, Vector3.ONE * r.randf_range(1.3, 1.7), Color(0.24, 0.5, 0.17, 1.0), r, 0.2, 5, 8)
	MeshKit.blob(st, Vector3(0, 5.2, 0), Vector3(1.8, 1.5, 1.8), Color(0.3, 0.56, 0.2, 1.0), r, 0.2, 5, 8)
	meshes["oak"] = MeshKit.finish(st)
	# Birch
	st = MeshKit.begin()
	MeshKit.cylinder(st, Vector3.ZERO, Vector3(0, 4.5, 0), 0.22, 0.15, 6, Color(0.92, 0.9, 0.86))
	for i in 4:
		var a2 := TAU * i / 4.0 + 0.4
		MeshKit.blob(st, Vector3(cos(a2) * 0.7, 4.2 + i * 0.4, sin(a2) * 0.7), Vector3(1.1, 1.3, 1.1), Color(0.55, 0.72, 0.24, 1.0), r, 0.22, 5, 7)
	meshes["birch"] = MeshKit.finish(st)
	# Palm
	st = MeshKit.begin()
	var prev := Vector3.ZERO
	for i in 6:
		var nxt := Vector3(sin(i * 0.25) * 0.9, (i + 1) * 1.1, 0)
		MeshKit.cylinder(st, prev, nxt, 0.28 - i * 0.02, 0.26 - i * 0.02, 6, Color(0.55, 0.42, 0.28) if i % 2 == 0 else Color(0.48, 0.36, 0.24), false)
		prev = nxt
	for i in 8:
		var a3 := TAU * i / 8.0
		var dir := Vector3(cos(a3), 0, sin(a3))
		var side := dir.cross(Vector3.UP)
		var p0 := prev
		var p1 := prev + dir * 1.6 + Vector3.UP * 0.5
		var p2 := prev + dir * 3.2 - Vector3.UP * 0.6
		var lc := Color(0.25, 0.55, 0.18, 1.0)
		MeshKit.quad(st, p0 - side * 0.15, p0 + side * 0.15, p1 + side * 0.55, p1 - side * 0.55, lc)
		MeshKit.quad(st, p1 - side * 0.55, p1 + side * 0.55, p2 + side * 0.08, p2 - side * 0.08, lc.lightened(0.1))
	meshes["palm"] = MeshKit.finish(st)
	# Rocks
	st = MeshKit.begin()
	MeshKit.blob(st, Vector3(0, 0.5, 0), Vector3(1.8, 1.4, 1.5), Color(0.5, 0.49, 0.47), r, 0.3, 5, 8, 0.12)
	meshes["rock_a"] = MeshKit.finish(st)
	st = MeshKit.begin()
	MeshKit.blob(st, Vector3(0, 0.8, 0), Vector3(2.6, 2.2, 2.3), Color(0.45, 0.44, 0.43), r, 0.32, 6, 9, 0.12)
	MeshKit.blob(st, Vector3(1.6, 0.3, 1.0), Vector3(1.2, 0.9, 1.0), Color(0.52, 0.5, 0.48), r, 0.3, 4, 7, 0.1)
	meshes["rock_b"] = MeshKit.finish(st)
	# Bush
	st = MeshKit.begin()
	for i in 4:
		var a4 := TAU * i / 4.0
		MeshKit.blob(st, Vector3(cos(a4) * 0.6, 0.6, sin(a4) * 0.6), Vector3(0.9, 0.75, 0.9), Color(0.22, 0.45, 0.15, 1.0), r, 0.25, 4, 7)
	meshes["bush"] = MeshKit.finish(st)


func _scatter() -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.012
	var placed := {}
	for type in ["pine", "oak", "birch", "palm", "rock_a", "rock_b", "bush"]:
		placed[type] = []
	var attempts := 9000
	for i in attempts:
		var x := rng.randf_range(-Terrain.HALF, Terrain.HALF)
		var z := rng.randf_range(-Terrain.HALF, Terrain.HALF)
		var h := terrain.height_at(x, z)
		if h < 0.8:
			continue
		if not terrain.poi_at(x, z, 6.0).is_empty():
			continue
		var n := terrain.normal_at(x, z)
		var f := forest.get_noise_2d(x, z)
		var type := ""
		if h < 3.0:
			if rng.randf() < 0.08 and n.y > 0.85:
				type = "palm"
		elif n.y < 0.72 or h > 48.0:
			if rng.randf() < 0.18:
				type = "rock_b" if rng.randf() < 0.5 else "rock_a"
		else:
			var dens := clampf(f * 1.8 + 0.25, 0.04, 1.0)
			if rng.randf() < dens * 0.55:
				if h > 30.0:
					type = "pine"
				else:
					var pick := rng.randf()
					type = "pine" if pick < 0.4 else ("oak" if pick < 0.75 else "birch")
			elif rng.randf() < 0.035:
				type = "rock_a" if rng.randf() < 0.7 else "rock_b"
			elif rng.randf() < 0.07:
				type = "bush"
		if type == "":
			continue
		placed[type].append(Vector3(x, h, z))
	for type in placed.keys():
		for p in placed[type]:
			_add_instance(type, p)
	for key in mm_nodes.keys():
		var mmi: MultiMeshInstance3D = mm_nodes[key]
		var arr: Array = mmi.get_meta("xforms")
		mmi.multimesh.instance_count = arr.size()
		for i in arr.size():
			mmi.multimesh.set_instance_transform(i, arr[i])
		mmi.remove_meta("xforms")


func _add_instance(type: String, p: Vector3) -> void:
	var cx := int(floor((p.x + Terrain.HALF) / CHUNK))
	var cz := int(floor((p.z + Terrain.HALF) / CHUNK))
	var key := "%s:%d:%d" % [type, cx, cz]
	var mmi: MultiMeshInstance3D
	if mm_nodes.has(key):
		mmi = mm_nodes[key]
	else:
		mmi = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[type]
		mmi.multimesh = mm
		mmi.material_override = rock_mat if type.begins_with("rock") else foliage_mat
		mmi.set_meta("xforms", [])
		mmi.visibility_range_end = 420.0
		add_child(mmi)
		mm_nodes[key] = mmi
	var s := rng.randf_range(0.8, 1.3)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
	if type.begins_with("rock"):
		basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
	var xf := Transform3D(basis, p - Vector3(0, 0.15, 0))
	var arr: Array = mmi.get_meta("xforms")
	var idx := arr.size()
	arr.append(xf)
	var info: Dictionary = TYPES[type]
	if int(info["hp"]) <= 0:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	if type.begins_with("rock"):
		var sph := SphereShape3D.new()
		sph.radius = float(info["radius"]) * s
		cs.shape = sph
		cs.position = Vector3(0, float(info["height"]) * 0.3 * s, 0)
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = float(info["radius"]) * s
		cyl.height = float(info["height"]) * s
		cs.shape = cyl
		cs.position = Vector3(0, cyl.height * 0.5, 0)
	body.add_child(cs)
	body.position = p
	add_child(body)
	var rec := {"type": type, "node": mmi, "index": idx, "hp": float(info["hp"]) * s, "max_hp": float(info["hp"]) * s, "mat": info["mat"], "body": body, "pos": p, "xf": xf, "alive": true}
	body.set_meta("harvest", items.size())
	items.append(rec)


## Called when a harvestable is hit. Returns materials gained.
func damage(id: int, amount: float) -> Dictionary:
	if id < 0 or id >= items.size():
		return {}
	var rec: Dictionary = items[id]
	if not rec["alive"]:
		return {}
	rec["hp"] = float(rec["hp"]) - amount
	var gain := int(clampf(amount * 0.22, 3.0, 12.0))
	# Little shake by squashing the instance.
	var mmi: MultiMeshInstance3D = rec["node"]
	var xf: Transform3D = rec["xf"]
	if float(rec["hp"]) <= 0.0:
		rec["alive"] = false
		mmi.multimesh.set_instance_transform(int(rec["index"]), Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin))
		var body: StaticBody3D = rec["body"]
		body.queue_free()
		Sfx.play3d("break", xf.origin, -4.0)
		gain += 6
	else:
		var t := create_tween()
		var squash := Transform3D(xf.basis.scaled(Vector3(1.06, 0.97, 1.06)), xf.origin)
		mmi.multimesh.set_instance_transform(int(rec["index"]), squash)
		t.tween_callback(func(): if rec["alive"]: mmi.multimesh.set_instance_transform(int(rec["index"]), xf)).set_delay(0.08)
	return {String(rec["mat"]): gain}


func nearest_harvestable(pos: Vector3, max_dist: float, mat := "") -> int:
	var best := -1
	var bd := max_dist * max_dist
	for i in items.size():
		var rec: Dictionary = items[i]
		if not rec["alive"]:
			continue
		if mat != "" and rec["mat"] != mat:
			continue
		var d := pos.distance_squared_to(rec["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func set_view_distance(d: float) -> void:
	for mmi in mm_nodes.values():
		(mmi as MultiMeshInstance3D).visibility_range_end = minf(d, 520.0)


# --- grass -------------------------------------------------------------------

func _build_grass() -> void:
	var st := MeshKit.begin()
	var gr := RandomNumberGenerator.new()
	gr.seed = 11
	# A tuft of thin tapered blades with random lean.
	for i in 7:
		var a := gr.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * gr.randf_range(0.0, 0.18)
		var side := Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)) * 0.035
		var lean := Vector3(cos(a), 0, sin(a)) * gr.randf_range(0.05, 0.22)
		var h := gr.randf_range(0.35, 0.65)
		var mid := base + lean * 0.4 + Vector3(0, h * 0.55, 0)
		var tip := base + lean + Vector3(0, h, 0)
		var c := Color(1, 1, 1)
		MeshKit.quad(st, base - side, base + side, mid + side * 0.7, mid - side * 0.7, c)
		MeshKit._tri(st, mid - side * 0.7, mid + side * 0.7, tip, c)
	var mesh := st.commit()
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	var ht := ImageTexture.create_from_image(terrain.height_image)
	var sp := ImageTexture.create_from_image(terrain.splat_image)
	grass_mat.set_shader_parameter("height_map", ht)
	grass_mat.set_shader_parameter("splat_map", sp)
	grass_mat.set_shader_parameter("map_size", Terrain.SIZE + Terrain.STEP)
	grass_node = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	grass_node.multimesh = mm
	grass_node.material_override = grass_mat
	grass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass_node.custom_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 400, 4000))
	add_child(grass_node)


func set_grass_quality(q: int) -> void:
	if grass_node == null:
		return
	var counts := [0, 6000, 12000, 22000]
	var radii := [20.0, 28.0, 36.0, 48.0]
	var n: int = counts[clampi(q, 0, 3)]
	var radius: float = radii[clampi(q, 0, 3)]
	grass_node.visible = n > 0
	grass_mat.set_shader_parameter("radius", radius)
	var mm := grass_node.multimesh
	mm.instance_count = n
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in n:
		var s := r.randf_range(0.7, 1.4)
		var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.7, 1.3), s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(r.randf_range(-radius, radius), 0, r.randf_range(-radius, radius))))


func update_camera(pos: Vector3) -> void:
	if grass_mat:
		grass_mat.set_shader_parameter("cam_pos", pos)
