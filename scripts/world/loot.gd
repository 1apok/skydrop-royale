class_name Loot
extends Node3D
## Pickups and chests: spawning, proximity queries, opening.

var rng := RandomNumberGenerator.new()
var pickups: Array = []   # Array of Node3D with meta "item"
var chests: Array = []    # Array of StaticBody3D with meta "opened"
var terrain: Terrain
var _label_timer := 0.0
var _beam_mat: StandardMaterial3D


func setup(t: Terrain, structures: Structures, seed_value: int) -> void:
	terrain = t
	rng.seed = seed_value + 31
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.vertex_color_use_as_albedo = true
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.disable_receive_shadows = true
	for c in structures.chest_spots:
		spawn_chest(c["pos"], c["yaw"])
	for p in structures.loot_spots:
		spawn_floor_loot(p)
	# Scattered chests / loot in the wild.
	for i in 40:
		var x := rng.randf_range(-Terrain.HALF * 0.8, Terrain.HALF * 0.8)
		var z := rng.randf_range(-Terrain.HALF * 0.8, Terrain.HALF * 0.8)
		var h := terrain.height_at(x, z)
		if h < 1.5 or terrain.normal_at(x, z).y < 0.8:
			continue
		if i % 3 == 0:
			spawn_chest(Vector3(x, h, z), rng.randf() * TAU)
		else:
			spawn_floor_loot(Vector3(x, h + 0.3, z))


func spawn_chest(pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 0.7, 0.65)
	cs.shape = bs
	cs.position = Vector3(0, 0.35, 0)
	body.add_child(cs)
	var meshes := Models.chest_meshes()
	var base := MeshInstance3D.new()
	base.mesh = meshes[0]
	base.material_override = Models.vc_material()
	body.add_child(base)
	var lid_pivot := Node3D.new()
	lid_pivot.position = Vector3(0, 0.6, -0.33)
	body.add_child(lid_pivot)
	var lid := MeshInstance3D.new()
	lid.mesh = meshes[1]
	lid.material_override = Models.glow_material()
	lid.position = Vector3(0, 0, 0)
	lid_pivot.add_child(lid)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.35)
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.position = Vector3(0, 1.0, 0)
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 25.0
	light.distance_fade_length = 10.0
	body.add_child(light)
	add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	body.set_meta("opened", false)
	body.set_meta("lid", lid_pivot)
	body.set_meta("light", light)
	chests.append(body)


func open_chest(chest: StaticBody3D) -> void:
	if chest.get_meta("opened", true):
		return
	chest.set_meta("opened", true)
	var lid: Node3D = chest.get_meta("lid")
	var t := create_tween()
	t.tween_property(lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var light: OmniLight3D = chest.get_meta("light")
	var t2 := create_tween()
	t2.tween_property(light, "light_energy", 0.0, 1.2)
	Sfx.play3d("chest", chest.global_position, -2.0)
	var origin := chest.global_position + Vector3(0, 0.8, 0)
	var fwd := chest.global_transform.basis.z
	var drops: Array = []
	drops.append(Items.random_weapon(rng, 1))
	drops.append(Items.random_consumable(rng))
	var w: Dictionary = drops[0]
	drops.append(Items.ammo_item(String(Items.WEAPONS[w["id"]]["ammo"])))
	drops.append({"kind": "mat", "id": ["wood", "stone", "metal"][rng.randi() % 3], "count": 30})
	for i in drops.size():
		var dir := (fwd + chest.global_transform.basis.x * (i - 1.5) * 0.45).normalized()
		spawn_pickup(drops[i], origin, dir * 2.2 + Vector3(0, 3.0, 0))


func spawn_floor_loot(pos: Vector3) -> void:
	var r := rng.randf()
	var item: Dictionary
	if r < 0.5:
		item = Items.random_weapon(rng)
		spawn_pickup(item, pos)
		spawn_pickup(Items.ammo_item(String(Items.WEAPONS[item["id"]]["ammo"])), pos + Vector3(0.7, 0, 0.3))
	elif r < 0.8:
		spawn_pickup(Items.random_consumable(rng), pos)
	else:
		var kinds := ["light", "medium", "heavy", "shells"]
		spawn_pickup(Items.ammo_item(kinds[rng.randi() % kinds.size()]), pos)


func spawn_pickup(item: Dictionary, pos: Vector3, velocity := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.set_meta("item", item)
	var spinner := Node3D.new()
	spinner.name = "Spinner"
	root.add_child(spinner)
	var mi := MeshInstance3D.new()
	match item["kind"]:
		"weapon":
			mi.mesh = Models.weapon_mesh(item["id"], int(item["rarity"]))
			mi.rotation = Vector3(0, PI * 0.5, 0)
			mi.scale = Vector3.ONE * 1.2
		"consumable":
			mi.mesh = Models.consumable_mesh(item["id"])
		"ammo":
			mi.mesh = Models.ammo_mesh(item["id"])
		"mat":
			mi.mesh = Models.mat_mesh(item["id"])
	mi.material_override = Models.vc_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.35, 0)
	spinner.add_child(mi)
	# Rarity glow ring and light beam.
	var col := Items.item_color(item)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.38
	tm.outer_radius = 0.45
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = col
	rm.emission_enabled = true
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.03, 0)
	root.add_child(ring)
	if item["kind"] == "weapon" and int(item["rarity"]) >= 2:
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.25
		cm.height = 6.0
		cm.radial_segments = 8
		cm.rings = 1
		beam.mesh = cm
		var bm := _beam_mat.duplicate() as StandardMaterial3D
		bm.albedo_color = Color(col.r, col.g, col.b, 0.22)
		bm.vertex_color_use_as_albedo = false
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0, 3.0, 0)
		root.add_child(beam)
	var label := Label3D.new()
	label.name = "Label"
	label.text = Items.display_name(item)
	label.modulate = col
	label.outline_size = 8
	label.font_size = 40
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0, 1.0, 0)
	label.visible = false
	root.add_child(label)
	add_child(root)
	root.global_position = pos
	pickups.append(root)
	if velocity != Vector3.ZERO:
		_toss(root, velocity)
	else:
		_settle(root)
	return root


