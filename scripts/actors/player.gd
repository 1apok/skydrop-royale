class_name PlayerController
extends Node3D
## Human input (touch + keyboard/mouse), third-person camera, aim, building ghost, interaction.

var f: Fighter
var m: Match
var hud: Node

var pivot: Node3D
var pitch_node: Node3D
var arm: SpringArm3D
var cam: Camera3D

var yaw := 0.0
var pitch := -0.15
var build_mode := false
var build_type := "wall"
var ghost: MeshInstance3D
var ghost_mat: ShaderMaterial
var placement := {}
var interact_target: Node3D = null
var interact_text := ""
var spectate: Fighter = null
var _mouse_captured := false
var _fire_held := false
var _ads_held := false
var _auto_t := 0.0
var _build_place_t := 0.0
var _shake := 0.0


func setup(fighter: Fighter, match_node: Match) -> void:
	f = fighter
	m = match_node
	top_level = true
	pivot = Node3D.new()
	add_child(pivot)
	pitch_node = Node3D.new()
	pivot.add_child(pitch_node)
	arm = SpringArm3D.new()
	arm.spring_length = 3.0
	arm.collision_mask = 1
	arm.margin = 0.2
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	arm.shape = sph
	arm.position = Vector3(0.75, 0.25, 0)
	pitch_node.add_child(arm)
	arm.add_excluded_object(f.get_rid())
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.08
	cam.far = 1100.0
	arm.add_child(cam)
	cam.current = true
	ghost_mat = ShaderMaterial.new()
	ghost_mat.shader = load("res://shaders/ghost.gdshader")
	ghost = MeshInstance3D.new()
	ghost.material_override = ghost_mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	ghost.top_level = true
	add_child(ghost)
	yaw = f.look_yaw
	if not Game.is_mobile:
		_capture_mouse(true)


func _capture_mouse(on: bool) -> void:
	_mouse_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if hud and hud.is_menu_open():
		return
	if event is InputEventMouseMotion and _mouse_captured:
		var s := 0.0022 * float(Game.settings["sens"]) * (float(Game.settings["ads_sens"]) if f.ads else 1.0)
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, -1.45, 1.35)
	elif event is InputEventMouseButton and event.pressed and not _mouse_captured and not Game.is_mobile:
		_capture_mouse(true)
	if event.is_action_pressed("pause"):
		if hud:
			hud.toggle_pause()
		_capture_mouse(false)
	if event.is_action_pressed("build_toggle"):
		toggle_build()
	for i in 5:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select_slot(i)
	if event.is_action_pressed("pickaxe"):
		select_slot(-1)
	if event.is_action_pressed("build_wall"): quick_build("wall")
	if event.is_action_pressed("build_floor"): quick_build("floor")
	if event.is_action_pressed("build_ramp"): quick_build("ramp")
	if event.is_action_pressed("build_cone"): quick_build("cone")
	if event.is_action_pressed("material_cycle"):
		cycle_material()
	if event.is_action_pressed("reload"):
		f.start_reload()
	if event.is_action_pressed("interact"):
		interact()
	if event.is_action_pressed("map") and hud:
		hud.toggle_map()


func on_pause_closed() -> void:
	if not Game.is_mobile:
		_capture_mouse(true)


# --- actions callable from touch UI ---------------------------------------------------------

func select_slot(i: int) -> void:
	build_mode = false
	f.select_slot(i)
	Sfx.play("ui", -10.0)


func toggle_build() -> void:
	if Game.settings["mode"] != "build":
		return
	build_mode = not build_mode
	Sfx.play("ui", -8.0)


func quick_build(type: String) -> void:
	if Game.settings["mode"] != "build":
		return
	build_mode = true
	build_type = type
	_update_placement()
	_place()


func set_build_type(type: String) -> void:
	build_type = type
	build_mode = true


func cycle_material() -> void:
	var order := ["wood", "stone", "metal"]
	f.build_mat = order[(order.find(f.build_mat) + 1) % 3]
	Sfx.play("ui", -8.0)


