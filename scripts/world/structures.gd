class_name Structures
extends Node3D
## POI houses + player building grid, placement rules and structural integrity.

const T := BuildPiece.TILE

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var player_pieces := {}     # key -> BuildPiece
var cell_index := {}        # Vector3i -> Array[BuildPiece]
var chest_spots: Array = [] # [{pos, yaw}]
var loot_spots: Array = []  # [Vector3]
var foundation_mat: StandardMaterial3D


func setup(t: Terrain, seed_value: int) -> void:
	terrain = t
	rng.seed = seed_value + 555
	foundation_mat = StandardMaterial3D.new()
	foundation_mat.albedo_color = Color(0.55, 0.53, 0.5)
	foundation_mat.roughness = 0.95
	for poi in terrain.pois:
		_build_poi(poi)


# --- POI generation -------------------------------------------------------------

func _build_poi(poi: Dictionary) -> void:
	var c: Vector3 = poi["pos"]
	var r: float = poi["radius"]
	var name_s: String = poi["name"]
	var count := rng.randi_range(3, 5)
	var occupied: Array[Rect2] = []
	var style := rng.randi() % 3
	if name_s.contains("Порт") or name_s.contains("Карьер") or name_s.contains("Лесопилка"):
		style = 3 # industrial
	for i in count * 6:
		if occupied.size() >= count:
			break
		var kind := "house"
		var roll := rng.randf()
		if style == 3:
			kind = "warehouse" if roll < 0.5 else ("two_story" if roll < 0.75 else "house")
		else:
			kind = "two_story" if roll < 0.4 else ("house" if roll < 0.85 else "warehouse")
		var w := 2
		var d := 2
		match kind:
			"house":
				w = rng.randi_range(2, 3); d = 2
			"two_story":
				w = 3; d = 2
			"warehouse":
				w = 4; d = 3
		if rng.randf() < 0.5:
			var tmp := w; w = d; d = tmp
		var a := rng.randf() * TAU
		var dist := rng.randf_range(0.0, r - maxf(w, d) * T * 0.7)
		var gx := floorf((c.x + cos(a) * dist) / T) * T
		var gz := floorf((c.z + sin(a) * dist) / T) * T
		var rect := Rect2(gx - 4.0, gz - 4.0, w * T + 8.0, d * T + 8.0)
		var ok := true
		for o in occupied:
			if o.intersects(rect):
				ok = false
				break
		if not ok:
			continue
		occupied.append(rect)
		var base := Vector3(gx, float(c.y), gz)
		match kind:
			"house":
				_make_house(base, w, d, 1, ["plaster", "wood", "brick"][rng.randi() % 3], rng.randf() < 0.6)
			"two_story":
				_make_house(base, w, d, 2, ["brick", "plaster"][rng.randi() % 2], rng.randf() < 0.5)
			"warehouse":
				_make_warehouse(base, w, d)
	# Some outdoor loot / chests around the POI.
	for i in rng.randi_range(2, 4):
		var a2 := rng.randf() * TAU
		var p := Vector3(c.x + cos(a2) * r * 0.9, 0, c.z + sin(a2) * r * 0.9)
		p.y = terrain.height_at(p.x, p.z)
		if p.y > 0.8:
			if rng.randf() < 0.4:
				chest_spots.append({"pos": p, "yaw": rng.randf() * TAU})
			else:
				loot_spots.append(p + Vector3(0, 0.3, 0))


func _add_static_piece(type: String, mat: String, pos: Vector3, yaw: float) -> BuildPiece:
	var p := BuildPiece.make(type, mat, false)
	p.world = self
	add_child(p)
	p.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_index_piece(p)
	return p


func _foundation(base: Vector3, w: int, d: int) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var lowest := base.y
	for i in w + 1:
		for j in d + 1:
			lowest = minf(lowest, terrain.height_at(base.x + i * T, base.z + j * T))
	var depth := base.y - lowest + 1.5
	bm.size = Vector3(w * T + 0.3, depth, d * T + 0.3)
	mi.mesh = bm
	mi.material_override = foundation_mat
	mi.position = Vector3(base.x + w * T * 0.5, base.y + 0.12 - depth * 0.5, base.z + d * T * 0.5)
	mi.visibility_range_end = 420.0
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)
	body.position = mi.position
	add_child(body)


