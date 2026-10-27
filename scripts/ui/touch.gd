class_name TouchControls
extends Control
## Multitouch on-screen controls: dynamic joystick, look drag, action buttons, slot bar taps.

var move_vec := Vector2.ZERO
var fire_down := false
var ads_on := false
var crouch_on := false
var enabled_input := true

var _look := Vector2.ZERO
var _joy_touch := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_touches := {}   # index -> last pos
var _button_touches := {} # index -> button id
var _pressed := {}        # one-shot presses
var buttons: Array = []   # {id, center, r, label, kind}
var player_ctrl: Node
var show_build := false
var show_interact := false
var interact_label := ""
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font


func consume_look() -> Vector2:
	var l := _look
	_look = Vector2.ZERO
	return l


func take(id: String) -> bool:
	if _pressed.get(id, false):
		_pressed.erase(id)
		return true
	return false


func _layout() -> void:
	var ins := Game.safe_insets(size)
	var s := Vector2(size.x - ins.size.x, size.y)
	var h := s.y
	var u := h / 720.0 * float(Game.settings.get("joystick_size", 1.0))
	var lx := ins.position.x
	buttons.clear()
	var build_mode: bool = player_ctrl != null and player_ctrl.build_mode
	var is_build_game: bool = Game.settings["mode"] == "build"
	buttons.append({"id": "fire", "c": Vector2(s.x - 170 * u, h - 230 * u), "r": 72 * u, "label": "ОГОНЬ" if not build_mode else "СТРОИТЬ", "kind": "hold"})
	buttons.append({"id": "fire2", "c": Vector2(lx + 95 * u, h * 0.42), "r": 44 * u, "label": "◎", "kind": "hold"})
	buttons.append({"id": "ads", "c": Vector2(s.x - 70 * u, h - 330 * u), "r": 42 * u, "label": "ПРИЦ", "kind": "toggle_ads"})
	buttons.append({"id": "jump", "c": Vector2(s.x - 70 * u, h - 120 * u), "r": 50 * u, "label": "▲", "kind": "tap"})
	buttons.append({"id": "crouch", "c": Vector2(s.x - 180 * u, h - 75 * u), "r": 40 * u, "label": "▼", "kind": "toggle_crouch"})
	buttons.append({"id": "reload", "c": Vector2(s.x - 285 * u, h - 150 * u), "r": 36 * u, "label": "⟳", "kind": "tap"})
	buttons.append({"id": "map", "c": Vector2(s.x - 280 * u, 70 * u), "r": 30 * u, "label": "КАРТА", "kind": "tap"})
	if is_build_game:
		buttons.append({"id": "build", "c": Vector2(s.x - 70 * u, h - 440 * u), "r": 40 * u, "label": "⌂" if not build_mode else "✕", "kind": "tap"})
		if build_mode:
			var names := {"wall": "СТЕНА", "floor": "ПОЛ", "ramp": "ЛЕСТН", "cone": "КРЫША"}
			var i := 0
			for t in ["wall", "floor", "ramp", "cone"]:
				buttons.append({"id": "b_" + t, "c": Vector2(s.x - 470 * u + i * 92 * u, h - 380 * u), "r": 40 * u, "label": names[t], "kind": "tap"})
				i += 1
			buttons.append({"id": "mat", "c": Vector2(s.x - 160 * u, h - 380 * u), "r": 34 * u, "label": "МАТ", "kind": "tap"})
	# Slot bar (matches HUD layout).
	var slot_w := 86.0 * u
	var total := 6
	var x0 := size.x * 0.5 - slot_w * total * 0.5
	for i in total:
		var id := "pickaxe" if i == 0 else "slot_%d" % (i - 1)
		buttons.append({"id": id, "rect": Rect2(x0 + i * slot_w, h - 100 * u, slot_w - 6 * u, 84 * u), "kind": "tap", "hidden": true})
	if show_interact:
		buttons.append({"id": "interact", "rect": Rect2(s.x * 0.5 + 60 * u, h * 0.55, 330 * u, 64 * u), "kind": "tap", "label": interact_label, "pill": true})


