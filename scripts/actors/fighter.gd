class_name Fighter
extends CharacterBody3D
## Shared character logic for the player and bots: movement phases, health, inventory, combat, building.

signal died(victim: Fighter, killer: Fighter, cause: String)

const GRAVITY := 24.0
const JUMP_VEL := 7.8
const RUN_SPEED := 6.2
const SPRINT_SPEED := 8.2
const CROUCH_SPEED := 3.0
const ADS_SPEED := 3.8
const FREEFALL_H := 20.0
const FREEFALL_V := 34.0
const DIVE_V := 50.0
const GLIDE_H := 15.0
const GLIDE_V := 7.5
const GLIDER_AUTO := 32.0
const PICKAXE_RATE := 1.7
const PICKAXE_DMG := 20.0
const PICKAXE_BUILD_DMG := 50.0
const WATER_LEVEL := -1.25
const SWIM_SPEED := 3.4

var game_match: Node
var display_name := "Player"
var team := 0
var is_player := false
var alive := true
var phase := "bus"     # bus | freefall | glide | ground | dead

var hp := 100.0
var shield := 0.0
var overshield := 0.0
var overshield_max := 0.0
var _overshield_delay := 0.0

var slots: Array = [{}, {}, {}, {}, {}]
var sel := -1          # -1 pickaxe, 0..4 slot
var ammo := {"light": 0, "medium": 0, "heavy": 0, "shells": 0}
var mats := {"wood": 0, "stone": 0, "metal": 0}
var build_mat := "wood"

# Controller inputs (set every frame by Player or Bot).
var move_input := Vector3.ZERO   # world-space desired direction (len <= 1)
var look_yaw := 0.0
var look_pitch := 0.0
var aim_dir := Vector3.FORWARD
var want_jump := false
var want_crouch := false
var want_sprint := false
var want_fire := false
var want_dive := false
var ads := false

var crouched := false
var cooldown := 0.0
var reload_t := 0.0
var bloom := 0.0
var heal_t := 0.0
var heal_slot := -1
var build_cooldown := 0.0
var last_fire_time := -100.0
var _was_on_floor := true
var _fall_speed := 0.0
var _step_t := 0.0
var _trigger_released := true

var kills := 0
var damage_dealt := 0.0
var last_attacker: Fighter
var last_damage_time := -100.0
var place := 0

var visual: BodyVisual
var seed_value := 0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	visual = BodyVisual.new()
	add_child(visual)
	visual.build(seed_value)
	visual.set_weapon({})


func setup_mode(mode: String) -> void:
	if mode == "zero":
		overshield_max = 50.0
		overshield = 50.0


# --- helpers -------------------------------------------------------------------------

func eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.55 if not crouched else 1.15, 0)


func chest_pos() -> Vector3:
	return global_position + Vector3(0, 1.2 if not crouched else 0.9, 0)


func current_item() -> Dictionary:
	if sel < 0 or sel >= slots.size():
		return {}
	return slots[sel]


func current_weapon() -> Dictionary:
	var it := current_item()
	if it.get("kind", "") == "weapon":
		return it
	return {}


func weapon_def() -> Dictionary:
	var w := current_weapon()
	if w.is_empty():
		return {}
	return Items.WEAPONS[w["id"]]


func total_health() -> float:
	return hp + shield + overshield


func is_reloading() -> bool:
	return reload_t > 0.0


func is_healing() -> bool:
	return heal_t > 0.0


func select_slot(i: int) -> void:
	if i == sel:
		return
	sel = i
	reload_t = 0.0
	_cancel_heal()
	cooldown = maxf(cooldown, 0.25)
	visual.set_weapon(current_item())
	if not current_weapon().is_empty() and int(current_weapon()["clip"]) <= 0:
		start_reload()


func _cancel_heal() -> void:
	heal_t = 0.0
	heal_slot = -1


