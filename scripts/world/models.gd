class_name Models
## Procedural meshes for weapons, consumables, chests and the drop airship.

static var _cache := {}
static var _mat_vc: StandardMaterial3D
static var _mat_glow: StandardMaterial3D


static func vc_material() -> StandardMaterial3D:
	if _mat_vc == null:
		_mat_vc = MeshKit.material_vc(0.55, 0.35)
	return _mat_vc


static func glow_material() -> StandardMaterial3D:
	if _mat_glow == null:
		_mat_glow = MeshKit.material_vc(0.4, 0.2, 1.4)
		_mat_glow.emission_enabled = true
		_mat_glow.emission_on_uv2 = false
	return _mat_glow


static func weapon_mesh(id: String, rarity: int) -> Mesh:
	var key := "w:%s:%d" % [id, rarity]
	if _cache.has(key):
		return _cache[key]
	var st := MeshKit.begin()
	var dark := Color(0.16, 0.17, 0.19)
	var mid := Color(0.32, 0.33, 0.36)
	var acc: Color = Items.RARITY_COLORS[rarity]
	# Weapons point toward -Z, grip at origin.
	match id:
		"ar":
			MeshKit.box(st, Vector3(0, 0.05, -0.25), Vector3(0.09, 0.14, 0.6), dark)
			MeshKit.box(st, Vector3(0, 0.08, -0.75), Vector3(0.05, 0.05, 0.5), mid)
			MeshKit.box(st, Vector3(0, -0.08, -0.12), Vector3(0.07, 0.2, 0.08), dark)
			MeshKit.box(st, Vector3(0, -0.06, -0.36), Vector3(0.06, 0.22, 0.1), acc)
			MeshKit.box(st, Vector3(0, 0.03, 0.17), Vector3(0.08, 0.13, 0.3), acc.darkened(0.2))
			MeshKit.box(st, Vector3(0, 0.16, -0.3), Vector3(0.05, 0.05, 0.18), mid)
		"smg":
			MeshKit.box(st, Vector3(0, 0.05, -0.15), Vector3(0.09, 0.13, 0.42), dark)
			MeshKit.box(st, Vector3(0, 0.07, -0.47), Vector3(0.05, 0.05, 0.22), mid)
			MeshKit.box(st, Vector3(0, -0.12, -0.05), Vector3(0.06, 0.24, 0.07), acc)
			MeshKit.box(st, Vector3(0, -0.06, 0.08), Vector3(0.07, 0.14, 0.07), dark)
			MeshKit.box(st, Vector3(0, 0.05, 0.14), Vector3(0.05, 0.05, 0.16), acc.darkened(0.2))
		"pump":
			MeshKit.box(st, Vector3(0, 0.06, -0.3), Vector3(0.1, 0.12, 0.5), dark)
			MeshKit.box(st, Vector3(0, 0.1, -0.8), Vector3(0.07, 0.07, 0.55), mid)
			MeshKit.box(st, Vector3(0, 0.0, -0.75), Vector3(0.1, 0.08, 0.28), acc)
			MeshKit.box(st, Vector3(0, -0.05, 0.12), Vector3(0.08, 0.16, 0.34), acc.darkened(0.35))
		"sniper":
			MeshKit.box(st, Vector3(0, 0.05, -0.3), Vector3(0.09, 0.13, 0.7), dark)
			MeshKit.box(st, Vector3(0, 0.07, -1.0), Vector3(0.045, 0.045, 0.75), mid)
			MeshKit.box(st, Vector3(0, 0.19, -0.3), Vector3(0.07, 0.08, 0.36), dark)
			MeshKit.box(st, Vector3(0, 0.19, -0.49), Vector3(0.09, 0.1, 0.04), acc)
			MeshKit.box(st, Vector3(0, -0.02, 0.22), Vector3(0.08, 0.17, 0.36), acc.darkened(0.2))
		"pistol":
			MeshKit.box(st, Vector3(0, 0.07, -0.12), Vector3(0.06, 0.09, 0.28), dark)
			MeshKit.box(st, Vector3(0, -0.06, -0.02), Vector3(0.05, 0.17, 0.07), acc)
	var m := MeshKit.finish(st)
	_cache[key] = m
	return m