func _hit(pos: Vector2) -> Dictionary:
	for b in buttons:
		if b.has("rect"):
			if (b["rect"] as Rect2).has_point(pos):
				return b
		elif pos.distance_to(b["c"]) <= float(b["r"]) * 1.15:
			return b
	return {}


func _input(event: InputEvent) -> void:
	if not visible or not enabled_input:
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			_layout()
			var b := _hit(pos)
			if not b.is_empty():
				_button_touches[event.index] = b["id"]
				match b["kind"]:
					"hold":
						fire_down = true
						_look_touches[event.index] = pos # fire button also aims
					"toggle_ads":
						ads_on = not ads_on
					"toggle_crouch":
						crouch_on = not crouch_on
					_:
						_pressed[b["id"]] = true
				queue_redraw()
				return
			if pos.x < size.x * 0.4 and _joy_touch < 0:
				_joy_touch = event.index
				_joy_origin = pos
				_joy_pos = pos
			else:
				_look_touches[event.index] = pos
		else:
			if _button_touches.has(event.index):
				var id: String = _button_touches[event.index]
				_button_touches.erase(event.index)
				if id == "fire" or id == "fire2":
					fire_down = _any_fire_held()
			if event.index == _joy_touch:
				_joy_touch = -1
				move_vec = Vector2.ZERO
			_look_touches.erase(event.index)
			queue_redraw()
	elif event is InputEventScreenDrag:
		var pos2: Vector2 = event.position
		if event.index == _joy_touch:
			_joy_pos = pos2
			var r := 80.0 * size.y / 720.0
			var d := (_joy_pos - _joy_origin)
			if d.length() > r:
				_joy_origin = _joy_pos - d.normalized() * r
				d = d.normalized() * r
			move_vec = d / r
			queue_redraw()
		elif _look_touches.has(event.index):
			var last: Vector2 = _look_touches[event.index]
			_look += (pos2 - last) * (720.0 / maxf(size.y, 1.0))
			_look_touches[event.index] = pos2


func _any_fire_held() -> bool:
	for id in _button_touches.values():
		if id == "fire" or id == "fire2":
			return true
	return false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	_layout()
	var u := size.y / 720.0
	# Joystick.
	if _joy_touch >= 0:
		draw_circle(_joy_origin, 80 * u, Color(1, 1, 1, 0.12))
		draw_arc(_joy_origin, 80 * u, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * u)
		draw_circle(_joy_pos, 34 * u, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(Game.safe_insets(size).position.x + 150 * u, size.y - 190 * u)
		draw_arc(hint, 80 * u, 0, TAU, 48, Color(1, 1, 1, 0.15), 2.0 * u)
		draw_circle(hint, 30 * u, Color(1, 1, 1, 0.12))
	for b in buttons:
		if b.get("hidden", false):
			continue
		if b.get("pill", false):
			var rect: Rect2 = b["rect"]
			draw_rect(rect, Color(0.05, 0.08, 0.15, 0.7))
			draw_rect(rect, Color(1.0, 0.85, 0.3, 0.9), false, 2.0 * u)
			draw_string(font, rect.position + Vector2(14 * u, rect.size.y * 0.62), "✋ " + String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20 * u, int(22 * u), Color.WHITE)
			continue
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		var active: bool = _button_touches.values().has(b["id"]) or (b["id"] == "ads" and ads_on) or (b["id"] == "crouch" and crouch_on)
		var col := Color(1, 1, 1, 0.22) if not active else Color(1.0, 0.8, 0.3, 0.45)
		if b["id"] == "fire":
			col = Color(1.0, 0.35, 0.3, 0.32) if not active else Color(1.0, 0.45, 0.35, 0.6)
		draw_circle(c, r, col)
		draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.55), 2.0 * u)
		var fs := int((20 if String(b["label"]).length() > 2 else 30) * u)
		var tw := font.get_string_size(String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-tw * 0.5, fs * 0.35), String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


func reset() -> void:
	_button_touches.clear()
	_look_touches.clear()
	_joy_touch = -1
	move_vec = Vector2.ZERO
	fire_down = false
	_pressed.clear()