func _perimeter_walls(base: Vector3, w: int, d: int, level: int, mat: String, door_edge: int, window_chance: float) -> void:
	var y := base.y + level * T + 0.12
	# Edges: 0 = -z side, 1 = +z side, 2 = -x side, 3 = +x side.
	for i in w:
		for side in [0, 1]:
			var z: float = base.z + (0.0 if side == 0 else d * T)
			var type := _wall_variant(level, door_edge == side and i == w / 2, window_chance)
			_add_static_piece(type, mat, Vector3(base.x + i * T + T * 0.5, y, z), 0.0)
	for j in d:
		for side in [2, 3]:
			var x: float = base.x + (0.0 if side == 2 else w * T)
			var type2 := _wall_variant(level, door_edge == side and j == d / 2, window_chance)
			_add_static_piece(type2, mat, Vector3(x, y, base.z + j * T + T * 0.5), PI * 0.5)


func _wall_variant(level: int, is_door: bool, window_chance: float) -> String:
	if is_door and level == 0:
		return "wall_door"
	return "wall_window" if rng.randf() < window_chance else "wall"


func _make_house(base: Vector3, w: int, d: int, floors: int, mat: String, pitched: bool) -> void:
	_foundation(base, w, d)
	var door_edge := rng.randi() % 4
	for level in floors:
		_perimeter_walls(base, w, d, level, mat, door_edge, 0.45)
	# Interior stairs between floors.
	var stair_cell := Vector2i(0, 0)
	if floors > 1:
		stair_cell = Vector2i(rng.randi() % w, 0)
		var sp := Vector3(base.x + stair_cell.x * T + T * 0.5, base.y + 0.12, base.z + stair_cell.y * T + T * 0.5 + 0.0)
		# Ramp rising toward +z inside the house; it climbs into the gap left in the upper floor.
		_add_static_piece("ramp", "wood", sp, PI)
		for level in range(1, floors):
			for i in w:
				for j in d:
					if Vector2i(i, j) == stair_cell + Vector2i(0, 1) or Vector2i(i, j) == stair_cell:
						if Vector2i(i, j) == stair_cell:
							continue
					_add_static_piece("floor", "wood", Vector3(base.x + i * T + T * 0.5, base.y + level * T + 0.12, base.z + j * T + T * 0.5), 0.0)
	# Roof.
	var roof_y := base.y + floors * T + 0.12
	for i in w:
		for j in d:
			var p := Vector3(base.x + i * T + T * 0.5, roof_y, base.z + j * T + T * 0.5)
			if pitched:
				_add_static_piece("cone", "wood" if mat != "wood" else "brick", p, 0.0)
			else:
				_add_static_piece("floor", mat, p, 0.0)
	# Loot inside.
	var chest_count := 1 if rng.randf() < 0.7 else 2
	for k in chest_count:
		var lvl := rng.randi() % floors
		var ci := rng.randi() % w
		var cj := rng.randi() % d
		if floors > 1 and Vector2i(ci, cj) == stair_cell:
			cj = (cj + 1) % d
		var pos := Vector3(base.x + ci * T + T * 0.5 + rng.randf_range(-0.8, 0.8), base.y + lvl * T + 0.25, base.z + cj * T + T * 0.5 + rng.randf_range(-0.8, 0.8))
		chest_spots.append({"pos": pos, "yaw": float(rng.randi() % 4) * PI * 0.5})
	for k in rng.randi_range(1, 2 + floors):
		var lvl2 := rng.randi() % floors
		var pos2 := Vector3(base.x + rng.randf_range(0.8, w * T - 0.8), base.y + lvl2 * T + 0.5, base.z + rng.randf_range(0.8, d * T - 0.8))
		loot_spots.append(pos2)


