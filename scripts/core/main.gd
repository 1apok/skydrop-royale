extends Node
## App flow: menu -> loading -> match -> results -> menu.

var menu: MainMenu
var game_match: Match
var hud: HUD
var ctrl: PlayerController
var loading: CanvasLayer
var _load_label: Label
var _load_bar: ProgressBar
var autotest := false
var _autotest_t := 0.0


func _ready() -> void:
	autotest = OS.get_cmdline_user_args().has("--autotest")
	if autotest:
		Game.settings["bots"] = 23
		start_match()
	else:
		show_menu()


func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = MainMenu.new()
	add_child(menu)
	menu.play_pressed.connect(start_match)


func _show_loading() -> void:
	loading = CanvasLayer.new()
	loading.layer = 10
	add_child(loading)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(c)
	var u := get_viewport().get_visible_rect().size.y / 720.0
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var title := UIKit.label("SKYDROP", int(72 * u), UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_load_label = UIKit.label("Загрузка…", int(24 * u))
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_load_label)
	_load_bar = ProgressBar.new()
	_load_bar.custom_minimum_size = Vector2(520 * u, 18 * u)
	_load_bar.show_percentage = false
	_load_bar.max_value = 1.0
	v.add_child(_load_bar)
	var tips := [
		"Совет: в режиме «Стройка» стена + лестница — лучший способ занять высоту.",
		"Совет: в «Нулевой высоте» у тебя есть перезаряжающийся сверхщит.",
		"Совет: золотые сундуки светятся и звенят — их слышно издалека.",
		"Совет: шторм сужается — следи за белым кругом на карте.",
		"Совет: попадание в голову наносит больше урона.",
	]
	var tip := UIKit.label(tips[randi() % tips.size()], int(18 * u), Color(0.7, 0.75, 0.9))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)


func start_match() -> void:
	if menu:
		menu.queue_free()
		menu = null
	_show_loading()
	await get_tree().process_frame
	game_match = Match.new()
	add_child(game_match)
	game_match.loading_progress.connect(func(t: String, val: float):
		_load_label.text = t
		_load_bar.value = val)
	await game_match.build_world()
	ctrl = PlayerController.new()
	game_match.add_child(ctrl)
	ctrl.setup(game_match.player, game_match)
	game_match.player_ctrl = ctrl
	hud = HUD.new()
	game_match.add_child(hud)
	hud.setup(game_match, ctrl)
	ctrl.hud = hud
	game_match.hud = hud
	hud.exit_to_menu.connect(exit_to_menu)
	game_match.apply_graphics()
	await get_tree().process_frame
	loading.queue_free()
	loading = null
	game_match.start_match()


func exit_to_menu() -> void:
	if game_match:
		game_match.queue_free()
		game_match = null
	hud = null
	ctrl = null
	await get_tree().process_frame
	show_menu()