# --- per-frame --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return
	match phase:
		"bus":
			return
		"freefall":
			_process_freefall(delta)
		"glide":
			_process_glide(delta)
		"ground":
			_process_ground(delta)
	_process_combat(delta)
	_process_overshield(delta)
	var state := phase
	if phase == "ground":
		state = "ground" if is_on_floor() else "air"
		if is_healing():
			state = "heal"
	var horiz := Vector2(velocity.x, velocity.z).length()
	var holding_gun := not current_weapon().is_empty() and not is_healing()
	visual.animate(delta, state, horiz, look_pitch, holding_gun, crouched)
	visual.rotation.y = lerp_angle(visual.rotation.y, look_yaw if (holding_gun or phase != "ground" or horiz < 0.5) else atan2(-velocity.x, -velocity.z), clampf(delta * 12.0, 0, 1))


func _process_freefall(delta: float) -> void:
	var target := move_input * FREEFALL_H
	velocity.x = move_toward(velocity.x, target.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 30.0 * delta)
	var vmax := DIVE_V if want_dive else FREEFALL_V
	velocity.y = move_toward(velocity.y, -vmax, 40.0 * delta)
	move_and_slide()
	var ground := _ground_height()
	if global_position.y - ground < GLIDER_AUTO or is_on_floor():
		phase = "glide"
		Sfx.play3d("glider", global_position, -6.0)


func _process_glide(delta: float) -> void:
	var target := move_input * GLIDE_H
	velocity.x = move_toward(velocity.x, target.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 18.0 * delta)
	velocity.y = move_toward(velocity.y, -GLIDE_V, 60.0 * delta)
	move_and_slide()
	if is_on_floor() or global_position.y - _ground_height() < 0.6 or global_position.y < WATER_LEVEL + 0.4:
		phase = "ground"
		Sfx.play3d("land", global_position, -4.0)