func _make_warehouse(base: Vector3, w: int, d: int) -> void:
	_foundation(base, w, d)
	var mat := "steel" if rng.randf() < 0.6 else "metal"
	for level in 2:
		var door_edge := 0 if level == 0 else -1
		_perimeter_walls(base, w, d, level, mat, door_edge, 0.0 if level == 0 else 0.5)
	# Second door on the opposite side.
	var roof_y := base.y + 2 * T + 0.12
	for i in w:
		for j in d:
			_add_static_piece("floor", "metal", Vector3(base.x + i * T + T * 0.5, roof_y, base.z + j * T + T * 0.5), 0.0)
	for k in rng.randi_range(3, 6):
		var p := Vector3(base.x + rng.randf_range(1.5, w * T - 1.5), base.y + 0.12, base.z + rng.randf_range(1.5, d * T - 1.5))
		_add_static_piece("crate", "wood", p, rng.randf() * TAU)
	chest_spots.append({"pos": Vector3(base.x + w * T * 0.5, base.y + 0.25, base.z + d * T * 0.5), "yaw": 0.0})
	if rng.randf() < 0.5:
		chest_spots.append({"pos": Vector3(base.x + 1.5, base.y + 0.25, base.z + d * T - 1.5), "yaw": PI * 0.5})
	for k in 3:
		loot_spots.append(Vector3(base.x + rng.randf_range(1.0, w * T - 1.0), base.y + 0.5, base.z + rng.randf_range(1.0, d * T - 1.0)))


# --- spatial index / integrity ------------------------------------------------------

func _cells_for(aabb: AABB) -> Array:
	var out := []
	var a := aabb.grow(0.2)
	var x0 := int(floor(a.position.x / T))
	var x1 := int(floor(a.end.x / T))
	var y0 := int(floor(a.position.y / T))
	var y1 := int(floor(a.end.y / T))
	var z0 := int(floor(a.position.z / T))
	var z1 := int(floor(a.end.z / T))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				out.append(Vector3i(x, y, z))
	return out


func _index_piece(p: BuildPiece) -> void:
	var aabb := p.world_aabb()
	p.set_meta("aabb", aabb)
	var cells := _cells_for(aabb)
	p.set_meta("cells", cells)
	for c in cells:
		if not cell_index.has(c):
			cell_index[c] = []
		cell_index[c].append(p)


func _unindex_piece(p: BuildPiece) -> void:
	if not p.has_meta("cells"):
		return
	for c in p.get_meta("cells"):
		if cell_index.has(c):
			cell_index[c].erase(p)
			if cell_index[c].is_empty():
				cell_index.erase(c)


func _neighbors(p: BuildPiece) -> Array:
	var out := []
	var aabb: AABB = p.get_meta("aabb")
	var g := aabb.grow(0.15)
	for c in p.get_meta("cells"):
		if not cell_index.has(c):
			continue
		for q in cell_index[c]:
			if q == p or out.has(q) or not is_instance_valid(q) or q.is_dead():
				continue
			if g.intersects(q.get_meta("aabb")):
				out.append(q)
	return out


func _grounded(p: BuildPiece) -> bool:
	var aabb: AABB = p.get_meta("aabb")
	var bottom := aabb.position.y
	var pts := [aabb.get_center(), aabb.position, aabb.position + Vector3(aabb.size.x, 0, 0), aabb.position + Vector3(0, 0, aabb.size.z), aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)]
	for pt in pts:
		if bottom <= terrain.height_at(pt.x, pt.z) + 0.35:
			return true
	return false


func on_piece_destroyed(p: BuildPiece, cascade: bool) -> void:
	var neigh := _neighbors(p) if p.has_meta("cells") else []
	_unindex_piece(p)
	if p.player_built and player_pieces.get(p.grid_key) == p:
		player_pieces.erase(p.grid_key)
	if not cascade:
		return
	var visited := {}
	for n in neigh:
		if not n.player_built or visited.has(n):
			continue
		var comp := []
		var queue := [n]
		var supported := false
		visited[n] = true
		while not queue.is_empty() and comp.size() < 400:
			var cur: BuildPiece = queue.pop_back()
			comp.append(cur)
			if _grounded(cur):
				supported = true
				break
			for q in _neighbors(cur):
				if not q.player_built:
					supported = true
					break
				if not visited.has(q):
					visited[q] = true
					queue.append(q)
			if supported:
				break
		if not supported:
			var delay := 0.05
			for piece in comp:
				var pc: BuildPiece = piece
				get_tree().create_timer(delay).timeout.connect(pc.destroy.bind(false))
				delay += 0.03