static func consumable_mesh(id: String) -> Mesh:
	var key := "c:" + id
	if _cache.has(key):
		return _cache[key]
	var st := MeshKit.begin()
	var c: Color = Items.CONSUMABLE_COLORS[id]
	match id:
		"bandage":
			MeshKit.cylinder(st, Vector3(0, 0, 0), Vector3(0, 0.12, 0), 0.12, 0.12, 10, c)
			MeshKit.cylinder(st, Vector3(0, 0.02, 0), Vector3(0, 0.1, 0), 0.125, 0.125, 10, Color(0.9, 0.3, 0.3), false)
		"medkit":
			MeshKit.box(st, Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.3), Color(0.95, 0.95, 0.95))
			MeshKit.box(st, Vector3(0, 0.15, 0.155), Vector3(0.2, 0.06, 0.01), c)
			MeshKit.box(st, Vector3(0, 0.15, 0.155), Vector3(0.06, 0.2, 0.01), c)
		"mini_shield":
			MeshKit.cylinder(st, Vector3.ZERO, Vector3(0, 0.25, 0), 0.08, 0.08, 10, c)
			MeshKit.cylinder(st, Vector3(0, 0.25, 0), Vector3(0, 0.32, 0), 0.04, 0.04, 8, Color(0.9, 0.9, 0.9))
		"big_shield":
			MeshKit.cylinder(st, Vector3.ZERO, Vector3(0, 0.45, 0), 0.14, 0.12, 12, c)
			MeshKit.cylinder(st, Vector3(0, 0.45, 0), Vector3(0, 0.55, 0), 0.06, 0.06, 8, Color(0.9, 0.9, 0.9))
	var m := MeshKit.finish(st)
	_cache[key] = m
	return m


static func ammo_mesh(id: String) -> Mesh:
	var key := "a:" + id
	if _cache.has(key):
		return _cache[key]
	var st := MeshKit.begin()
	var c: Color = Items.AMMO_COLORS[id]
	MeshKit.box(st, Vector3(0, 0.12, 0), Vector3(0.4, 0.24, 0.26), Color(0.25, 0.3, 0.22))
	MeshKit.box(st, Vector3(0, 0.25, 0), Vector3(0.42, 0.04, 0.28), c)
	var m := MeshKit.finish(st)
	_cache[key] = m
	return m


static func mat_mesh(id: String) -> Mesh:
	var key := "m:" + id
	if _cache.has(key):
		return _cache[key]
	var st := MeshKit.begin()
	match id:
		"wood":
			for i in 3:
				MeshKit.box(st, Vector3(0, 0.08 + i * 0.12, 0), Vector3(0.6, 0.1, 0.18), Color(0.7, 0.5, 0.3).darkened(i * 0.05), Transform3D(Basis(Vector3.UP, i * 0.6), Vector3.ZERO))
		"stone":
			for i in 3:
				MeshKit.box(st, Vector3((i - 1) * 0.18, 0.12, 0), Vector3(0.16, 0.24, 0.3), Color(0.62, 0.6, 0.58))
		"metal":
			MeshKit.box(st, Vector3(0, 0.06, 0), Vector3(0.55, 0.12, 0.3), Color(0.6, 0.65, 0.7))
			MeshKit.box(st, Vector3(0, 0.18, 0), Vector3(0.45, 0.1, 0.25), Color(0.55, 0.6, 0.66))
	var m := MeshKit.finish(st)
	_cache[key] = m
	return m


