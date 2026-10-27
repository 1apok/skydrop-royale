class_name Match
extends Node3D
## A single battle royale match: world, environment, fighters, airship, storm, end conditions.

signal loading_progress(text: String, value: float)
signal match_finished(result: Dictionary)
signal kill_feed(text: String, highlight: bool)

const BUS_HEIGHT := 170.0
const BUS_SPEED := 42.0

const NAME_A := ["Тихий", "Быстрый", "Хитрый", "Ночной", "Ледяной", "Огненный", "Северный", "Пиксельный", "Неоновый", "Бодрый", "Лунный", "Ржавый", "Mega", "Turbo", "Night", "Frost", "Pixel", "Neo", "Lucky", "Sly"]
const NAME_B := ["Лис", "Волк", "Ёж", "Барсук", "Енот", "Сокол", "Кот", "Медведь", "Бобр", "Филин", "Yeti", "Byte", "Fox", "Raven", "Comet", "Otter", "Panda", "Gecko", "Moth", "Lynx"]

var seed_value := 0
var terrain: Terrain
var structures: Structures
var foliage: Foliage
var loot: Loot
var storm: Storm
var fx: FX
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var water: MeshInstance3D
var fighters: Array = []
var player: Fighter
var player_ctrl: Node
var hud: Node

var bus_active := false
var bus_pos := Vector3.ZERO
var bus_dir := Vector3.FORWARD
var bus_start := Vector3.ZERO
var bus_end := Vector3.ZERO
var bus_t := 0.0
var bus_len := 1.0
var bus_node: Node3D
var on_bus: Array = []
var state := "loading" # loading | countdown | bus | playing | ended
var countdown := 4.0
var storm_tick := 0.0
var elapsed := 0.0
var finished := false
var player_place := 0
var rng := RandomNumberGenerator.new()
var map_image: Image


func build_world() -> void:
	seed_value = randi()
	rng.seed = seed_value
	loading_progress.emit("Генерация острова…", 0.05)
	await get_tree().process_frame
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(seed_value)
	loading_progress.emit("Рельеф и вода…", 0.3)
	await get_tree().process_frame
	_setup_environment()
	terrain.build(_terrain_material(), float(Game.settings["view_dist"]))
	_build_water()
	loading_progress.emit("Деревья и скалы…", 0.45)
	await get_tree().process_frame
	foliage = Foliage.new()
	add_child(foliage)
	foliage.setup(terrain, seed_value)
	loading_progress.emit("Постройки…", 0.6)
	await get_tree().process_frame
	structures = Structures.new()
	add_child(structures)
	structures.setup(terrain, seed_value)
	loading_progress.emit("Лут…", 0.72)
	await get_tree().process_frame
	loot = Loot.new()
	add_child(loot)
	loot.setup(terrain, structures, seed_value)
	storm = Storm.new()
	add_child(storm)
	storm.setup(terrain, seed_value)
	fx = FX.new()
	add_child(fx)
	loading_progress.emit("Карта…", 0.8)
	await get_tree().process_frame
	map_image = terrain.make_map_image(256)
	loading_progress.emit("Игроки…", 0.9)
	await get_tree().process_frame
	_spawn_fighters()
	_setup_bus()
	Game.settings_changed.connect(apply_graphics)
	apply_graphics()
	loading_progress.emit("Готово!", 1.0)
	state = "countdown"


func _terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.05
	n.fractal_octaves = 4
	var dt := NoiseTexture2D.new()
	dt.noise = n
	dt.seamless = true
	dt.width = 512
	dt.height = 512
	dt.generate_mipmaps = true
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.generate_mipmaps = true
	var m2 := FastNoiseLite.new()
	m2.seed = seed_value + 3
	m2.frequency = 0.01
	var mt := NoiseTexture2D.new()
	mt.noise = m2
	mt.seamless = true
	mt.width = 256
	mt.height = 256
	mat.set_shader_parameter("detail_noise", dt)
	mat.set_shader_parameter("detail_normal", nt)
	mat.set_shader_parameter("macro_noise", mt)
	return mat


