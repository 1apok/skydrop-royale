class_name BotBrain
extends Node
## Bot AI: utility-style decisions (drop, loot, rotate, fight, heal, build, cover) + steering and aiming.

var f: Fighter
var m: Node
var rng := RandomNumberGenerator.new()

# Personality / skill.
var skill := 0.5
var aggression := 0.6
var reaction := 0.35
var aim_error := 4.0
var turn_speed := 6.0
var build_skill := 0.5
var preferred_range := 25.0

var state := "bus"
var think_t := 0.0
var drop_target := Vector3.ZERO
var drop_jump_dist := 0.0
var move_target := Vector3.ZERO
var has_move := false
var target: Fighter
var target_visible := false
var target_seen_t := -100.0
var target_last_pos := Vector3.ZERO
var first_seen_t := -100.0
var noise_pos := Vector3.ZERO
var noise_t := -100.0
var loot_node: Node3D
var chest_node: StaticBody3D
var harvest_id := -1
var strafe := 1.0
var strafe_t := 0.0
var jump_t := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var avoid_dir := Vector3.ZERO
var avoid_t := 0.0
var build_cd := 0.0
var cover_point := Vector3.ZERO
var has_cover := false
var aim_noise := Vector3.ZERO
var roam_point := Vector3.ZERO
var break_piece: BuildPiece
var now := 0.0
var blacklist := {}
var loot_since := 0.0
var _last_loot_obj: Object = null


func setup(fighter: Fighter, match_node: Node, difficulty: int) -> void:
	f = fighter
	m = match_node
	rng.seed = fighter.seed_value * 7 + 3
	var base: float = [0.22, 0.48, 0.72, 0.93][clampi(difficulty, 0, 3)]
	skill = clampf(base + rng.randf_range(-0.12, 0.12), 0.05, 1.0)
	aggression = rng.randf_range(0.25, 1.0)
	reaction = lerpf(0.7, 0.12, skill)
	aim_error = lerpf(10.0, 1.0, skill)
	turn_speed = lerpf(3.0, 14.0, skill)
	build_skill = clampf(skill + rng.randf_range(-0.2, 0.1), 0.0, 1.0)
	preferred_range = rng.randf_range(10.0, 35.0)
	think_t = rng.randf() * 0.3


func choose_drop() -> void:
	var pois: Array = m.terrain.pois
	if rng.randf() < 0.75 and not pois.is_empty():
		var poi: Dictionary = pois[rng.randi() % pois.size()]
		var c: Vector3 = poi["pos"]
		var a := rng.randf() * TAU
		var d := rng.randf() * float(poi["radius"]) * 0.8
		drop_target = c + Vector3(cos(a) * d, 0, sin(a) * d)
	else:
		for i in 30:
			var p := Vector3(rng.randf_range(-300, 300), 0, rng.randf_range(-300, 300))
			if m.terrain.is_land(p.x, p.z, 2.0):
				drop_target = p
				break
	drop_target.y = m.terrain.height_at(drop_target.x, drop_target.z)
	drop_jump_dist = rng.randf_range(90.0, 220.0)


func _physics_process(delta: float) -> void:
	if f == null or not f.alive:
		return
	now = Time.get_ticks_msec() * 0.001
	build_cd -= delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = rng.randf_range(0.18, 0.3) * (1.6 if _far_from_camera() else 1.0)
		_think()
	match f.phase:
		"bus":
			_bus_logic()
		"freefall", "glide":
			_drop_steer()
		"ground":
			_ground_steer(delta)
			_aim_and_fire(delta)


func _far_from_camera() -> bool:
	var cam := f.get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_squared_to(f.global_position) > 150.0 * 150.0


# --- drop ---------------------------------------------------------------------------------------

func _bus_logic() -> void:
	if not m.bus_active:
		return
	var bp: Vector3 = m.bus_pos
	var d := Vector2(bp.x - drop_target.x, bp.z - drop_target.z).length()
	var ahead: float = (Vector2(drop_target.x - bp.x, drop_target.z - bp.z)).dot(Vector2(m.bus_dir.x, m.bus_dir.z))
	if d < drop_jump_dist or ahead < -20.0:
		m.eject(f)