# --- player building -------------------------------------------------------------

func _phase_near(feet: Vector3) -> float:
	var c := Vector3i(int(floor(feet.x / T)), int(floor(feet.y / T)), int(floor(feet.z / T)))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var k := c + Vector3i(dx, dy, dz)
				if cell_index.has(k):
					for q in cell_index[k]:
						if is_instance_valid(q) and q.player_built:
							return fposmod(q.get_meta("base_y", 0.0), T)
	return fposmod(feet.y, T)


## Computes grid placement for a piece type from a builder's feet position and view angles.
func compute_placement(type: String, feet: Vector3, yaw: float, pitch: float) -> Dictionary:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var dx := 0
	var dz := 0
	if absf(fwd.x) > absf(fwd.z):
		dx = 1 if fwd.x > 0 else -1
	else:
		dz = 1 if fwd.z > 0 else -1
	var cx := int(floor(feet.x / T))
	var cz := int(floor(feet.z / T))
	var phase := _phase_near(feet)
	var lvl := int(floor((feet.y - phase + 0.3) / T))
	# Distance to the front boundary of the current cell along the build direction.
	var dist := 0.0
	if dx != 0:
		dist = ((cx + (1 if dx > 0 else 0)) * T - feet.x) * dx
	else:
		dist = ((cz + (1 if dz > 0 else 0)) * T - feet.z) * dz
	var lvl_front := int(floor((feet.y + dist - phase + 0.3) / T))
	var pos := Vector3.ZERO
	var rot := 0.0
	var key := ""
	match type:
		"wall":
			var l := lvl + (1 if pitch > 0.55 else 0)
			var y := phase + l * T
			if dx != 0:
				var bx := cx + (1 if dx > 0 else 0)
				pos = Vector3(bx * T, y, cz * T + T * 0.5)
				rot = PI * 0.5
				key = "w:x:%d:%d:%d" % [bx, l, cz]
			else:
				var bz := cz + (1 if dz > 0 else 0)
				pos = Vector3(cx * T + T * 0.5, y, bz * T)
				key = "w:z:%d:%d:%d" % [cx, l, bz]
		"floor":
			var fx := cx
			var fz := cz
			var l2 := lvl
			if pitch > -0.45:
				fx += dx
				fz += dz
				l2 = lvl_front
				if pitch > 0.55:
					l2 += 1
			pos = Vector3(fx * T + T * 0.5, phase + l2 * T, fz * T + T * 0.5)
			key = "f:%d:%d:%d" % [fx, l2, fz]
		"ramp":
			var rx := cx + dx
			var rz := cz + dz
			pos = Vector3(rx * T + T * 0.5, phase + lvl_front * T, rz * T + T * 0.5)
			if dz == -1: rot = 0.0
			elif dz == 1: rot = PI
			elif dx == 1: rot = -PI * 0.5
			else: rot = PI * 0.5
			key = "r:%d:%d:%d" % [rx, lvl_front, rz]
		"cone":
			var l3 := lvl + 1
			pos = Vector3(cx * T + T * 0.5, phase + l3 * T, cz * T + T * 0.5)
			key = "c:%d:%d:%d" % [cx, l3, cz]
	key += ":%.1f" % phase
	return {"key": key, "xf": Transform3D(Basis(Vector3.UP, rot), pos), "valid": not player_pieces.has(key), "base_y": pos.y}


func place_player_piece(type: String, mat: String, placement: Dictionary, team: int) -> BuildPiece:
	var key: String = placement["key"]
	if player_pieces.has(key) and is_instance_valid(player_pieces[key]) and not player_pieces[key].is_dead():
		return null
	var p := BuildPiece.make(type, mat, true)
	p.world = self
	p.team = team
	p.grid_key = key
	p.set_meta("base_y", float(placement["base_y"]))
	add_child(p)
	p.global_transform = placement["xf"]
	_index_piece(p)
	player_pieces[key] = p
	Sfx.play3d("build", p.global_position + Vector3(0, 1, 0), -6.0)
	return p
