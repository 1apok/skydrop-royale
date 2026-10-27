class_name MeshKit
## Helpers for building low-poly vertex-colored meshes procedurally.


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


## Axis-aligned box (optionally transformed) with flat shading.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, xf := Transform3D.IDENTITY) -> void:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for i in 8:
		p[i] = xf * (p[i] + center)
	quad(st, p[4], p[5], p[6], p[7], col) # +z
	quad(st, p[1], p[0], p[3], p[2], col) # -z
	quad(st, p[5], p[1], p[2], p[6], col) # +x
	quad(st, p[0], p[4], p[7], p[3], col) # -x
	quad(st, p[7], p[6], p[2], p[3], col.lightened(0.04)) # +y
	quad(st, p[0], p[1], p[5], p[4], col.darkened(0.1)) # -y


static func cylinder(st: SurfaceTool, base: Vector3, top: Vector3, r0: float, r1: float, segs: int, col: Color, cap := true) -> void:
	var axis := (top - base).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := axis.cross(side).normalized()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		quad(st, base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1, col)
		if cap and r1 > 0.001:
			_tri(st, top, top + d0 * r1, top + d1 * r1, col)


static func cone(st: SurfaceTool, base: Vector3, height: float, r: float, segs: int, col: Color, tip_col := Color(0, 0, 0, 0)) -> void:
	var tip := base + Vector3.UP * height
	var tc := col if tip_col.a == 0.0 else tip_col
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * r
		var n := (p1 - p0).cross(tip - p0).normalized()
		st.set_color(col); st.set_normal(n); st.add_vertex(p0)
		st.set_color(tc); st.set_normal(n); st.add_vertex(tip)
		st.set_color(col); st.set_normal(n); st.add_vertex(p1)
		_tri(st, base, p0, p1, col.darkened(0.3))


## Noise-displaced low-poly blob (for rocks, tree canopies, bushes).
static func blob(st: SurfaceTool, center: Vector3, radius: Vector3, col: Color, rng: RandomNumberGenerator, rough := 0.25, rings := 6, segs := 9, col_var := 0.08) -> void:
	var pts := []
	for r in rings + 1:
		var row := []
		var v := float(r) / rings
		var phi := v * PI
		for s in segs:
			var th := TAU * s / segs
			var dir := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var k := 1.0 + rng.randf_range(-rough, rough) if (r > 0 and r < rings) else 1.0
			row.append(center + dir * radius * k)
		pts.append(row)
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			var c := col.lightened(rng.randf_range(-col_var, col_var))
			if r == 0:
				_tri(st, pts[r][s], pts[r + 1][s1], pts[r + 1][s], c)
			elif r == rings - 1:
				_tri(st, pts[r][s], pts[r][s1], pts[r + 1][s], c)
			else:
				quad(st, pts[r][s], pts[r][s1], pts[r + 1][s1], pts[r + 1][s], c)


static func material_vc(rough := 0.85, metal := 0.0, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission_energy_multiplier = emission
	return m
