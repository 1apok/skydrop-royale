class_name Terrain
extends Node3D
## Procedural island heightfield: generation, chunked render meshes, collision, sampling.

const SIZE := 800.0
const RES := 401
const STEP := SIZE / (RES - 1)
const HALF := SIZE * 0.5
const CHUNKS := 8

const POI_NAMES := [
	"Тихие Сосны", "Ржавый Порт", "Старая Ферма", "Обсерватория", "Пыльный Карьер",
	"Маяк", "Лесопилка", "Солнечный Двор", "Каменный Перевал", "Сонная Бухта",
]

var heights := PackedFloat32Array()
var splat := PackedColorArray()
var pois: Array = []
var rng := RandomNumberGenerator.new()
var height_image: Image
var splat_image: Image
var mountain_pos := Vector2.ZERO
var chunk_meshes: Array[MeshInstance3D] = []


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	heights.resize(RES * RES)
	splat.resize(RES * RES)

	var n_base := FastNoiseLite.new()
	n_base.seed = seed_value
	n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_base.frequency = 0.0042
	n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_base.fractal_octaves = 5
	var n_ridge := FastNoiseLite.new()
	n_ridge.seed = seed_value + 7
	n_ridge.frequency = 0.009
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_ridge.fractal_octaves = 4
	var n_shore := FastNoiseLite.new()
	n_shore.seed = seed_value + 13
	n_shore.frequency = 1.6

	var ang := rng.randf() * TAU
	mountain_pos = Vector2(cos(ang), sin(ang)) * rng.randf_range(120.0, 190.0)

	for iz in RES:
		for ix in RES:
			var x := ix * STEP - HALF
			var z := iz * STEP - HALF
			var p := Vector2(x, z)
			var a := atan2(z, x)
			var shore_r := 0.8 + n_shore.get_noise_2d(cos(a), sin(a)) * 0.12
			var d := p.length() / HALF / shore_r
			var mask := 1.0 - smoothstep(0.72, 1.0, d)
			var base := n_base.get_noise_2d(x, z) * 0.5 + 0.5
			var h := 3.0 + base * base * 26.0
			var md := p.distance_to(mountain_pos)
			var mountain := exp(-pow(md / 95.0, 2.0)) * (38.0 + n_ridge.get_noise_2d(x, z) * 16.0)
			h += maxf(mountain, 0.0)
			h = lerpf(-9.0, h, mask)
			heights[iz * RES + ix] = h

	_place_pois()
	for poi in pois:
		_flatten(poi)
	_compute_splat()
	_make_images()


func _place_pois() -> void:
	pois.clear()
	var names := POI_NAMES.duplicate()
	var tries := 0
	while pois.size() < 9 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(-HALF * 0.7, HALF * 0.7), rng.randf_range(-HALF * 0.7, HALF * 0.7))
		var h := _raw_height(p.x, p.y)
		if h < 3.0 or h > 34.0:
			continue
		if p.distance_to(mountain_pos) < 55.0:
			continue
		var ok := true
		for other in pois:
			if Vector2(other["pos"].x, other["pos"].z).distance_to(p) < 120.0:
				ok = false
				break
		if not ok:
			continue
		var r := rng.randf_range(30.0, 44.0)
		pois.append({"name": names[pois.size()], "pos": Vector3(p.x, h, p.y), "radius": r})


func _flatten(poi: Dictionary) -> void:
	var c: Vector3 = poi["pos"]
	var r: float = poi["radius"]
	var outer := r + 22.0
	# Average height in the inner area gives the plateau level.
	var sum := 0.0
	var cnt := 0
	for k in 24:
		var a := TAU * k / 24.0
		sum += _raw_height(c.x + cos(a) * r * 0.5, c.z + sin(a) * r * 0.5)
		cnt += 1
	var level := maxf(sum / cnt, 2.5)
	poi["pos"] = Vector3(c.x, level, c.z)
	var i0 := int((c.x - outer + HALF) / STEP)
	var i1 := int((c.x + outer + HALF) / STEP) + 1
	var j0 := int((c.z - outer + HALF) / STEP)
	var j1 := int((c.z + outer + HALF) / STEP) + 1
	for iz in range(maxi(j0, 0), mini(j1, RES - 1) + 1):
		for ix in range(maxi(i0, 0), mini(i1, RES - 1) + 1):
			var x := ix * STEP - HALF
			var z := iz * STEP - HALF
			var d := Vector2(x - c.x, z - c.z).length()
			if d > outer:
				continue
			var t := 1.0 - smoothstep(r, outer, d)
			var idx := iz * RES + ix
			heights[idx] = lerpf(heights[idx], level, t)