func _drop_steer() -> void:
	var to := drop_target - f.global_position
	to.y = 0
	var dist := to.length()
	f.move_input = to.normalized() if dist > 3.0 else Vector3.ZERO
	f.look_yaw = atan2(-to.x, -to.z) if dist > 1.0 else f.look_yaw
	var height := f.global_position.y - drop_target.y
	f.want_dive = dist < height * 0.6


# --- thinking ----------------------------------------------------------------------------------

func _think() -> void:
	if f.phase != "ground":
		return
	_perceive()
	var storm: Storm = m.storm
	var pos := f.global_position
	var health := f.total_health()
	var outside := storm.distance_outside(pos)
	var to_next := Vector2(pos.x, pos.z).distance_to(storm.next_center) - storm.next_radius
	var storm_urgent := outside > -5.0 or (to_next > 0.0 and (storm.shrinking or storm.timer < to_next / 6.0 + 10.0))
	var has_weapon := f.has_usable_weapon()
	var heal_slot := _usable_heal_slot()
	var recently_hit := now - f.last_damage_time < 2.5

	# Melee fallback when unarmed and cornered.
	if not has_weapon and target != null and target.alive and target_visible and pos.distance_to(target.global_position) < 6.0:
		state = "melee"
		return
	# Fight decisions.
	if target != null and target.alive and has_weapon:
		var dist := pos.distance_to(target.global_position)
		var engage_range := 70.0 + aggression * 60.0
		if target_visible and dist < engage_range:
			if health < 45.0 and heal_slot >= 0 and aggression < 0.6 and not storm_urgent:
				state = "retreat"
			else:
				state = "fight"
			return
		if now - target_seen_t < 5.0 and aggression > 0.45 and dist < 90.0 and not storm_urgent:
			state = "chase"
			return
	if storm_urgent and (outside > -5.0 or to_next > 20.0):
		state = "rotate"
		_set_rotate_target()
		return
	if heal_slot >= 0 and not recently_hit and (f.hp < 75.0 or f.shield < 50.0):
		state = "heal"
		return
	if not has_weapon or _inventory_score() < 22.0 or _needs_ammo():
		if _find_loot():
			state = "loot"
			return
	if Game.settings["mode"] == "build" and int(f.mats["wood"]) + int(f.mats["stone"]) + int(f.mats["metal"]) < 90 and not recently_hit:
		harvest_id = m.foliage.nearest_harvestable(pos, 35.0)
		if harvest_id >= 0:
			state = "harvest"
			return
	if _find_loot(40.0):
		state = "loot"
		return
	if now - noise_t < 6.0 and aggression > 0.5 and pos.distance_to(noise_pos) < 110.0:
		state = "investigate"
		move_target = noise_pos
		has_move = true
		return
	state = "roam"
	if not has_move or pos.distance_to(roam_point) < 6.0 or rng.randf() < 0.02:
		_pick_roam_point()


func _perceive() -> void:
	var pos := f.eye_pos()
	var best: Fighter = null
	var best_score := 1e9
	var checks := 0
	# Always know who shot us recently.
	if f.last_attacker != null and f.last_attacker.alive and now - f.last_damage_time < 3.0:
		best = f.last_attacker
		best_score = -1.0
	var fwd := Vector3(-sin(f.look_yaw), 0, -cos(f.look_yaw))
	for other in m.fighters:
		var o: Fighter = other
		if o == f or not o.alive or o.phase == "bus":
			continue
		var d := pos.distance_to(o.global_position)
		var view := 140.0 if o.phase != "ground" else 110.0
		if d > view:
			continue
		var to := (o.global_position - f.global_position)
		to.y = 0
		var facing := fwd.dot(to.normalized()) if to.length() > 0.1 else 1.0
		if facing < -0.35 and d > 12.0:
			continue
		var score := d
		if checks < 4 and score < best_score:
			checks += 1
			if _has_los(o):
				best = o
				best_score = score
	if best != null:
		if best != target:
			first_seen_t = now
		target = best
		target_visible = _has_los(best) if best_score < 0.0 else true
		if target_visible:
			target_seen_t = now
			target_last_pos = best.global_position
	else:
		target_visible = false
		if target != null and (not target.alive or now - target_seen_t > 8.0):
			target = null


