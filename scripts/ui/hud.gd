class_name HUD
extends CanvasLayer
## In-match HUD: health, slots, minimap, storm, kill feed, crosshair, prompts, pause, results.

signal exit_to_menu

const SHORT := {"ar": "ВИНТОВКА", "smg": "ПП", "pump": "ДРОБОВИК", "sniper": "СНАЙПЕР", "pistol": "ПИСТОЛЕТ",
	"bandage": "БИНТЫ", "medkit": "АПТЕЧКА", "mini_shield": "МАЛ. ЩИТ", "big_shield": "БОЛ. ЩИТ"}

var m: Match
var ctrl: PlayerController
var touch: TouchControls
var overlay: Control
var font: Font
var map_tex: ImageTexture
var map_open := false
var paused := false
var pause_panel: Control
var settings_panel: SettingsPanel
var results_panel: Control
var feed: Array = []        # {text, t, hl}
var toast_text := ""
var toast_t := 0.0
var hit_t := 0.0
var hit_head := false
var dmg_dirs: Array = []    # {dir(Vector3), t}
var elim_text := ""
var elim_t := 0.0
var fps_label: Label
var u := 1.0
var inset := Rect2()   # x = left, y = top, w = right, h = bottom


func setup(match_node: Match, controller: PlayerController) -> void:
	m = match_node
	ctrl = controller
	font = ThemeDB.fallback_font
	map_tex = ImageTexture.create_from_image(m.map_image)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	touch = TouchControls.new()
	touch.player_ctrl = ctrl
	touch.visible = Game.is_mobile or OS.has_feature("touch_debug")
	add_child(touch)
	fps_label = UIKit.label("", 16)
	fps_label.position = Vector2(8, 4)
	add_child(fps_label)
	m.kill_feed.connect(func(text: String, hl: bool): feed.append({"text": text, "t": 7.0, "hl": hl}))
	m.match_finished.connect(_on_finished)


func is_menu_open() -> bool:
	return paused or results_panel != null


func toast(text: String) -> void:
	toast_text = text
	toast_t = 1.6


func on_hitmarker(head: bool) -> void:
	hit_t = 0.18
	hit_head = head


func on_player_damaged(attacker: Fighter, _amount: float) -> void:
	if attacker != null:
		dmg_dirs.append({"pos": attacker.global_position, "t": 1.2})
	ctrl.add_shake(0.3)


func on_player_elimination(victim: Fighter) -> void:
	elim_text = "Устранён: " + victim.display_name
	elim_t = 2.5


func toggle_map() -> void:
	map_open = not map_open


func _process(delta: float) -> void:
	u = overlay.size.y / 720.0
	inset = Game.safe_insets(overlay.size)
	toast_t -= delta
	hit_t -= delta
	elim_t -= delta
	for e in feed:
		e["t"] = float(e["t"]) - delta
	while not feed.is_empty() and float(feed[0]["t"]) <= 0.0:
		feed.pop_front()
	if feed.size() > 5:
		feed.pop_front()
	for d in dmg_dirs:
		d["t"] = float(d["t"]) - delta
	dmg_dirs = dmg_dirs.filter(func(d): return float(d["t"]) > 0.0)
	fps_label.visible = bool(Game.settings["show_fps"])
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	fps_label.position = Vector2(8 + inset.position.x, 4)
	if touch:
		touch.show_interact = ctrl.interact_target != null
		touch.interact_label = ctrl.interact_text
		touch.enabled_input = not is_menu_open()
		touch.visible = (Game.is_mobile or OS.has_feature("touch_debug")) and not is_menu_open() and m.player.alive
	overlay.queue_redraw()


# --- drawing -------------------------------------------------------------------------------

func _text(pos: Vector2, text: String, size: float, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := true) -> void:
	var fs := int(size * u)
	if outline:
		overlay.draw_string_outline(font, pos, text, align, width, fs, int(max(2.0, 4 * u)), Color(0, 0, 0, 0.75 * col.a))
	overlay.draw_string(font, pos, text, align, width, fs, col)


func _text_center(pos: Vector2, text: String, size: float, col := Color.WHITE) -> void:
	var fs := int(size * u)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(pos - Vector2(w * 0.5, 0), text, size, col)