static func chest_meshes() -> Array:
	if _cache.has("chest"):
		return _cache["chest"]
	var gold := Color(0.95, 0.72, 0.2)
	var wood := Color(0.5, 0.3, 0.16)
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 0.65), wood)
	MeshKit.box(st, Vector3(0, 0.3, 0.33), Vector3(1.14, 0.12, 0.02), gold)
	MeshKit.box(st, Vector3(-0.5, 0.3, 0), Vector3(0.08, 0.62, 0.68), gold)
	MeshKit.box(st, Vector3(0.5, 0.3, 0), Vector3(0.08, 0.62, 0.68), gold)
	var body := MeshKit.finish(st)
	st = MeshKit.begin()
	# Lid pivots at its back edge (z = -0.33).
	MeshKit.box(st, Vector3(0, 0.12, 0.33), Vector3(1.12, 0.24, 0.67), wood.lightened(0.05))
	MeshKit.box(st, Vector3(0, 0.25, 0.33), Vector3(1.14, 0.04, 0.69), gold)
	MeshKit.box(st, Vector3(0, 0.08, 0.68), Vector3(0.16, 0.16, 0.04), gold.lightened(0.2))
	var lid := MeshKit.finish(st)
	_cache["chest"] = [body, lid]
	return _cache["chest"]


static func airship_mesh() -> Mesh:
	if _cache.has("airship"):
		return _cache["airship"]
	var st := MeshKit.begin()
	var r := RandomNumberGenerator.new()
	r.seed = 3
	MeshKit.blob(st, Vector3.ZERO, Vector3(6, 6, 22), Color(0.2, 0.55, 0.95), r, 0.0, 10, 16, 0.0)
	for i in 6:
		var z := -14.0 + i * 5.6
		MeshKit.box(st, Vector3(0, 0, z), Vector3(12.2, 12.2, 0.6), Color(0.95, 0.85, 0.3) if i % 2 == 0 else Color(0.95, 0.95, 0.98), Transform3D(Basis(Vector3.FORWARD, PI * 0.25), Vector3.ZERO))
	MeshKit.box(st, Vector3(0, -7.2, 0), Vector3(3.2, 2.4, 9.0), Color(0.85, 0.3, 0.25))
	MeshKit.box(st, Vector3(0, -6.2, 0), Vector3(0.3, 1.0, 8.0), Color(0.3, 0.3, 0.3))
	for s in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 4.5, 0, 18), Vector3(6, 0.4, 3.5), Color(0.95, 0.85, 0.3))
	MeshKit.box(st, Vector3(0, 4.5, 18), Vector3(0.4, 6, 3.5), Color(0.95, 0.85, 0.3))
	var m := MeshKit.finish(st)
	_cache["airship"] = m
	return m


static func glider_mesh(col: Color) -> Mesh:
	var key := "g:%s" % col.to_html()
	if _cache.has(key):
		return _cache[key]
	var st := MeshKit.begin()
	var pts := []
	for i in 7:
		var a := lerpf(-1.1, 1.1, i / 6.0)
		pts.append(Vector3(sin(a) * 2.2, cos(a) * 1.2, 0))
	for i in 6:
		var c := col if i % 2 == 0 else col.lightened(0.5)
		MeshKit.quad(st, pts[i] + Vector3(0, 0, -0.9), pts[i + 1] + Vector3(0, 0, -0.9), pts[i + 1] + Vector3(0, 0, 0.9), pts[i] + Vector3(0, 0, 0.9), c)
		MeshKit.quad(st, pts[i] + Vector3(0, 0, 0.9), pts[i + 1] + Vector3(0, 0, 0.9), pts[i + 1] + Vector3(0, 0, -0.9), pts[i] + Vector3(0, 0, -0.9), c.darkened(0.2))
	for s in [-1.0, 1.0]:
		MeshKit.cylinder(st, Vector3(s * 2.0, 0.5, 0), Vector3(s * 0.2, -1.4, 0), 0.015, 0.015, 4, Color(0.2, 0.2, 0.2), false)
	var m := MeshKit.finish(st)
	_cache[key] = m
	return m