func _has_los(o: Fighter) -> bool:
	var space := f.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(f.eye_pos(), o.chest_pos(), 1)
	return space.intersect_ray(q).is_empty()


func _usable_heal_slot() -> int:
	for i in f.slots.size():
		var s: Dictionary = f.slots[i]
		if s.get("kind", "") == "consumable" and f.can_use(s):
			return i
	return -1


func _inventory_score() -> float:
	var sc := 0.0
	for s in f.slots:
		sc += Items.weapon_score(s)
	return sc


func _needs_ammo() -> bool:
	var w: Dictionary = f.slots[f.best_weapon_slot()] if f.best_weapon_slot() >= 0 else {}
	if w.is_empty():
		return false
	var kind: String = Items.WEAPONS[w["id"]]["ammo"]
	return int(f.ammo.get(kind, 0)) < 10


func _find_loot(radius := 70.0) -> bool:
	var pos := f.global_position
	chest_node = m.loot.nearest_chest(pos, radius, blacklist)
	loot_node = m.loot.nearest_pickup(pos, radius, Callable(self, "_wants_item_at"))
	if chest_node != null and (loot_node == null or pos.distance_to(chest_node.global_position) < pos.distance_to(loot_node.global_position) + 10.0):
		move_target = chest_node.global_position
		loot_node = null
		has_move = true
		return true
	if loot_node != null:
		chest_node = null
		move_target = loot_node.global_position
		has_move = true
		return true
	return false


func _wants_item_at(item: Dictionary) -> bool:
	if blacklist.has(item):
		return false
	return _wants_item(item)


## Gives up on loot targets that take too long to reach (e.g. on unreachable floors).
func _loot_timeout(obj: Object, item_key = null) -> bool:
	if obj != _last_loot_obj:
		_last_loot_obj = obj
		loot_since = now
		return false
	if now - loot_since > 12.0:
		blacklist[item_key if item_key != null else obj] = true
		_last_loot_obj = null
		return true
	return false


func _wants_item(item: Dictionary) -> bool:
	match item["kind"]:
		"ammo":
			for s in f.slots:
				if s.get("kind", "") == "weapon" and Items.WEAPONS[s["id"]]["ammo"] == item["id"]:
					return int(f.ammo[item["id"]]) < 60
			return false
		"mat":
			return Game.settings["mode"] == "build" and int(f.mats[item["id"]]) < 200
		"consumable":
			var existing := f.find_slot_with("consumable", item["id"])
			if existing >= 0:
				return int(f.slots[existing]["count"]) < int(Items.CONSUMABLES[item["id"]]["stack"])
			return f._empty_slot() >= 0
		"weapon":
			if f._empty_slot() >= 0:
				return f.find_slot_with("weapon", item["id"]) < 0 or Items.weapon_score(item) > _worst_weapon_score()
			return Items.weapon_score(item) > _worst_weapon_score() + 1.0
	return false


func _worst_weapon_score() -> float:
	var worst := 999.0
	for s in f.slots:
		if s.get("kind", "") == "weapon":
			worst = minf(worst, Items.weapon_score(s))
	return 0.0 if worst == 999.0 else worst


func _set_rotate_target() -> void:
	var storm: Storm = m.storm
	var c := storm.next_center
	var r := storm.next_radius * 0.6
	var pos := Vector2(f.global_position.x, f.global_position.z)
	var dir := (c - pos)
	var goal := c - dir.normalized() * minf(r, dir.length()) if dir.length() > 1.0 else c
	goal += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * r * 0.3
	move_target = Vector3(goal.x, m.terrain.height_at(goal.x, goal.y), goal.y)
	has_move = true