func _build_water() -> void:
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	for k in ["wave_normal_a", "wave_normal_b"]:
		var n := FastNoiseLite.new()
		n.seed = seed_value + (1 if k.ends_with("a") else 2)
		n.frequency = 0.04 if k.ends_with("a") else 0.07
		n.fractal_octaves = 3
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.as_normal_map = true
		t.bump_strength = 3.0
		t.width = 256
		t.height = 256
		t.generate_mipmaps = true
		wm.set_shader_parameter(k, t)
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0, 0.0, 0)
	add_child(water)
	# Water blocks bodies from falling forever but is not walkable deeply: a trigger floor below.


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.42, 0.85)
	sm.sky_horizon_color = Color(0.68, 0.8, 0.95)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.12, 0.2, 0.3)
	sm.ground_horizon_color = Color(0.68, 0.8, 0.95)
	sm.sun_angle_max = 25.0
	sm.sun_curve = 0.08
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color(0.62, 0.6, 0.55)
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.95)
	env.fog_density = 0.0009
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.3
	env.glow_normalized = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssil_radius = 4.0
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 1.0
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.92, 1.0)
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_anisotropy = 0.5
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)


func apply_graphics() -> void:
	if env == null:
		return
	var s := Game.settings
	env.ssao_enabled = bool(s["ssao"])
	env.ssil_enabled = bool(s["ssil"])
	env.ssr_enabled = bool(s["ssr"])
	env.sdfgi_enabled = bool(s["sdfgi"])
	env.volumetric_fog_enabled = bool(s["vol_fog"])
	env.glow_enabled = bool(s["glow"])
	var q := int(s["shadows"])
	sun.shadow_enabled = q > 0
	sun.directional_shadow_max_distance = [40.0, 70.0, 120.0, 200.0][clampi(q, 0, 3)]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q <= 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5 if q >= 2 else 0.5
	var vd := float(s["view_dist"])
	terrain.set_view_distance(vd)
	foliage.set_view_distance(vd * 0.7)
	foliage.set_grass_quality(int(s["grass"]))
	env.fog_density = lerpf(0.0018, 0.0008, clampf((vd - 250.0) / 450.0, 0.0, 1.0))
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.far = vd + 300.0


func _spawn_fighters() -> void:
	var used := {}
	var total := int(Game.settings["bots"]) + 1
	for i in total:
		var f := Fighter.new()
		f.seed_value = rng.randi()
		f.team = i
		f.game_match = self
		f.is_player = i == 0
		if f.is_player:
			f.display_name = "Ты"
		else:
			var nm := ""
			for k in 10:
				nm = NAME_A[rng.randi() % NAME_A.size()] + NAME_B[rng.randi() % NAME_B.size()]
				if rng.randf() < 0.4:
					nm += str(rng.randi_range(1, 99))
				if not used.has(nm):
					break
			used[nm] = true
			f.display_name = nm
		add_child(f)
		f.setup_mode(String(Game.settings["mode"]))
		f.visible = false
		f.global_position = Vector3(0, BUS_HEIGHT, 0)
		f.died.connect(_on_fighter_died)
		fighters.append(f)
		on_bus.append(f)
		if f.is_player:
			player = f
		else:
			var brain := BotBrain.new()
			f.add_child(brain)
			brain.setup(f, self, int(Game.settings["difficulty"]))
			brain.choose_drop()


func _setup_bus() -> void:
	var a := rng.randf() * TAU
	bus_dir = Vector3(cos(a), 0, sin(a))
	var perp := bus_dir.cross(Vector3.UP)
	var off := perp * rng.randf_range(-120.0, 120.0)
	bus_start = -bus_dir * 520.0 + off + Vector3(0, BUS_HEIGHT, 0)
	bus_end = bus_dir * 520.0 + off + Vector3(0, BUS_HEIGHT, 0)
	bus_len = bus_start.distance_to(bus_end)
	bus_pos = bus_start
	bus_node = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Models.airship_mesh()
	mi.material_override = Models.vc_material()
	bus_node.add_child(mi)
	add_child(bus_node)
	bus_node.global_position = bus_pos
	bus_node.look_at(bus_pos - bus_dir, Vector3.UP)


func start_match() -> void:
	state = "countdown"
	countdown = 4.0


func _process(delta: float) -> void:
	if state == "loading":
		return
	elapsed += delta
	if state == "countdown":
		countdown -= delta
		_update_bus(0.0)
		if countdown <= 0.0:
			state = "bus"
			bus_active = true
		return
	if bus_active:
		_update_bus(delta)
	if state != "ended" or true:
		storm_tick -= delta
		if storm_tick <= 0.0:
			storm_tick = 1.0
			_apply_storm_damage()
	var cam := get_viewport().get_camera_3d()
	if cam and foliage:
		foliage.update_camera(cam.global_position)
	if water and cam:
		water.global_position = Vector3(snappedf(cam.global_position.x, 16.0), 0.0, snappedf(cam.global_position.z, 16.0))