func _draw_overlay() -> void:
	var s := overlay.size
	var p := m.player
	var target := p
	if not p.alive and ctrl.spectate != null:
		target = ctrl.spectate
	# Storm tint / low health.
	if m.storm.active and target.alive and m.storm.is_outside(target.global_position):
		overlay.draw_rect(Rect2(Vector2.ZERO, s), Color(0.5, 0.1, 0.8, 0.22))
	if p.alive and p.hp < 30.0:
		var a := (1.0 - p.hp / 30.0) * 0.35
		_vignette(s, Color(0.8, 0.0, 0.0, a))
	# Sniper scope.
	if p.ads and String(p.current_weapon().get("id", "")) == "sniper":
		_scope(s)
	_draw_crosshair(s)
	_draw_damage_dirs(s)
	_draw_top(s)
	_draw_feed(s)
	_draw_minimap(s)
	if p.alive:
		_draw_health(s)
		_draw_slots(s)
		_draw_mats(s)
		_draw_progress(s)
		if ctrl.interact_target != null and not Game.is_mobile:
			_text_center(Vector2(s.x * 0.5, s.y * 0.62), "[E] " + ctrl.interact_text, 22, Color(1, 0.92, 0.6))
	if toast_t > 0.0:
		_text_center(Vector2(s.x * 0.5, s.y * 0.35), toast_text, 24, Color(1, 0.6, 0.5, clampf(toast_t * 2.0, 0, 1)))
	if elim_t > 0.0:
		_text_center(Vector2(s.x * 0.5, s.y * 0.25), elim_text, 30, Color(1.0, 0.85, 0.3, clampf(elim_t, 0, 1)))
	if map_open:
		_draw_big_map(s)


func _vignette(s: Vector2, col: Color) -> void:
	var steps := 8
	for i in steps:
		var k := float(i) / steps
		var inset := k * s.y * 0.25
		var c := Color(col.r, col.g, col.b, col.a * (1.0 - k) / steps * 2.0)
		overlay.draw_rect(Rect2(Vector2(0, 0), Vector2(s.x, inset + 4)), c)
		overlay.draw_rect(Rect2(Vector2(0, s.y - inset - 4), Vector2(s.x, inset + 4)), c)


func _scope(s: Vector2) -> void:
	var c := s * 0.5
	var r := s.y * 0.44
	var pts := PackedVector2Array()
	# Black mask: draw thick ring.
	overlay.draw_arc(c, r + s.x * 0.5, 0, TAU, 64, Color.BLACK, s.x, true)
	overlay.draw_rect(Rect2(0, 0, c.x - r, s.y), Color.BLACK)
	overlay.draw_rect(Rect2(c.x + r, 0, s.x - c.x - r, s.y), Color.BLACK)
	overlay.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.8), 2.0 * u)
	overlay.draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.8), 2.0 * u)
	overlay.draw_circle(c, 3 * u, Color(1, 0.2, 0.2))
	pts.clear()


func _draw_crosshair(s: Vector2) -> void:
	var p := m.player
	if not p.alive or p.phase != "ground":
		return
	var c := s * 0.5
	if ctrl.build_mode:
		overlay.draw_circle(c, 3 * u, Color(1, 1, 1, 0.9))
	elif p.current_weapon().is_empty():
		overlay.draw_circle(c, 3 * u, Color(1, 1, 1, 0.85))
	else:
		var def := p.weapon_def()
		var spread := float(def["spread_ads"]) if p.ads else float(def["spread_hip"])
		spread += p.bloom * float(def["spread_hip"]) * (0.3 if p.ads else 1.0)
		var cam := ctrl.cam
		var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(cam.fov * 0.5)) * s.y * 0.5
		var gap := maxf(px, 4 * u)
		var len := 9 * u
		var col := Color(1, 1, 1, 0.9)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			overlay.draw_line(c + d * gap, c + d * (gap + len), Color(0, 0, 0, 0.6), 4 * u)
			overlay.draw_line(c + d * gap, c + d * (gap + len), col, 2 * u)
		if int(def["pellets"]) > 1:
			overlay.draw_arc(c, gap, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5 * u)
	if hit_t > 0.0:
		var hc := Color(1, 0.85, 0.2) if hit_head else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			overlay.draw_line(c + d * 7 * u, c + d * 15 * u, hc, 3 * u)