func _pick_roam_point() -> void:
	var storm: Storm = m.storm
	for i in 20:
		var a := rng.randf() * TAU
		var d := rng.randf() * storm.next_radius * 0.8
		var p := storm.next_center + Vector2(cos(a), sin(a)) * d
		if m.terrain.is_land(p.x, p.y, 1.5):
			roam_point = Vector3(p.x, m.terrain.height_at(p.x, p.y), p.y)
			move_target = roam_point
			has_move = true
			return


# --- movement --------------------------------------------------------------------------------

func _ground_steer(delta: float) -> void:
	f.want_jump = false
	f.want_crouch = false
	f.want_sprint = false
	f.ads = false
	var pos := f.global_position
	var desired := Vector3.ZERO
	match state:
		"fight":
			desired = _fight_move(delta)
		"retreat":
			desired = _retreat_move()
		"chase":
			desired = (target_last_pos - pos) if target != null else Vector3.ZERO
		"melee":
			desired = (target.global_position - pos) if target != null and target.alive else Vector3.ZERO
		"heal":
			desired = _heal_move()
		"loot":
			desired = _loot_move()
		"harvest":
			desired = _harvest_move()
		_:
			if has_move:
				desired = move_target - pos
				f.want_sprint = true
	desired.y = 0
	var dist := desired.length()
	var dir := desired.normalized() if dist > 0.6 else Vector3.ZERO
	# Obstacle avoidance.
	avoid_t -= delta
	var near_goal := state == "loot" and dist < 4.5
	if near_goal:
		avoid_dir = Vector3.ZERO
	elif dir != Vector3.ZERO and avoid_t <= 0.0:
		avoid_t = 0.12
		avoid_dir = _avoid(dir)
	if dir != Vector3.ZERO:
		dir = (dir + avoid_dir * 1.4).normalized()
	f.move_input = dir
	# Storm damage pushes urgency.
	if m.storm.is_outside(pos) and state != "fight":
		f.want_sprint = true
	# Stuck handling.
	var moved := pos.distance_to(last_pos)
	last_pos = pos
	if dir != Vector3.ZERO and moved < 0.03:
		stuck_t += delta
	else:
		stuck_t = maxf(0.0, stuck_t - delta * 2.0)
	if stuck_t > 0.6:
		f.want_jump = true
	if stuck_t > 1.4:
		_unstick(dir)
	if f.is_on_floor() and state != "fight" and dir != Vector3.ZERO and not target_visible:
		# Face movement direction while not fighting.
		var yaw := atan2(-dir.x, -dir.z)
		f.look_yaw = lerp_angle(f.look_yaw, yaw, clampf(delta * 6.0, 0, 1))
		f.look_pitch = lerpf(f.look_pitch, 0.0, delta * 4.0)