func _process(delta: float) -> void:
	if not autotest or game_match == null or game_match.state == "loading":
		return
	_autotest_t += delta
	# Automated smoke test: drop the player, let bots play, then report and quit.
	if game_match.player.phase == "bus" and game_match.bus_active and _autotest_t > 6.0:
		game_match.eject(game_match.player)
		# Put the test player on the ground at a POI, armed, facing its center.
		var poi: Dictionary = game_match.terrain.pois[0]
		var c: Vector3 = poi["pos"]
		var p := game_match.player
		var spot := c + Vector3(float(poi["radius"]) + 6.0, 0, 4.0)
		spot.y = game_match.terrain.height_at(spot.x, spot.z) + 1.0
		p.global_position = spot
		p.phase = "ground"
		p.pick_up(Items.weapon_item("ar", 3))
		p.ammo["medium"] = 120
		p.mats["wood"] = 200
		var to := c - spot
		ctrl.yaw = atan2(-to.x, -to.z)
		ctrl.pitch = -0.12
		p.hp = 100000.0
		if OS.get_environment("AUTOTEST_VIEW") == "air":
			p.global_position = Vector3(c.x + 90.0, c.y + 75.0, c.z + 90.0)
			p.phase = "glide"
			ctrl.yaw = atan2(-(-90.0), -(-90.0))
			ctrl.pitch = -0.45
	if int(_autotest_t) != int(_autotest_t - delta) and int(_autotest_t) % 5 == 0:
		var phases := {}
		for f in game_match.fighters:
			var fi: Fighter = f
			var key := fi.phase
			phases[key] = int(phases.get(key, 0)) + 1
		var states := {}
		for f in game_match.fighters:
			var fi2: Fighter = f
			if fi2.is_player or not fi2.alive:
				continue
			var b: BotBrain = fi2.get_child(fi2.get_child_count() - 1) as BotBrain
			if b:
				states[b.state] = int(states.get(b.state, 0)) + 1
		if OS.get_environment("AUTOTEST_DEBUG") == "1" and int(_autotest_t) % 15 == 0:
			for f in game_match.fighters:
				var fd: Fighter = f
				if fd.is_player or not fd.alive:
					continue
				var bd: BotBrain = fd.get_child(fd.get_child_count() - 1) as BotBrain
				var tgt := "-"
				if bd.loot_node != null and is_instance_valid(bd.loot_node):
					tgt = "pickup %s dy=%.1f d=%.1f" % [str(bd.loot_node.get_meta("item")["kind"]), bd.loot_node.global_position.y - fd.global_position.y, fd.global_position.distance_to(bd.loot_node.global_position)]
				elif bd.chest_node != null and is_instance_valid(bd.chest_node):
					tgt = "chest dy=%.1f d=%.1f" % [bd.chest_node.global_position.y - fd.global_position.y, fd.global_position.distance_to(bd.chest_node.global_position)]
				elif bd.target != null:
					var cw := fd.current_weapon()
					var winfo := "none"
					if not cw.is_empty():
						winfo = "%s clip=%d res=%d" % [cw["id"], int(cw["clip"]), int(fd.ammo[Items.WEAPONS[cw["id"]]["ammo"]])]
					tgt = "enemy d=%.0f vis=%s %s fire=%s dmg=%.0f" % [fd.global_position.distance_to(bd.target.global_position), str(bd.target_visible), winfo, str(fd.want_fire), fd.damage_dealt]
				print("   %s state=%s stuck=%.1f hp=%.0f weap=%d %s" % [fd.display_name, bd.state, bd.stuck_t, fd.total_health(), fd.best_weapon_slot(), tgt])
		print("[autotest] t=%d fps=%d alive=%d phases=%s bot_states=%s pieces=%d storm=%.0f" % [int(_autotest_t), Engine.get_frames_per_second(), game_match.alive_count(), str(phases), str(states), game_match.structures.player_pieces.size(), game_match.storm.radius])
	if OS.get_environment("AUTOTEST_BUILD") == "1" and _autotest_t > 8.0 and not has_meta("built"):
		set_meta("built", true)
		var p2 := game_match.player
		var before := game_match.structures.player_pieces.size()
		for t in ["wall", "ramp", "floor", "cone"]:
			p2.build_cooldown = 0.0
			ctrl.quick_build(t)
		var after := game_match.structures.player_pieces.size()
		print("[autotest] build: pieces %d -> %d, wood left %d" % [before, after, int(p2.mats["wood"])])
		# Destroy the floor's supports and check the cascade.
		var keys := game_match.structures.player_pieces.keys()
		for k in keys:
			var bp: BuildPiece = game_match.structures.player_pieces[k]
			if bp.team == p2.team and bp.piece_type == "ramp":
				bp.take_damage(9999.0)
		get_tree().create_timer(1.0).timeout.connect(func():
			var left := 0
			for k2 in game_match.structures.player_pieces.keys():
				var q: BuildPiece = game_match.structures.player_pieces[k2]
				if is_instance_valid(q) and q.team == p2.team:
					left += 1
			print("[autotest] after ramp destroyed, own pieces left: %d" % left))
		# Inventory: chest + pickup + heal.
		var ch := game_match.loot.nearest_chest(p2.global_position, 400.0)
		if ch:
			game_match.loot.open_chest(ch)
			print("[autotest] chest opened, pickups now %d" % game_match.loot.pickups.size())
		p2.pick_up(Items.consumable_item("mini_shield"))
		var slot := p2.find_slot_with("consumable", "mini_shield")
		p2.select_slot(slot)
		p2.start_heal()
		get_tree().create_timer(3.0).timeout.connect(func():
			print("[autotest] shield after mini shield: %.0f" % p2.shield))
	var limit := float(OS.get_environment("AUTOTEST_SECONDS")) if OS.get_environment("AUTOTEST_SECONDS") != "" else 60.0
	if _autotest_t > limit:
		var shot := OS.get_environment("AUTOTEST_SHOT")
		if shot != "":
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot)
		print("[autotest] done alive=%d" % game_match.alive_count())
		get_tree().quit()