func interact() -> void:
	if interact_target == null or not is_instance_valid(interact_target):
		return
	if interact_target is StaticBody3D:
		m.loot.open_chest(interact_target)
	else:
		m.pickup_item(f, interact_target)
	interact_target = null


func jump_pressed() -> void:
	if f.phase == "bus":
		m.eject(f)
	else:
		f.want_jump = true


# --- per frame -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if f == null:
		return
	var touch = hud.touch if hud else null
	var menu_open: bool = hud != null and hud.is_menu_open()
	# Look.
	if touch:
		var ld: Vector2 = touch.consume_look()
		var s := 0.0055 * float(Game.settings["sens"]) * (float(Game.settings["ads_sens"]) if f.ads else 1.0)
		yaw -= ld.x * s
		pitch = clampf(pitch - ld.y * s, -1.45, 1.35)
	# Move.
	var mv := Vector2.ZERO
	if not menu_open:
		mv = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
		if touch and touch.move_vec.length() > 0.05:
			mv = touch.move_vec
	if mv.length() > 1.0:
		mv = mv.normalized()
	var basis := Basis(Vector3.UP, yaw)
	f.move_input = basis * Vector3(mv.x, 0, mv.y)
	f.look_yaw = yaw
	f.look_pitch = pitch
	f.want_sprint = Input.is_action_pressed("sprint") or (touch != null and touch.move_vec.length() > 0.95) or Game.is_mobile
	f.want_dive = pitch < -0.6 or Input.is_action_pressed("crouch")
	if not menu_open:
		if Input.is_action_just_pressed("jump") or (touch and touch.take("jump")):
			jump_pressed()
		f.want_crouch = Input.is_action_pressed("crouch") or (touch != null and touch.crouch_on)
		# On phones touches are also emulated as mouse clicks, so mouse-bound actions are ignored there.
		var kbm := not Game.is_mobile
		_fire_held = (kbm and Input.is_action_pressed("fire")) or (touch != null and touch.fire_down)
		_ads_held = (kbm and Input.is_action_pressed("aim")) or (touch != null and touch.ads_on)
		if touch:
			if touch.take("reload"): f.start_reload()
			if touch.take("interact"): interact()
			if touch.take("build"): toggle_build()
			if touch.take("mat"): cycle_material()
			for t in ["wall", "floor", "ramp", "cone"]:
				if touch.take("b_" + t):
					quick_build(t)
			for i in 5:
				if touch.take("slot_%d" % i):
					select_slot(i)
			if touch.take("pickaxe"):
				select_slot(-1)
			if touch.take("map"):
				hud.toggle_map()
	else:
		_fire_held = false
		_ads_held = false
	f.ads = _ads_held and not build_mode and f.phase == "ground" and not f.current_weapon().is_empty()
	_update_camera(delta)
	_update_aim(delta)
	# Fire / build.
	if build_mode and f.phase == "ground":
		f.want_fire = false
		_update_placement()
		_build_place_t -= delta
		if _fire_held and _build_place_t <= 0.0:
			_place()
			_build_place_t = 0.15
	else:
		ghost.visible = false
		f.want_fire = _fire_held
	_update_interact()


func _update_camera(delta: float) -> void:
	var target_f := f if f.alive else (spectate if spectate != null and spectate.alive else f)
	var head := target_f.global_position + Vector3(0, 1.55 if not target_f.crouched else 1.15, 0)
	var length := 3.4
	var fov := 75.0
	match target_f.phase:
		"bus":
			head = m.bus_pos + Vector3(0, 6, 0)
			length = 34.0
		"freefall":
			length = 6.5
			fov = 82.0
		"glide":
			length = 5.0
			fov = 80.0
	if target_f.phase == "ground" and f.ads:
		var w := f.weapon_def()
		fov = float(w.get("zoom", 60.0))
		length = 1.6 if String(f.current_weapon().get("id", "")) != "sniper" else 0.6
	if not f.alive and spectate != null:
		yaw = lerp_angle(yaw, spectate.look_yaw, delta * 3.0)
	pivot.global_position = pivot.global_position.lerp(head, clampf(delta * 18.0, 0, 1)) if pivot.global_position.distance_to(head) < 10.0 else head
	pivot.rotation = Vector3(0, yaw, 0)
	_shake = maxf(0.0, _shake - delta * 4.0)
	pitch_node.rotation = Vector3(pitch + randf_range(-1, 1) * _shake * 0.02, 0, 0)
	arm.spring_length = lerpf(arm.spring_length, length, clampf(delta * 8.0, 0, 1))
	arm.position.x = lerpf(arm.position.x, 0.0 if target_f.phase != "ground" else (0.55 if f.ads else 0.8), clampf(delta * 10.0, 0, 1))
	cam.fov = lerpf(cam.fov, fov, clampf(delta * 12.0, 0, 1))


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.5)