func _avoid(dir: Vector3) -> Vector3:
	var space := f.get_world_3d().direct_space_state
	var origin := f.global_position + Vector3(0, 0.6, 0)
	var side := dir.cross(Vector3.UP).normalized()
	var push := Vector3.ZERO
	break_piece = null
	for k in [-1.0, 0.0, 1.0]:
		var d: Vector3 = (dir + side * k * 0.6).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * 2.4, 1, [f.get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			if n.y > 0.6:
				continue
			push += Vector3(n.x, 0, n.z) * (1.0 if k == 0.0 else 0.6)
			if k == 0.0 and hit["collider"] is BuildPiece:
				break_piece = hit["collider"]
	if push.length() > 0.01:
		# Prefer sliding sideways along obstacles.
		var slide := side if side.dot(push) > 0 else -side
		return (push.normalized() * 0.5 + slide * 0.8)
	return Vector3.ZERO


func _unstick(dir: Vector3) -> void:
	# Break through blocking walls with the pickaxe, or build a ramp out, or sidestep.
	if break_piece != null and is_instance_valid(break_piece) and not break_piece.is_dead():
		if f.sel != -1 and state != "fight":
			f.select_slot(-1)
		var aim := break_piece.global_position + Vector3(0, 1.2, 0)
		var to := aim - f.eye_pos()
		if dir != Vector3.ZERO:
			# Aim along our heading at chest height (walls are thin, centers can be off to the side).
			to = Vector3(dir.x, clampf(to.normalized().y, -0.3, 0.3), dir.z)
		f.look_yaw = atan2(-to.x, -to.z)
		f.aim_dir = to.normalized()
		f.want_fire = true
		if break_piece.is_dead():
			break_piece = null
			stuck_t = 0.0
		return
	if Game.settings["mode"] == "build" and build_cd <= 0.0 and f.pick_build_mat() != "" and stuck_t > 2.0:
		var yaw := atan2(-dir.x, -dir.z)
		var pl: Dictionary = m.structures.compute_placement("ramp", f.global_position, yaw, 0.0)
		if f.try_build("ramp", pl) != null:
			build_cd = 1.0
			stuck_t = 0.0
			return
	if stuck_t > 3.0:
		var side := dir.cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
		move_target = f.global_position + side * 8.0 - dir * 3.0
		has_move = true
		stuck_t = 0.0


func _fight_move(delta: float) -> Vector3:
	if target == null:
		return Vector3.ZERO
	var pos := f.global_position
	var to := target.global_position - pos
	to.y = 0
	var dist := to.length()
	var dir := to.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = rng.randf_range(0.4, 1.4) * lerpf(1.5, 0.7, skill)
		strafe = -strafe if rng.randf() < 0.7 else strafe
	var wdef := f.weapon_def()
	var want := preferred_range
	if not wdef.is_empty():
		match String(f.current_weapon()["id"]):
			"pump": want = 6.0
			"smg": want = 12.0
			"pistol": want = 15.0
			"ar": want = preferred_range
			"sniper": want = 60.0
	var approach := 0.0
	if dist > want * 1.3:
		approach = 1.0
	elif dist < want * 0.6:
		approach = -0.7
	var move := side * strafe * lerpf(0.4, 0.9, skill) + dir * approach
	# Jump/crouch spice for skilled bots.
	jump_t -= delta
	if jump_t <= 0.0:
		jump_t = rng.randf_range(0.8, 2.5)
		if rng.randf() < skill * 0.45 and dist < 30.0:
			f.want_jump = true
	if dist > 35.0 and rng.randf() < 0.01:
		f.want_crouch = true
	# Defensive building when under fire.
	if Game.settings["mode"] == "build" and now - f.last_damage_time < 0.6 and build_cd <= 0.0 and rng.randf() < build_skill * 0.9:
		_defensive_build(dir)
	elif Game.settings["mode"] == "zero" and now - f.last_damage_time < 1.0 and f.total_health() < 70.0:
		if not has_cover or rng.randf() < 0.05:
			has_cover = _find_cover()
		if has_cover:
			return cover_point - pos
	f.ads = dist > 15.0 and rng.randf() < 0.9
	return move


func _defensive_build(dir_to_enemy: Vector3) -> void:
	if f.pick_build_mat() == "":
		return
	var yaw := atan2(-dir_to_enemy.x, -dir_to_enemy.z)
	var wall: Dictionary = m.structures.compute_placement("wall", f.global_position, yaw, 0.0)
	var placed := f.try_build("wall", wall)
	build_cd = lerpf(2.0, 0.6, build_skill)
	if placed != null and build_skill > 0.55 and rng.randf() < 0.6:
		# Ramp toward the enemy for height advantage.
		var ramp: Dictionary = m.structures.compute_placement("ramp", f.global_position, yaw, 0.0)
		f.build_cooldown = 0.0
		f.try_build("ramp", ramp)
		if rng.randf() < build_skill * 0.5:
			f.build_cooldown = 0.0
			f.try_build("floor", m.structures.compute_placement("floor", f.global_position, yaw, -1.0))


func _find_cover() -> bool:
	if target == null:
		return false
	var space := f.get_world_3d().direct_space_state
	var enemy_eye := target.eye_pos()
	var best := Vector3.ZERO
	var bd := 1e9
	for i in 10:
		var a := TAU * i / 10.0
		var p := f.global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 12.0)
		p.y = m.terrain.height_at(p.x, p.z)
		if p.y < 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(enemy_eye, p + Vector3(0, 1.2, 0), 1)
		if not space.intersect_ray(q).is_empty():
			var d := p.distance_to(f.global_position)
			if d < bd:
				bd = d
				best = p
	if bd < 1e9:
		cover_point = best
		return true
	return false