func _draw_damage_dirs(s: Vector2) -> void:
	var c := s * 0.5
	var p := m.player
	for d in dmg_dirs:
		var to: Vector3 = d["pos"] - p.global_position
		var ang := atan2(to.x, -to.z) + ctrl.yaw
		var dir := Vector2(sin(-ang), -cos(-ang))
		var a := clampf(float(d["t"]), 0.0, 1.0)
		var base_ang := dir.angle()
		overlay.draw_arc(c, 90 * u, base_ang - 0.35, base_ang + 0.35, 16, Color(1, 0.15, 0.1, 0.8 * a), 7 * u)


func _draw_top(s: Vector2) -> void:
	var p := m.player
	var cx := s.x * 0.5
	if m.state == "countdown":
		_text_center(Vector2(cx, s.y * 0.3), "Взлёт через %d" % int(ceil(m.countdown)), 40, UIKit.ACCENT)
	if p.phase == "bus":
		_text_center(Vector2(cx, s.y * 0.72), "Нажми ▲ ПРЫЖОК, чтобы десантироваться" if Game.is_mobile else "Нажми ПРОБЕЛ, чтобы десантироваться", 26, Color(1, 1, 1))
	elif p.phase == "freefall":
		_text_center(Vector2(cx, s.y * 0.75), "Высота: %d м" % int(p.global_position.y - m.terrain.height_at(p.global_position.x, p.global_position.z)), 22)
	var info := "Живых: %d    Устранения: %d" % [m.alive_count(), p.kills]
	_text_center(Vector2(cx, 36 * u), info, 24)
	if m.storm.active:
		var col := Color(0.85, 0.6, 1.0) if not m.storm.shrinking else Color(1.0, 0.5, 0.9)
		_text_center(Vector2(cx, 64 * u), m.storm.status_text(), 20, col)


func _draw_feed(s: Vector2) -> void:
	var y := 90.0 * u
	for e in feed:
		var a := clampf(float(e["t"]), 0.0, 1.0)
		var col := Color(1.0, 0.85, 0.35, a) if e["hl"] else Color(1, 1, 1, a * 0.9)
		_text(Vector2(16 * u + inset.position.x, y), String(e["text"]), 18, col)
		y += 26 * u


func _world_to_map(p: Vector3, rect: Rect2) -> Vector2:
	return rect.position + Vector2((p.x + Terrain.HALF) / Terrain.SIZE, (p.z + Terrain.HALF) / Terrain.SIZE) * rect.size


func _draw_minimap(s: Vector2) -> void:
	if map_open:
		return
	var size := 190.0 * u
	var rect := Rect2(Vector2(s.x - size - 16 * u - inset.size.x, 16 * u), Vector2(size, size))
	var p := m.player
	var target := p if p.alive or ctrl.spectate == null else ctrl.spectate
	# Zoomed view centered on player: draw a sub-region of the map texture.
	var zoom := 3.0
	var tex_size := Vector2(map_tex.get_width(), map_tex.get_height())
	var center_uv := Vector2((target.global_position.x + Terrain.HALF) / Terrain.SIZE, (target.global_position.z + Terrain.HALF) / Terrain.SIZE)
	var half_uv := Vector2(0.5, 0.5) / zoom
	var src := Rect2((center_uv - half_uv) * tex_size, half_uv * 2.0 * tex_size)
	overlay.draw_rect(rect.grow(3 * u), Color(0, 0, 0, 0.6))
	overlay.draw_texture_rect_region(map_tex, rect, src)
	var to_screen := func(w: Vector3) -> Vector2:
		var uv := Vector2((w.x + Terrain.HALF) / Terrain.SIZE, (w.z + Terrain.HALF) / Terrain.SIZE)
		return rect.position + (uv - (center_uv - half_uv)) / (half_uv * 2.0) * rect.size
	var px_per_m := rect.size.x / (Terrain.SIZE / zoom)
	if m.storm.active:
		var sc: Vector2 = to_screen.call(Vector3(m.storm.center.x, 0, m.storm.center.y))
		var nc: Vector2 = to_screen.call(Vector3(m.storm.next_center.x, 0, m.storm.next_center.y))
		_clipped_circle(sc, m.storm.radius * px_per_m, rect, Color(0.75, 0.3, 1.0), 2.5 * u)
		_clipped_circle(nc, m.storm.next_radius * px_per_m, rect, Color(1, 1, 1, 0.9), 1.5 * u)
	_arrow(rect.get_center(), ctrl.yaw, Color(1, 0.9, 0.3))
	overlay.draw_rect(rect, Color(1, 1, 1, 0.5), false, 2 * u)