func _update_aim(delta: float) -> void:
	var space := f.get_world_3d().direct_space_state
	var cdir := -cam.global_transform.basis.z
	var cpos := cam.global_position
	var eye := f.eye_pos()
	var t0 := maxf((eye - cpos).dot(cdir), 0.0)
	var origin := cpos + cdir * t0
	var q := PhysicsRayQueryParameters3D.create(origin, origin + cdir * 600.0, 1 | 2, [f.get_rid()])
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + cdir * 600.0
	var dir := (target - eye)
	if dir.length() < 1.0:
		dir = cdir
	f.aim_dir = dir.normalized()
	# Mobile-style aim assist: slow down and gently pull toward enemies near the crosshair.
	if Game.settings.get("aim_assist", true) and f.phase == "ground" and not f.current_weapon().is_empty():
		var best: Fighter = null
		var best_ang := 6.0
		for o in m.fighters:
			var other: Fighter = o
			if other == f or not other.alive or other.phase == "bus":
				continue
			var to := other.chest_pos() - cpos
			var d := to.length()
			if d > 120.0:
				continue
			var ang := rad_to_deg(cdir.angle_to(to / d))
			if ang < best_ang:
				best_ang = ang
				best = other
		if best != null:
			var to2 := best.chest_pos() - eye
			var want_yaw := atan2(-to2.x, -to2.z)
			var want_pitch := atan2(to2.y, Vector2(to2.x, to2.z).length())
			var strength := (0.9 if f.ads else 0.35) * delta * 4.0
			yaw = lerp_angle(yaw, want_yaw, strength * 0.5)
			pitch = lerpf(pitch, want_pitch, strength * 0.5)


func _update_placement() -> void:
	if Game.settings["mode"] != "build":
		return
	placement = m.structures.compute_placement(build_type, f.global_position, yaw, pitch)
	ghost.mesh = BuildPiece.get_mesh(build_type)
	ghost.global_transform = placement["xf"]
	var can := bool(placement["valid"]) and f.pick_build_mat() != ""
	ghost_mat.set_shader_parameter("valid", can)
	ghost.visible = true


func _place() -> void:
	if placement.is_empty():
		return
	var p := f.try_build(build_type, placement)
	if p == null and f.pick_build_mat() == "" and hud:
		hud.toast("Недостаточно материалов")


func _update_interact() -> void:
	interact_target = null
	interact_text = ""
	if f.phase != "ground" or not f.alive:
		return
	var pos := f.global_position
	# Auto-pickup ammo / materials.
	var auto := m.loot.nearest_pickup(pos, 1.6, func(it: Dictionary): return it["kind"] == "ammo" or it["kind"] == "mat")
	if auto != null:
		m.pickup_item(f, auto)
	var chest := m.loot.nearest_chest(pos, 2.6)
	if chest != null:
		interact_target = chest
		interact_text = "Открыть сундук"
		return
	var p := m.loot.nearest_pickup(pos, 2.3)
	if p != null:
		interact_target = p
		var item: Dictionary = p.get_meta("item")
		interact_text = "Взять: " + Items.display_name(item)
		if item["kind"] == "weapon":
			interact_text += " (" + Items.RARITY_NAMES[int(item["rarity"])] + ")"