func _retreat_move() -> Vector3:
	if target == null:
		return Vector3.ZERO
	var away := f.global_position - target.global_position
	away.y = 0
	if Game.settings["mode"] == "build" and build_cd <= 0.0:
		_defensive_build(-away.normalized())
	if _find_cover():
		return cover_point - f.global_position
	return away


func _heal_move() -> Vector3:
	var slot := _usable_heal_slot()
	if slot < 0:
		state = "roam"
		return Vector3.ZERO
	if f.sel != slot:
		f.select_slot(slot)
	# Pulse the trigger so each heal item restarts once the previous one finishes.
	f.want_fire = not f.is_healing()
	if Game.settings["mode"] == "build" and build_cd <= 0.0 and f.pick_build_mat() != "" and now - target_seen_t < 10.0:
		# Box up while healing.
		for k in 4:
			var yaw := f.look_yaw + k * PI * 0.5
			f.build_cooldown = 0.0
			f.try_build("wall", m.structures.compute_placement("wall", f.global_position, yaw, 0.0))
		build_cd = 8.0
	return Vector3.ZERO


func _loot_move() -> Vector3:
	var pos := f.global_position
	if chest_node != null:
		if not is_instance_valid(chest_node) or chest_node.get_meta("opened", true):
			chest_node = null
			state = "roam"
			return Vector3.ZERO
		var to := chest_node.global_position - pos
		if _loot_timeout(chest_node):
			chest_node = null
			state = "roam"
			return Vector3.ZERO
		if Vector2(to.x, to.z).length() < 2.9 and absf(to.y) < 2.2:
			m.loot.open_chest(chest_node)
			chest_node = null
			think_t = 0.6
			return Vector3.ZERO
		_check_blocked(chest_node.global_position + Vector3(0, 0.5, 0), to.length())
		return to
	if loot_node != null:
		if not is_instance_valid(loot_node) or not m.loot.pickups.has(loot_node):
			loot_node = null
			return Vector3.ZERO
		var to2 := loot_node.global_position - pos
		if _loot_timeout(loot_node, loot_node.get_meta("item")):
			loot_node = null
			state = "roam"
			return Vector3.ZERO
		if Vector2(to2.x, to2.z).length() < 2.5 and absf(to2.y) < 2.2:
			m.pickup_item(f, loot_node)
			loot_node = null
			think_t = 0.1
			return Vector3.ZERO
		return to2
	return Vector3.ZERO