func _clipped_circle(c: Vector2, r: float, rect: Rect2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var n := 96
	for i in n + 1:
		var a := TAU * i / n
		var pt := c + Vector2(cos(a), sin(a)) * r
		if rect.has_point(pt):
			pts.append(pt)
		else:
			if pts.size() > 1:
				overlay.draw_polyline(pts, col, w)
			pts = PackedVector2Array()
	if pts.size() > 1:
		overlay.draw_polyline(pts, col, w)


func _arrow(c: Vector2, yaw: float, col: Color) -> void:
	var dir := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([c + dir * 9 * u, c - dir * 6 * u + side * 6 * u, c - dir * 3 * u, c - dir * 6 * u - side * 6 * u])
	overlay.draw_colored_polygon(pts, col)
	overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 1.5 * u)


func _draw_big_map(s: Vector2) -> void:
	overlay.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var size := s.y * 0.86
	var rect := Rect2(Vector2(s.x * 0.5 - size * 0.5, s.y * 0.07), Vector2(size, size))
	overlay.draw_texture_rect(map_tex, rect, false)
	overlay.draw_rect(rect, Color(1, 1, 1, 0.6), false, 2 * u)
	var k := size / Terrain.SIZE
	for poi in m.terrain.pois:
		var pp := _world_to_map(poi["pos"], rect)
		overlay.draw_circle(pp, 4 * u, Color(1, 1, 1, 0.9))
		_text_center(pp + Vector2(0, -8 * u), String(poi["name"]).to_upper(), 15, Color(1, 1, 1))
	if m.bus_active:
		overlay.draw_line(_world_to_map(m.bus_start, rect), _world_to_map(m.bus_end, rect), Color(1, 1, 1, 0.6), 2 * u)
		overlay.draw_circle(_world_to_map(m.bus_pos, rect), 7 * u, Color(0.3, 0.7, 1.0))
	if m.storm.active:
		overlay.draw_arc(_world_to_map(Vector3(m.storm.center.x, 0, m.storm.center.y), rect), m.storm.radius * k, 0, TAU, 96, Color(0.75, 0.3, 1.0), 3 * u)
		overlay.draw_arc(_world_to_map(Vector3(m.storm.next_center.x, 0, m.storm.next_center.y), rect), m.storm.next_radius * k, 0, TAU, 96, Color.WHITE, 2 * u)
	_arrow(_world_to_map(m.player.global_position, rect), ctrl.yaw, Color(1, 0.9, 0.3))
	_text_center(Vector2(s.x * 0.5, rect.end.y + 26 * u), "Нажми КАРТА, чтобы закрыть" if Game.is_mobile else "[M] закрыть карту", 18)


func _draw_health(s: Vector2) -> void:
	var p := m.player
	var x := 20.0 * u + inset.position.x
	var y := s.y - 70.0 * u
	if touch.visible:
		y = 48.0 * u + 150 * u
	var w := 260.0 * u
	var h := 20.0 * u
	if p.overshield_max > 0.0:
		overlay.draw_rect(Rect2(x, y - h * 2.2, w, h * 0.7), Color(0, 0, 0, 0.5))
		overlay.draw_rect(Rect2(x, y - h * 2.2, w * p.overshield / p.overshield_max, h * 0.7), Color(0.85, 0.95, 1.0))
	overlay.draw_rect(Rect2(x, y - h * 1.2, w, h), Color(0, 0, 0, 0.5))
	overlay.draw_rect(Rect2(x, y - h * 1.2, w * clampf(p.shield / 100.0, 0.0, 1.0), h), Color(0.25, 0.65, 1.0))
	_text(Vector2(x + w + 8 * u, y - h * 0.35), str(int(ceil(p.shield))), 18, Color(0.6, 0.85, 1.0))
	overlay.draw_rect(Rect2(x, y + h * 0.1, w, h), Color(0, 0, 0, 0.5))
	overlay.draw_rect(Rect2(x, y + h * 0.1, w * clampf(p.hp / 100.0, 0.0, 1.0), h), Color(0.35, 0.9, 0.35))
	_text(Vector2(x + w + 8 * u, y + h * 0.95), str(int(ceil(p.hp))), 18, Color(0.6, 1.0, 0.6))