func _update_bus(delta: float) -> void:
	bus_t += delta * BUS_SPEED
	var k := clampf(bus_t / bus_len, 0.0, 1.0)
	bus_pos = bus_start.lerp(bus_end, k)
	if bus_node:
		bus_node.global_position = bus_pos
	for f in on_bus:
		(f as Fighter).global_position = bus_pos + Vector3(0, -8.0, 0)
	if k >= 1.0 and bus_active:
		for f in on_bus.duplicate():
			eject(f)
		bus_active = false
		var t := create_tween()
		t.tween_property(bus_node, "global_position", bus_pos + bus_dir * 400.0, 8.0)
		t.tween_callback(bus_node.queue_free)
		state = "playing"


func eject(f: Fighter) -> void:
	if not on_bus.has(f):
		return
	on_bus.erase(f)
	f.visible = true
	f.phase = "freefall"
	f.global_position = bus_pos + Vector3(rng.randf_range(-2, 2), -9.0, rng.randf_range(-2, 2))
	f.velocity = bus_dir * BUS_SPEED * 0.4
	f.look_yaw = atan2(-bus_dir.x, -bus_dir.z)
	if not storm.active:
		storm.start()
	if f.is_player:
		Sfx.play("glider", -4.0)


func _apply_storm_damage() -> void:
	if not storm.active:
		return
	for f in fighters:
		var fi: Fighter = f
		if fi.alive and fi.phase != "bus" and storm.is_outside(fi.global_position):
			fi.take_damage(storm.damage, null, false, "storm")


func pickup_item(f: Fighter, node: Node3D) -> void:
	if not is_instance_valid(node) or not loot.pickups.has(node):
		return
	var item: Dictionary = node.get_meta("item")
	var pos := node.global_position
	loot.remove_pickup(node)
	var left := f.pick_up(item)
	if not left.is_empty():
		loot.spawn_pickup(left, pos + Vector3(0, 0.1, 0))
	if f.is_player:
		Sfx.play("pickup", -6.0)


func on_gunshot(shooter: Fighter, pos: Vector3) -> void:
	for f in fighters:
		var fi: Fighter = f
		if fi != shooter and fi.alive and not fi.is_player:
			var brain: BotBrain = fi.get_child(fi.get_child_count() - 1) as BotBrain
			if brain:
				brain.on_noise(pos)


func on_damaged(victim: Fighter, attacker: Fighter, amount: float) -> void:
	if hud and victim == player and amount > 0.0:
		hud.on_player_damaged(attacker, amount)


func on_player_hit(head: bool) -> void:
	if hud:
		hud.on_hitmarker(head)
	Sfx.play("headshot" if head else "hitmarker", -4.0)


func alive_count() -> int:
	var n := 0
	for f in fighters:
		if (f as Fighter).alive:
			n += 1
	return n


func _on_fighter_died(victim: Fighter, killer: Fighter, cause: String) -> void:
	var alive_n := alive_count()
	victim.place = alive_n + 1
	# Drop loot.
	var items := victim.drop_all()
	for i in items.size():
		var a := TAU * i / maxf(items.size(), 1)
		loot.spawn_pickup(items[i], victim.global_position + Vector3(cos(a), 0.5, sin(a)) * 1.2)
	var text := ""
	var reason := cause
	if killer != null and killer != victim:
		var weapon := "Кирка"
		var w := killer.current_weapon()
		if not w.is_empty():
			weapon = String(Items.WEAPONS[w["id"]]["name"])
		text = "%s  ⟶  %s  [%s]" % [killer.display_name, victim.display_name, weapon]
	else:
		match reason:
			"storm": text = "%s погиб в шторме" % victim.display_name
			"fall": text = "%s разбился" % victim.display_name
			"water": text = "%s утонул" % victim.display_name
			_: text = "%s выбыл" % victim.display_name
	kill_feed.emit(text, killer == player or victim == player)
	if killer == player:
		Sfx.play("eliminate", -2.0)
		if hud:
			hud.on_player_elimination(victim)
	if victim == player:
		player_place = alive_n + 1
		_finish(false, killer)
	elif alive_n <= 1 and player.alive:
		player_place = 1
		_finish(true, null)
	elif alive_n <= 1 and not finished:
		pass


func _finish(victory: bool, killer: Fighter) -> void:
	if finished:
		return
	finished = true
	if victory:
		Sfx.play("victory", -2.0)
	var result := {
		"victory": victory,
		"place": player_place,
		"kills": player.kills,
		"damage": int(player.damage_dealt),
		"time": int(elapsed),
		"total": fighters.size(),
		"killer": killer.display_name if killer != null else "",
		"killer_node": killer,
	}
	Game.last_result = result
	match_finished.emit(result)