## When a loot target is close but walled off, break through with the pickaxe.
func _check_blocked(goal: Vector3, dist: float) -> void:
	if dist > 9.0 or now - loot_since < 2.0:
		return
	var space := f.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(f.eye_pos() - Vector3(0, 0.4, 0), goal, 1, [f.get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] is BuildPiece:
		break_piece = hit["collider"]
		stuck_t = maxf(stuck_t, 1.5)


func _harvest_move() -> Vector3:
	if harvest_id < 0:
		return Vector3.ZERO
	var rec: Dictionary = m.foliage.items[harvest_id]
	if not rec["alive"]:
		harvest_id = -1
		state = "roam"
		return Vector3.ZERO
	var p: Vector3 = rec["pos"]
	var to := p - f.global_position
	to.y = 0
	if to.length() < 2.2:
		if f.sel != -1:
			f.select_slot(-1)
		f.look_yaw = atan2(-to.x, -to.z)
		f.aim_dir = (p + Vector3(0, 1.0, 0) - f.eye_pos()).normalized()
		f.want_fire = true
		return Vector3.ZERO
	return to


# --- aiming / shooting ---------------------------------------------------------------------

func _aim_and_fire(delta: float) -> void:
	if state == "heal" or state == "harvest":
		return
	if state == "melee" and target != null and target.alive:
		if f.sel != -1:
			f.select_slot(-1)
		var tm := target.chest_pos() - f.eye_pos()
		f.look_yaw = atan2(-tm.x, -tm.z)
		f.aim_dir = tm.normalized()
		f.want_fire = tm.length() < 3.0
		return
	if stuck_t > 1.4 and break_piece != null:
		return
	f.want_fire = false
	if target == null or not target.alive or not target_visible:
		if state != "fight":
			f.aim_dir = Vector3(-sin(f.look_yaw), sin(f.look_pitch), -cos(f.look_yaw)).normalized()
		return
	var dist := f.global_position.distance_to(target.global_position)
	_choose_weapon(dist)
	var wdef := f.weapon_def()
	if wdef.is_empty():
		return
	# Aim point with lead, headshot bias and wandering error that shrinks while tracking.
	var head_bias := 0.3 if rng.randf() < skill * 0.5 else 0.0
	var aim_pt := target.chest_pos() + Vector3(0, head_bias, 0)
	var tracking := now - first_seen_t
	var err_deg := aim_error * (1.0 + 2.0 * maxf(0.0, 1.0 - tracking / 1.5))
	if target.velocity.length() > 4.0:
		err_deg *= 1.3
	aim_noise = aim_noise.lerp(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)), delta * 2.0)
	aim_pt += aim_noise * dist * tan(deg_to_rad(err_deg))
	aim_pt += target.velocity * reaction * (1.0 - skill * 0.6)
	var to := aim_pt - f.eye_pos()
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var k := clampf(delta * turn_speed, 0.0, 1.0)
	f.look_yaw = lerp_angle(f.look_yaw, want_yaw, k)
	f.look_pitch = lerpf(f.look_pitch, want_pitch, k)
	f.aim_dir = Vector3(-sin(f.look_yaw) * cos(f.look_pitch), sin(f.look_pitch), -cos(f.look_yaw) * cos(f.look_pitch)).normalized()
	if tracking < reaction:
		return
	var ang := rad_to_deg(f.aim_dir.angle_to(to.normalized()))
	var tol := clampf(160.0 / maxf(dist, 1.0), 2.0, 25.0)
	if dist > float(wdef["range"]) * 0.9:
		return
	if ang < tol:
		if String(f.current_weapon()["id"]) == "ar" and dist > 45.0 and f.bloom > 0.4:
			return # tap fire at range
		f.want_fire = true
	if int(f.current_weapon()["clip"]) <= 0 and not f.is_reloading():
		f.start_reload()


func _choose_weapon(dist: float) -> void:
	if f.is_reloading() and int(f.current_weapon().get("clip", 0)) > 0:
		return
	var prefer := []
	if dist < 9.0:
		prefer = ["pump", "smg", "ar", "pistol", "sniper"]
	elif dist < 25.0:
		prefer = ["smg", "ar", "pump", "pistol", "sniper"]
	elif dist < 70.0:
		prefer = ["ar", "smg", "pistol", "sniper", "pump"]
	else:
		prefer = ["sniper", "ar", "smg", "pistol", "pump"]
	for id in prefer:
		var i := f.find_slot_with("weapon", id)
		if i >= 0:
			var w: Dictionary = f.slots[i]
			var has_ammo := int(w["clip"]) > 0 or int(f.ammo.get(Items.WEAPONS[id]["ammo"], 0)) > 0
			if has_ammo:
				if f.sel != i and f.cooldown <= 0.05:
					f.select_slot(i)
				return
	if f.sel < 0 or f.current_weapon().is_empty():
		var b := f.best_weapon_slot()
		if b >= 0:
			f.select_slot(b)


func on_noise(pos: Vector3) -> void:
	if f.global_position.distance_to(pos) < 120.0:
		noise_pos = pos
		noise_t = Time.get_ticks_msec() * 0.001