func _draw_slots(s: Vector2) -> void:
	var p := m.player
	var slot_w := 86.0 * u
	var total := 6
	var x0 := s.x * 0.5 - slot_w * total * 0.5
	var y := s.y - 100.0 * u
	for i in total:
		var rect := Rect2(x0 + i * slot_w, y, slot_w - 6 * u, 84 * u)
		var idx := i - 1
		var selected := p.sel == idx and not ctrl.build_mode
		overlay.draw_rect(rect, Color(0.05, 0.07, 0.14, 0.75))
		if i == 0:
			_text_center(rect.get_center() + Vector2(0, 6 * u), "КИРКА", 15, Color(0.85, 0.85, 0.9))
		else:
			var item: Dictionary = p.slots[idx]
			if not item.is_empty():
				var col := Items.item_color(item)
				overlay.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 8 * u), Vector2(rect.size.x, 8 * u)), col)
				_text_center(rect.get_center() + Vector2(0, -6 * u), String(SHORT.get(item["id"], "?")), 14, col.lightened(0.3))
				if item["kind"] == "weapon":
					var def: Dictionary = Items.WEAPONS[item["id"]]
					_text_center(rect.get_center() + Vector2(0, 20 * u), "%d | %d" % [int(item["clip"]), int(p.ammo.get(def["ammo"], 0))], 15)
				else:
					_text_center(rect.get_center() + Vector2(0, 20 * u), "×%d" % int(item["count"]), 16)
		if selected:
			overlay.draw_rect(rect.grow(2 * u), UIKit.ACCENT, false, 3 * u)
		else:
			overlay.draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.5 * u)
		if not Game.is_mobile and i > 0:
			_text(rect.position + Vector2(5 * u, 16 * u), str(i), 13, Color(1, 1, 1, 0.6))


func _draw_mats(s: Vector2) -> void:
	if Game.settings["mode"] != "build":
		return
	var p := m.player
	var x := s.x * 0.5 + 6 * 86.0 * u * 0.5 + 14 * u
	var y := s.y - 92.0 * u
	if touch.visible:
		x = s.x - 250 * u - inset.size.x
		y = 230 * u
	var names := {"wood": "ДЕРЕВО", "stone": "КАМЕНЬ", "metal": "МЕТАЛЛ"}
	var cols := {"wood": Color(0.9, 0.7, 0.45), "stone": Color(0.8, 0.8, 0.82), "metal": Color(0.6, 0.8, 0.95)}
	var i := 0
	for k in ["wood", "stone", "metal"]:
		var r := Rect2(x, y + i * 26 * u, 150 * u, 24 * u)
		var sel: bool = p.build_mat == k
		overlay.draw_rect(r, Color(0, 0, 0, 0.55 if sel else 0.3))
		if sel:
			overlay.draw_rect(r, cols[k], false, 2 * u)
		_text(r.position + Vector2(6 * u, 18 * u), "%s  %d" % [names[k], int(p.mats[k])], 15, cols[k])
		i += 1
	if ctrl.build_mode:
		var names2 := {"wall": "СТЕНА", "floor": "ПОЛ", "ramp": "ЛЕСТНИЦА", "cone": "КРЫША"}
		_text(Vector2(x, y - 10 * u), "Стройка: " + names2[ctrl.build_type] + ("" if Game.is_mobile else "   [Z X V B, T — материал]"), 15, UIKit.ACCENT2)


func _draw_progress(s: Vector2) -> void:
	var p := m.player
	var t := 0.0
	var label := ""
	if p.is_reloading():
		var def := p.weapon_def()
		if not def.is_empty():
			t = 1.0 - p.reload_t / (float(def["reload"]) * float(Items.RARITY_RELOAD[int(p.current_weapon()["rarity"])]))
			label = "Перезарядка"
	elif p.is_healing():
		var item := p.current_item()
		if not item.is_empty():
			t = 1.0 - p.heal_t / float(Items.CONSUMABLES[item["id"]]["time"])
			label = String(Items.CONSUMABLES[item["id"]]["name"])
	if label == "":
		return
	var c := s * 0.5 + Vector2(0, 70 * u)
	overlay.draw_rect(Rect2(c - Vector2(90 * u, 0), Vector2(180 * u, 8 * u)), Color(0, 0, 0, 0.6))
	overlay.draw_rect(Rect2(c - Vector2(90 * u, 0), Vector2(180 * u * clampf(t, 0, 1), 8 * u)), UIKit.ACCENT)
	_text_center(c + Vector2(0, -6 * u), label, 16)


