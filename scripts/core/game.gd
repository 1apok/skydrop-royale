extends Node
## Global state: settings, graphics presets, match options.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

const PRESET_NAMES := ["Низкие", "Средние", "Высокие", "Ультра", "RT"]

# Every preset is a full set of graphics options.
const PRESETS := [
	{ # Low
		"render_scale": 0.6, "shadows": 1, "ssao": false, "ssil": false, "ssr": false,
		"sdfgi": false, "vol_fog": false, "glow": false, "grass": 0, "view_dist": 260.0,
		"upscaler": 1,
	},
	{ # Medium
		"render_scale": 0.7, "shadows": 2, "ssao": false, "ssil": false, "ssr": false,
		"sdfgi": false, "vol_fog": false, "glow": true, "grass": 1, "view_dist": 380.0,
		"upscaler": 1,
	},
	{ # High
		"render_scale": 0.75, "shadows": 2, "ssao": true, "ssil": false, "ssr": false,
		"sdfgi": false, "vol_fog": true, "glow": true, "grass": 2, "view_dist": 520.0,
		"upscaler": 2,
	},
	{ # Ultra
		"render_scale": 0.85, "shadows": 3, "ssao": true, "ssil": true, "ssr": true,
		"sdfgi": false, "vol_fog": true, "glow": true, "grass": 3, "view_dist": 700.0,
		"upscaler": 2,
	},
	{ # RT: software ray-traced GI (SDFGI) + screen-space reflections and indirect light
		"render_scale": 0.7, "shadows": 3, "ssao": true, "ssil": true, "ssr": true,
		"sdfgi": true, "vol_fog": true, "glow": true, "grass": 3, "view_dist": 700.0,
		"upscaler": 2,
	},
]

const DIFFICULTY_NAMES := ["Новичок", "Нормальный", "Профи", "Киберспортсмен"]

var settings := {
	"preset": 2,
	"render_scale": 0.75,
	"shadows": 2,
	"ssao": true,
	"ssil": false,
	"ssr": false,
	"sdfgi": false,
	"vol_fog": true,
	"glow": true,
	"grass": 2,
	"view_dist": 520.0,
	"upscaler": 2, # 0 bilinear, 1 spatial, 2 temporal
	"fps_limit": 60,
	"show_fps": true,
	"sens": 1.0,
	"ads_sens": 0.6,
	"aim_assist": true,
	"auto_fire": false,
	"master_volume": 0.8,
	"joystick_size": 1.0,
	"mode": "build", # "build" | "zero"
	"bots": 23,
	"difficulty": 1,
}

var is_mobile := false
var last_result := {}


func _ready() -> void:
	is_mobile = OS.has_feature("mobile") or OS.get_name() == "iOS" or OS.get_name() == "Android"
	if is_mobile:
		# Sensible default for phones on first launch.
		settings["preset"] = 1
		_copy_preset(1)
		settings["bots"] = 19
	_setup_input()
	load_settings()
	apply_settings()


## Left/right/top/bottom insets (in viewport units) that keep UI clear of the notch and home indicator.
func safe_insets(view_size: Vector2) -> Rect2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or not is_mobile:
		return Rect2()
	var safe := DisplayServer.get_display_safe_area()
	var k := view_size.x / float(win.x)
	var left := float(safe.position.x) * k
	var top := float(safe.position.y) * k
	var right := float(win.x - safe.end.x) * k
	var bottom := float(win.y - safe.end.y) * k
	return Rect2(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))


func _copy_preset(i: int) -> void:
	var p: Dictionary = PRESETS[clampi(i, 0, PRESETS.size() - 1)]
	for k in p.keys():
		settings[k] = p[k]


func set_preset(i: int) -> void:
	settings["preset"] = i
	_copy_preset(i)
	apply_settings()
	save_settings()


func set_value(key: String, value) -> void:
	settings[key] = value
	if key in ["render_scale", "shadows", "ssao", "ssil", "ssr", "sdfgi", "vol_fog", "glow", "grass", "view_dist", "upscaler"]:
		settings["preset"] = -1
	apply_settings()
	save_settings()


func get_value(key: String, default_value = null):
	return settings.get(key, default_value)


func apply_settings() -> void:
	Engine.max_fps = int(settings["fps_limit"])
	var vp := get_viewport()
	var scale_v: float = clampf(float(settings["render_scale"]), 0.4, 1.0)
	vp.scaling_3d_scale = scale_v
	var up := int(settings["upscaler"])
	if scale_v >= 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif OS.get_name() == "iOS" or OS.get_name() == "macOS":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if up == 2 else (Viewport.SCALING_3D_MODE_METALFX_SPATIAL if up == 1 else Viewport.SCALING_3D_MODE_BILINEAR)
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if up == 2 else (Viewport.SCALING_3D_MODE_FSR if up == 1 else Viewport.SCALING_3D_MODE_BILINEAR)
	# Temporal upscalers already anti-alias; otherwise use cheap FXAA.
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if (up == 2 and scale_v < 0.999) else Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_taa = false
	var shadow_sizes := [1024, 2048, 2048, 4096]
	RenderingServer.directional_shadow_atlas_set_size(shadow_sizes[clampi(int(settings["shadows"]), 0, 3)], true)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(settings["master_volume"]))))
	settings_changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		if cfg.has_section_key("settings", k):
			settings[k] = cfg.get_value("settings", k)


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev: InputEvent
		if k is int and k >= 1000:
			var mb := InputEventMouseButton.new()
			mb.button_index = k - 1000
			ev = mb
		else:
			var kb := InputEventKey.new()
			kb.physical_keycode = k
			ev = kb
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_key("move_forward", [KEY_W])
	_add_key("move_back", [KEY_S])
	_add_key("move_left", [KEY_A])
	_add_key("move_right", [KEY_D])
	_add_key("jump", [KEY_SPACE])
	_add_key("crouch", [KEY_CTRL, KEY_C])
	_add_key("sprint", [KEY_SHIFT])
	_add_key("fire", [1000 + MOUSE_BUTTON_LEFT])
	_add_key("aim", [1000 + MOUSE_BUTTON_RIGHT])
	_add_key("reload", [KEY_R])
	_add_key("interact", [KEY_E])
	_add_key("build_toggle", [KEY_Q])
	_add_key("build_wall", [KEY_Z])
	_add_key("build_floor", [KEY_X])
	_add_key("build_ramp", [KEY_V])
	_add_key("build_cone", [KEY_B])
	_add_key("material_cycle", [KEY_T])
	_add_key("map", [KEY_M])
	_add_key("pause", [KEY_ESCAPE])
	_add_key("pickaxe", [KEY_F])
	for i in 5:
		_add_key("slot_%d" % (i + 1), [KEY_1 + i])