func _raw_height(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, RES - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, RES - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[iz * RES + ix]
	var h10 := heights[iz * RES + ix + 1]
	var h01 := heights[(iz + 1) * RES + ix]
	var h11 := heights[(iz + 1) * RES + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func height_at(x: float, z: float) -> float:
	return _raw_height(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	var hl := _raw_height(x - e, z)
	var hr := _raw_height(x + e, z)
	var hd := _raw_height(x, z - e)
	var hu := _raw_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func is_land(x: float, z: float, min_h := 1.5) -> bool:
	return absf(x) < HALF and absf(z) < HALF and _raw_height(x, z) > min_h


func poi_at(x: float, z: float, margin := 0.0) -> Dictionary:
	for poi in pois:
		var c: Vector3 = poi["pos"]
		if Vector2(x - c.x, z - c.z).length() < float(poi["radius"]) + margin:
			return poi
	return {}


func _compute_splat() -> void:
	for iz in RES:
		for ix in RES:
			var idx := iz * RES + ix
			var h := heights[idx]
			var x := ix * STEP - HALF
			var z := iz * STEP - HALF
			var sand := 1.0 - smoothstep(1.4, 3.2, h)
			var n := normal_at(x, z)
			var rock := smoothstep(0.62, 0.48, n.y)
			if h > 40.0:
				rock = maxf(rock, smoothstep(40.0, 48.0, h) * 0.55)
			var dirt := 0.0
			for poi in pois:
				var c: Vector3 = poi["pos"]
				var d := Vector2(x - c.x, z - c.z).length()
				dirt = maxf(dirt, 1.0 - smoothstep(float(poi["radius"]) * 0.82, float(poi["radius"]) + 6.0, d))
			var snow := smoothstep(52.0, 58.0, h)
			splat[idx] = Color(sand, rock, dirt, snow)


func _make_images() -> void:
	height_image = Image.create(RES, RES, false, Image.FORMAT_RF)
	splat_image = Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	for iz in RES:
		for ix in RES:
			var idx := iz * RES + ix
			height_image.set_pixel(ix, iz, Color(heights[idx], 0, 0))
			splat_image.set_pixel(ix, iz, splat[idx])


func build(material: Material, view_dist: float) -> void:
	var cells := (RES - 1) / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(cx * cells, cz * cells, cells)
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			chunk_meshes.append(mi)
	set_view_distance(view_dist)
	# Collision: uniformly scaled heightmap (Jolt prefers uniform scale).
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("terrain", true)
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / STEP
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(STEP, STEP, STEP)
	body.add_child(cs)
	add_child(body)


func set_view_distance(d: float) -> void:
	for mi in chunk_meshes:
		mi.visibility_range_end = d + 120.0


func _chunk_mesh(x0: int, z0: int, cells: int) -> ArrayMesh:
	var n := cells + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var gx := x0 + i
			var gz := z0 + j
			var k := j * n + i
			var x := gx * STEP - HALF
			var z := gz * STEP - HALF
			verts[k] = Vector3(x, heights[gz * RES + gx], z)
			var hl := heights[gz * RES + maxi(gx - 1, 0)]
			var hr := heights[gz * RES + mini(gx + 1, RES - 1)]
			var hd := heights[maxi(gz - 1, 0) * RES + gx]
			var hu := heights[mini(gz + 1, RES - 1) * RES + gx]
			norms[k] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			cols[k] = splat[gz * RES + gx]
	idx.resize(cells * cells * 6)
	var w := 0
	for j in cells:
		for i in cells:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Minimap image: shaded relief with water/sand/grass/rock/snow colors.
func make_map_image(size_px: int) -> Image:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.5, 0.8, -0.3).normalized()
	for py in size_px:
		for px in size_px:
			var x := (float(px) / size_px) * SIZE - HALF
			var z := (float(py) / size_px) * SIZE - HALF
			var h := _raw_height(x, z)
			var c: Color
			if h < 0.0:
				c = Color(0.1, 0.35, 0.6).lerp(Color(0.05, 0.18, 0.4), clampf(-h / 9.0, 0.0, 1.0))
			else:
				var fx := clampf((x + HALF) / STEP, 0, RES - 1)
				var fz := clampf((z + HALF) / STEP, 0, RES - 1)
				var s := splat[int(fz) * RES + int(fx)]
				c = Color(0.36, 0.6, 0.22)
				c = c.lerp(Color(0.58, 0.46, 0.32), s.b * 0.8)
				c = c.lerp(Color(0.9, 0.82, 0.6), s.r)
				c = c.lerp(Color(0.5, 0.48, 0.46), s.g)
				c = c.lerp(Color(0.95, 0.96, 1.0), s.a)
				var nrm := normal_at(x, z)
				c = c * (0.65 + 0.45 * maxf(nrm.dot(light), 0.0))
			img.set_pixel(px, py, c)
	return img