func _settle(node: Node3D) -> void:
	var space := get_world_3d().direct_space_state
	var from := node.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 30, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		node.global_position = hit["position"] + Vector3(0, 0.05, 0)
	else:
		node.global_position.y = maxf(node.global_position.y, terrain.height_at(node.global_position.x, node.global_position.z) + 0.05)


func _toss(node: Node3D, vel: Vector3) -> void:
	var start := node.global_position
	var land := start + Vector3(vel.x, 0, vel.z) * 0.6
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(land + Vector3(0, 2.0, 0), land - Vector3(0, 30, 0), 1)
	var hit := space.intersect_ray(q)
	var end := land
	if not hit.is_empty():
		end = hit["position"] + Vector3(0, 0.05, 0)
	else:
		end.y = terrain.height_at(end.x, end.z) + 0.05
	# Tween owned by the pickup itself, so it dies with it if picked up mid-air.
	var t := node.create_tween()
	var peak := maxf(start.y, end.y) + 1.2
	t.tween_method(_toss_step.bind(node, start, end, peak), 0.0, 1.0, 0.55)


func _toss_step(k: float, node: Node3D, start: Vector3, end: Vector3, peak: float) -> void:
	var p := start.lerp(end, k)
	p.y = lerpf(lerpf(start.y, peak, k), lerpf(peak, end.y, k), k)
	node.global_position = p


func remove_pickup(node: Node3D) -> void:
	pickups.erase(node)
	if is_instance_valid(node):
		node.queue_free()


func nearest_pickup(pos: Vector3, max_dist: float, filter := Callable()) -> Node3D:
	var best: Node3D = null
	var bd := max_dist * max_dist
	for p in pickups:
		var n: Node3D = p
		var d := pos.distance_squared_to(n.global_position)
		if d < bd:
			if filter.is_valid() and not filter.call(n.get_meta("item")):
				continue
			bd = d
			best = n
	return best


func nearest_chest(pos: Vector3, max_dist: float, exclude := {}) -> StaticBody3D:
	var best: StaticBody3D = null
	var bd := max_dist * max_dist
	for c in chests:
		var ch: StaticBody3D = c
		if ch.get_meta("opened", true) or exclude.has(ch):
			continue
		var d := pos.distance_squared_to(ch.global_position)
		if d < bd:
			bd = d
			best = ch
	return best


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var t := Time.get_ticks_msec() * 0.001
	_label_timer -= delta
	var update_labels := _label_timer <= 0.0
	if update_labels:
		_label_timer = 0.25
	for p in pickups:
		var n: Node3D = p
		var d2 := cp.distance_squared_to(n.global_position)
		if d2 < 60.0 * 60.0:
			var sp: Node3D = n.get_node("Spinner")
			sp.rotation.y = t * 1.5
			sp.position.y = sin(t * 2.0 + n.global_position.x) * 0.06
		if update_labels:
			(n.get_node("Label") as Label3D).visible = d2 < 14.0 * 14.0