# --- menus -------------------------------------------------------------------------------------

func toggle_pause() -> void:
	if results_panel != null:
		return
	if paused:
		_close_pause()
	else:
		_open_pause()


func _open_pause() -> void:
	paused = true
	touch.reset()
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.theme = UIKit.make_theme(u)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	holder.set_meta("bg", bg)
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_child(UIKit.label("ПАУЗА", int(36 * u), UIKit.ACCENT))
	v.add_child(UIKit.label("Игра продолжается — это королевская битва!", int(16 * u), Color(0.7, 0.75, 0.9)))
	v.add_child(UIKit.button("Продолжить", _close_pause, 320 * u, 64 * u))
	v.add_child(UIKit.button("Настройки", _open_settings, 320 * u, 64 * u))
	v.add_child(UIKit.button("Выйти в меню", func(): exit_to_menu.emit(), 320 * u, 64 * u))
	panel.add_child(v)
	holder.add_child(panel)
	add_child(holder)
	pause_panel = holder


func _close_pause() -> void:
	paused = false
	if pause_panel:
		(pause_panel.get_meta("bg") as Node).queue_free()
		pause_panel.queue_free()
		pause_panel = null
	if settings_panel:
		settings_panel.get_parent().queue_free()
		settings_panel = null
	ctrl.on_pause_closed()


func _open_settings() -> void:
	if pause_panel:
		pause_panel.visible = false
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.theme = UIKit.make_theme(u)
	settings_panel = SettingsPanel.new()
	settings_panel.build(u)
	settings_panel.closed.connect(func():
		holder.queue_free()
		settings_panel = null
		if pause_panel:
			pause_panel.visible = true)
	holder.add_child(settings_panel)
	add_child(holder)


func _on_finished(result: Dictionary) -> void:
	var delay := 2.0 if not result["victory"] else 1.0
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	_show_results(result)


func _show_results(result: Dictionary) -> void:
	touch.reset()
	if not Game.is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.theme = UIKit.make_theme(u)
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	if result["victory"]:
		v.add_child(UIKit.label("#1  ПОБЕДА!", int(64 * u), UIKit.ACCENT))
		v.add_child(UIKit.label("Ты последний выживший на острове.", int(22 * u)))
	else:
		v.add_child(UIKit.label("#%d  место" % int(result["place"]), int(56 * u), Color(1, 1, 1)))
		if String(result["killer"]) != "":
			v.add_child(UIKit.label("Тебя устранил: " + String(result["killer"]), int(22 * u), Color(1, 0.6, 0.5)))
	var mins := int(result["time"]) / 60
	var secs := int(result["time"]) % 60
	v.add_child(UIKit.label("Устранения: %d    Урон: %d    Время: %d:%02d" % [int(result["kills"]), int(result["damage"]), mins, secs], int(22 * u)))
	var hb := HBoxContainer.new()
	var killer: Fighter = result.get("killer_node")
	if not result["victory"] and killer != null and is_instance_valid(killer) and killer.alive:
		hb.add_child(UIKit.button("Наблюдать", func():
			ctrl.spectate = killer
			holder.queue_free()
			results_panel = null
			_spectate_bar(), 260 * u, 64 * u))
	hb.add_child(UIKit.button("В меню", func(): exit_to_menu.emit(), 260 * u, 64 * u))
	v.add_child(hb)
	panel.add_child(v)
	holder.add_child(panel)
	add_child(holder)
	results_panel = holder


func _spectate_bar() -> void:
	var b := UIKit.button("Выйти в меню", func(): exit_to_menu.emit(), 220 * u, 56 * u)
	b.theme = UIKit.make_theme(u)
	b.position = Vector2(overlay.size.x - 240 * u, overlay.size.y - 80 * u)
	add_child(b)