func _ground_height() -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position - Vector3(0, 400, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -10.0
	return hit["position"].y


func _process_ground(delta: float) -> void:
	var on_floor := is_on_floor()
	crouched = want_crouch and on_floor
	var speed := RUN_SPEED
	if crouched:
		speed = CROUCH_SPEED
	elif ads:
		speed = ADS_SPEED
	elif want_sprint and move_input.length() > 0.5 and (Game.settings["mode"] == "zero" or true):
		speed = SPRINT_SPEED if Game.settings["mode"] == "zero" else RUN_SPEED * 1.12
	if is_healing():
		speed = minf(speed, 2.2)
	var swimming := is_swimming()
	if swimming:
		speed = SWIM_SPEED
	var target := move_input * speed
	var accel := 50.0 if on_floor else 12.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if on_floor:
		if not _was_on_floor and _fall_speed > 20.0:
			var dmg := (_fall_speed - 20.0) * 5.0
			take_damage(dmg, null, false, "fall")
			Sfx.play3d("land", global_position, 0.0)
		if want_jump:
			velocity.y = JUMP_VEL
			want_jump = false
		else:
			velocity.y = -0.5
		_step_t -= delta * Vector2(velocity.x, velocity.z).length()
		if _step_t <= 0.0:
			_step_t = 2.4
			if is_player or global_position.distance_squared_to(_cam_pos()) < 900.0:
				Sfx.play3d("step", global_position, -18.0 if not is_player else -14.0)
	elif swimming:
		# Float at the surface.
		velocity.y = clampf((WATER_LEVEL - global_position.y) * 4.0, -3.0, 3.0)
		_fall_speed = 0.0
	else:
		velocity.y -= GRAVITY * delta
		_fall_speed = -velocity.y
	_was_on_floor = on_floor
	if on_floor:
		_fall_speed = 0.0
	move_and_slide()
	# Mantle onto ledges in zero-build mode.
	if Game.settings["mode"] == "zero" and not on_floor and want_jump and velocity.y < 2.0:
		_try_mantle()
	if global_position.y < -40.0:
		take_damage(9999.0, null, false, "water")


func is_swimming() -> bool:
	return phase == "ground" and global_position.y < WATER_LEVEL + 0.15


func _cam_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _try_mantle() -> void:
	var fwd := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
	var space := get_world_3d().direct_space_state
	var top := global_position + fwd * 0.8 + Vector3(0, 2.6, 0)
	var q := PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 2.4, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var h: float = hit["position"].y - global_position.y
	if h > 0.8 and h < 2.4:
		velocity.y = 9.0
		want_jump = false


func _process_overshield(delta: float) -> void:
	if overshield_max <= 0.0:
		return
	_overshield_delay -= delta
	if _overshield_delay <= 0.0 and overshield < overshield_max:
		overshield = minf(overshield_max, overshield + 10.0 * delta)


func _process_combat(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	build_cooldown = maxf(0.0, build_cooldown - delta)
	bloom = maxf(0.0, bloom - delta * 3.5)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()
	if heal_t > 0.0:
		heal_t -= delta
		if heal_t <= 0.0:
			_finish_heal()
	if phase != "ground" or is_swimming():
		return
	if want_fire:
		var w := current_weapon()
		var item := current_item()
		if item.get("kind", "") == "consumable":
			if _trigger_released:
				start_heal()
		elif w.is_empty():
			if cooldown <= 0.0:
				pickaxe_swing()
		else:
			var def: Dictionary = Items.WEAPONS[w["id"]]
			var semi_ok: bool = _trigger_released or not is_player or bool(Game.settings.get("auto_fire", false))
			if (bool(def["auto"]) or semi_ok) and cooldown <= 0.0 and reload_t <= 0.0:
				fire_weapon()
		_trigger_released = false
	else:
		_trigger_released = true


# --- weapons --------------------------------------------------------------------------

func fire_weapon() -> void:
	var w := current_weapon()
	if w.is_empty():
		return
	var def: Dictionary = Items.WEAPONS[w["id"]]
	if int(w["clip"]) <= 0:
		start_reload()
		return
	_cancel_heal()
	w["clip"] = int(w["clip"]) - 1
	cooldown = 1.0 / float(def["rate"])
	last_fire_time = Time.get_ticks_msec() * 0.001
	var origin := eye_pos()
	var spread := float(def["spread_ads"]) if ads else float(def["spread_hip"])
	if crouched:
		spread *= 0.75
	if not is_on_floor():
		spread *= 1.6
	if Vector2(velocity.x, velocity.z).length() > 1.0:
		spread *= 1.25
	spread += bloom * (0.3 if ads else 1.0) * float(def["spread_hip"])
	if float(def["bloom"]) > 0.0:
		bloom = minf(bloom + float(def["bloom"]), 2.5)
	var dmg := float(def["damage"]) * float(Items.RARITY_DMG[int(w["rarity"])])
	var pellets := int(def["pellets"])
	var muzzle := visual.hand_r.global_position + aim_dir * 0.7
	for i in pellets:
		var dir := _spread_dir(aim_dir, spread)
		_hitscan(origin, dir, float(def["range"]), dmg, def, muzzle, i == 0)
	visual.recoil(1.0 if pellets == 1 else 2.0)
	if game_match:
		game_match.fx.muzzle(muzzle)
		game_match.on_gunshot(self, global_position)
	Sfx.play3d(String(w["id"]), muzzle, 2.0 if is_player else 0.0)
	if int(w["clip"]) <= 0:
		start_reload()


func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.001:
		return dir
	var r := deg_to_rad(deg) * sqrt(randf())
	var a := randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


func _hitscan(origin: Vector3, dir: Vector3, rng_m: float, dmg: float, def: Dictionary, muzzle: Vector3, show_tracer: bool) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng_m, 1 | 2, [get_rid()])
	var hit := space.intersect_ray(q)
	var end := origin + dir * rng_m
	if not hit.is_empty():
		end = hit["position"]
		var dist := origin.distance_to(end)
		var fall := 1.0
		var fs := float(def["falloff_start"])
		var fe := float(def["falloff_end"])
		if dist > fs:
			fall = lerpf(1.0, float(def["falloff_min"]), clampf((dist - fs) / maxf(fe - fs, 0.01), 0.0, 1.0))
		var collider: Object = hit["collider"]
		if collider is Fighter:
			var f: Fighter = collider
			var head: bool = end.y > f.global_position.y + (1.45 if not f.crouched else 1.05)
			var amount := dmg * fall * (float(def["head"]) if head else 1.0)
			_apply_hit(f, amount, head, String(def["name"]), end)
		elif collider is BuildPiece:
			var bp: BuildPiece = collider
			bp.take_damage(dmg * fall, self)
			if game_match:
				game_match.fx.impact(end, hit["normal"], Color(0.8, 0.7, 0.55))
				if is_player:
					game_match.fx.damage_number(end, dmg * fall, "build")
		else:
			if game_match:
				game_match.fx.impact(end, hit["normal"])
	if show_tracer and game_match:
		game_match.fx.tracer(muzzle, end)


func _apply_hit(f: Fighter, amount: float, head: bool, cause: String, pos: Vector3) -> void:
	if not f.alive:
		return
	var had_shield := f.shield + f.overshield > 0.0
	var dealt := f.take_damage(amount, self, head, cause)
	damage_dealt += dealt
	if game_match:
		game_match.fx.impact(pos, -aim_dir, Color(0.4, 0.8, 1.0) if had_shield else Color(1.0, 0.35, 0.3))
		if is_player:
			game_match.fx.damage_number(pos + Vector3(0, 0.3, 0), dealt, "head" if head else ("shield" if had_shield else "hp"))
			game_match.on_player_hit(head)


func pickaxe_swing() -> void:
	cooldown = 1.0 / PICKAXE_RATE
	visual.swing()
	var origin := eye_pos()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * 3.2, 1 | 2, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	if col is Fighter:
		_apply_hit(col, PICKAXE_DMG, false, "Кирка", pos)
		Sfx.play3d("pickaxe", pos, -2.0)
	elif col is BuildPiece:
		var bp: BuildPiece = col
		var mat := bp.harvest_type()
		var destroyed := bp.take_damage(PICKAXE_BUILD_DMG, self)
		if not bp.player_built or bp.team != team:
			add_mats(mat, 6 if not destroyed else 12)
		Sfx.play3d("hit_wood", pos, -2.0)
		if game_match:
			game_match.fx.impact(pos, hit["normal"], Color(0.75, 0.65, 0.5))
	elif col is StaticBody3D and (col as Node).has_meta("harvest"):
		var gained: Dictionary = game_match.foliage.damage(int((col as Node).get_meta("harvest")), PICKAXE_BUILD_DMG)
		for k in gained.keys():
			add_mats(k, int(gained[k]))
		Sfx.play3d("hit_wood", pos, -2.0)
		if game_match:
			game_match.fx.impact(pos, hit["normal"], Color(0.7, 0.6, 0.45))
	else:
		Sfx.play3d("pickaxe", pos, -6.0)


func add_mats(kind: String, amount: int) -> void:
	if not mats.has(kind):
		return
	mats[kind] = mini(Items.MAT_MAX, int(mats[kind]) + amount)


func start_reload() -> void:
	var w := current_weapon()
	if w.is_empty() or reload_t > 0.0:
		return
	var def: Dictionary = Items.WEAPONS[w["id"]]
	if int(w["clip"]) >= int(def["mag"]):
		return
	if int(ammo.get(def["ammo"], 0)) <= 0:
		return
	_cancel_heal()
	reload_t = float(def["reload"]) * float(Items.RARITY_RELOAD[int(w["rarity"])])
	if is_player or global_position.distance_squared_to(_cam_pos()) < 400.0:
		Sfx.play3d("reload", global_position + Vector3(0, 1.2, 0), -8.0)


func _finish_reload() -> void:
	reload_t = 0.0
	var w := current_weapon()
	if w.is_empty():
		return
	var def: Dictionary = Items.WEAPONS[w["id"]]
	var kind: String = def["ammo"]
	var need := int(def["mag"]) - int(w["clip"])
	var take := mini(need, int(ammo.get(kind, 0)))
	w["clip"] = int(w["clip"]) + take
	ammo[kind] = int(ammo[kind]) - take


# --- consumables -------------------------------------------------------------------------

func can_use(item: Dictionary) -> bool:
	if item.get("kind", "") != "consumable":
		return false
	var c: Dictionary = Items.CONSUMABLES[item["id"]]
	if int(c["hp"]) > 0 and hp < float(c["hp_cap"]):
		return true
	if int(c["shield"]) > 0 and shield < float(c["shield_cap"]):
		return true
	return false


func start_heal() -> void:
	var item := current_item()
	if not can_use(item) or is_healing():
		return
	reload_t = 0.0
	heal_slot = sel
	heal_t = float(Items.CONSUMABLES[item["id"]]["time"])
	if is_player:
		Sfx.play("ui", -6.0)


func _finish_heal() -> void:
	heal_t = 0.0
	if heal_slot < 0 or heal_slot != sel:
		heal_slot = -1
		return
	var item: Dictionary = slots[heal_slot]
	if item.is_empty():
		return
	var c: Dictionary = Items.CONSUMABLES[item["id"]]
	if int(c["hp"]) > 0:
		hp = minf(maxf(hp, minf(hp + float(c["hp"]), float(c["hp_cap"]))), 100.0)
	if int(c["shield"]) > 0:
		shield = minf(maxf(shield, minf(shield + float(c["shield"]), float(c["shield_cap"]))), 100.0)
	item["count"] = int(item["count"]) - 1
	if is_player or global_position.distance_squared_to(_cam_pos()) < 400.0:
		Sfx.play3d("heal", global_position + Vector3(0, 1, 0), -6.0)
	if int(item["count"]) <= 0:
		slots[heal_slot] = {}
		visual.set_weapon({})
		var best := best_weapon_slot()
		select_slot(best)
	heal_slot = -1


func has_usable_weapon() -> bool:
	for s in slots:
		if s.get("kind", "") == "weapon":
			if int(s["clip"]) > 0 or int(ammo.get(Items.WEAPONS[s["id"]]["ammo"], 0)) > 0:
				return true
	return false


func best_weapon_slot() -> int:
	var best := -1
	var bs := 0.0
	for i in slots.size():
		var s := Items.weapon_score(slots[i])
		if s > bs:
			bs = s
			best = i
	return best


func find_slot_with(kind: String, id := "") -> int:
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s.get("kind", "") == kind and (id == "" or s.get("id", "") == id):
			return i
	return -1


# --- inventory ---------------------------------------------------------------------------

## Picks up an item. Returns the leftover item to drop (or {} if fully consumed).
func pick_up(item: Dictionary) -> Dictionary:
	match item["kind"]:
		"ammo":
			ammo[item["id"]] = int(ammo.get(item["id"], 0)) + int(item["count"])
			return {}
		"mat":
			add_mats(String(item["id"]), int(item["count"]))
			return {}
		"consumable":
			var stack := int(Items.CONSUMABLES[item["id"]]["stack"])
			var existing := find_slot_with("consumable", item["id"])
			if existing >= 0:
				var s: Dictionary = slots[existing]
				var room := stack - int(s["count"])
				var add := mini(room, int(item["count"]))
				s["count"] = int(s["count"]) + add
				var left := int(item["count"]) - add
				if left <= 0:
					return {}
				item = item.duplicate()
				item["count"] = left
				return item
			var empty := _empty_slot()
			if empty >= 0:
				slots[empty] = item.duplicate()
				if sel == empty:
					visual.set_weapon(current_item())
				return {}
			return item
		"weapon":
			# A fresh weapon comes with one magazine of reserve ammo if we are low on that type.
			var wdef: Dictionary = Items.WEAPONS[item["id"]]
			var akind: String = wdef["ammo"]
			if int(ammo.get(akind, 0)) < int(wdef["mag"]):
				ammo[akind] = int(ammo.get(akind, 0)) + int(wdef["mag"])
			var empty2 := _empty_slot()
			if empty2 >= 0:
				slots[empty2] = item.duplicate()
				if sel < 0 or current_item().is_empty():
					select_slot(empty2)
				return {}
			# Swap with the selected slot (or worst weapon if pickaxe is held).
			var target := sel
			if target < 0:
				var worst := 999.0
				for i in slots.size():
					var sc := Items.weapon_score(slots[i])
					if slots[i].get("kind", "") == "weapon" and sc < worst:
						worst = sc
						target = i
			if target < 0:
				return item
			var old: Dictionary = slots[target]
			slots[target] = item.duplicate()
			sel = -2
			select_slot(target)
			return old
	return item


func _empty_slot() -> int:
	for i in slots.size():
		if (slots[i] as Dictionary).is_empty():
			return i
	return -1


func drop_all() -> Array:
	var out := []
	for s in slots:
		if not s.is_empty():
			out.append(s)
	for k in ammo.keys():
		if int(ammo[k]) > 0:
			out.append({"kind": "ammo", "id": k, "count": int(ammo[k])})
	for k in mats.keys():
		if int(mats[k]) > 0:
			out.append({"kind": "mat", "id": k, "count": mini(int(mats[k]), 300)})
	return out


# --- damage --------------------------------------------------------------------------------

func take_damage(amount: float, attacker: Fighter, headshot := false, cause := "") -> float:
	if not alive or amount <= 0.0:
		return 0.0
	var dealt := 0.0
	var left := amount
	_overshield_delay = 6.0
	if cause != "storm" and cause != "fall":
		var o := minf(overshield, left)
		overshield -= o
		left -= o
		dealt += o
		var s := minf(shield, left)
		shield -= s
		left -= s
		dealt += s
	var h := minf(hp, left)
	hp -= h
	dealt += h
	if attacker != null and attacker != self:
		last_attacker = attacker
	last_damage_time = Time.get_ticks_msec() * 0.001
	_cancel_heal()
	if game_match:
		game_match.on_damaged(self, attacker, dealt)
	if hp <= 0.0:
		die(attacker if attacker != null else last_attacker, cause)
	return dealt


func die(killer: Fighter, cause: String) -> void:
	if not alive:
		return
	alive = false
	phase = "dead"
	velocity = Vector3.ZERO
	collision_layer = 0
	if killer != null and killer != self:
		killer.kills += 1
	died.emit(self, killer, cause)
	# Simple fall-over then fade out.
	var t := create_tween()
	t.tween_property(visual, "rotation:x", -PI * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(visual, "scale", Vector3(1, 0.01, 1), 0.4).set_delay(0.6)
	t.tween_callback(func(): visual.visible = false)


# --- building ------------------------------------------------------------------------------

func pick_build_mat() -> String:
	if int(mats[build_mat]) >= Items.BUILD_COST:
		return build_mat
	for m in ["wood", "stone", "metal"]:
		if int(mats[m]) >= Items.BUILD_COST:
			return m
	return ""


func try_build(type: String, placement: Dictionary) -> BuildPiece:
	if Game.settings["mode"] != "build" or phase != "ground" or build_cooldown > 0.0:
		return null
	if not bool(placement.get("valid", false)):
		return null
	var m := pick_build_mat()
	if m == "":
		return null
	var p: BuildPiece = game_match.structures.place_player_piece(type, m, placement, team)
	if p == null:
		return null
	mats[m] = int(mats[m]) - Items.BUILD_COST
	build_cooldown = 0.12
	return p
