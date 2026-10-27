class_name MainMenu
extends Node
## Main menu: 3D lobby preview + play / mode / bots / difficulty / settings.

signal play_pressed

var ui: CanvasLayer
var stage: Node3D
var body: BodyVisual
var cam: Camera3D
var _t := 0.0
var u := 1.0
var _bots_label: Label
var _mode_buttons: Array[Button] = []


func _ready() -> void:
	_build_stage()
	_build_ui()


func _build_stage() -> void:
	stage = Node3D.new()
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.4, 0.9)
	sm.sky_horizon_color = Color(0.95, 0.7, 0.55)
	sm.ground_horizon_color = Color(0.95, 0.7, 0.55)
	sm.ground_bottom_color = Color(0.1, 0.15, 0.3)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 150, 0)
	sun.light_color = Color(1.0, 0.85, 0.7)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	stage.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.0, 2.5, 2.0)
	rim.light_color = Color(0.4, 0.7, 1.0)
	rim.light_energy = 1.2
	rim.omni_range = 6.0
	stage.add_child(rim)
	# Podium.
	var pod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.6
	cm.height = 0.4
	pod.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.15, 0.18, 0.3)
	pm.metallic = 0.6
	pm.roughness = 0.3
	pod.material_override = pm
	pod.position = Vector3(0, -0.2, 0)
	stage.add_child(pod)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.45
	tm.outer_radius = 1.55
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = UIKit.ACCENT
	rm.emission_enabled = true
	rm.emission = UIKit.ACCENT
	rm.emission_energy_multiplier = 3.0
	ring.material_override = rm
	ring.position = Vector3(0, 0.0, 0)
	stage.add_child(ring)
	# Distant floating island silhouettes.
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for i in 6:
		var st := MeshKit.begin()
		MeshKit.blob(st, Vector3.ZERO, Vector3(r.randf_range(4, 9), r.randf_range(2, 4), r.randf_range(4, 9)), Color(0.35, 0.55, 0.3), r, 0.25, 5, 10)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.finish(st)
		mi.material_override = MeshKit.material_vc(0.9)
		var a := r.randf_range(-1.2, 1.2) + PI
		mi.position = Vector3(sin(a) * 40.0, r.randf_range(-8, 6), cos(a) * 40.0)
		stage.add_child(mi)
	body = BodyVisual.new()
	stage.add_child(body)
	body.build(randi())
	body.set_weapon(Items.weapon_item("ar", 4))
	cam = Camera3D.new()
	cam.position = Vector3(0.9, 1.4, -4.2)
	cam.fov = 45.0
	stage.add_child(cam)
	cam.look_at(Vector3(0.9, 1.05, 0))
	cam.current = true


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	u = root.get_viewport_rect().size.y / 720.0
	root.theme = UIKit.make_theme(u)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.1, 0.9))
	g.set_color(1, Color(0.02, 0.03, 0.1, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.6, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grad)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(48 * u))
	root.add_child(margin)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(v)
	var title := UIKit.label("SKYDROP", int(86 * u), UIKit.ACCENT)
	title.add_theme_constant_override("outline_size", int(10 * u))
	title.add_theme_color_override("font_outline_color", Color(0.4, 0.15, 0.0))
	v.add_child(title)
	v.add_child(UIKit.label("КОРОЛЕВСКАЯ БИТВА  •  ОФФЛАЙН", int(22 * u), Color(0.8, 0.85, 1.0)))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 20 * u)
	v.add_child(sp)
	var play := UIKit.button("ИГРАТЬ", func(): play_pressed.emit(), 380 * u, 86 * u)
	play.add_theme_font_size_override("font_size", int(38 * u))
	v.add_child(play)
	v.add_child(UIKit.label("Режим", int(20 * u), UIKit.ACCENT2))
	var mh := HBoxContainer.new()
	for mode in [["build", "СТРОЙКА"], ["zero", "НУЛЕВАЯ ВЫСОТА"]]:
		var id: String = mode[0]
		var b := UIKit.button(mode[1], func():
			Game.set_value("mode", id)
			_sync_mode(), 0, 56 * u)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(186 * u, 56 * u)
		_mode_buttons.append(b)
		mh.add_child(b)
	v.add_child(mh)
	_sync_mode()
	_bots_label = UIKit.label("", int(20 * u), UIKit.ACCENT2)
	v.add_child(_bots_label)
	var bs := HSlider.new()
	bs.min_value = 5
	bs.max_value = 49
	bs.step = 1
	bs.value = int(Game.settings["bots"])
	bs.custom_minimum_size = Vector2(380 * u, 40 * u)
	bs.value_changed.connect(func(val: float):
		Game.set_value("bots", int(val))
		_update_bots_label())
	v.add_child(bs)
	_update_bots_label()
	v.add_child(UIKit.label("Сложность ботов", int(20 * u), UIKit.ACCENT2))
	var diff := OptionButton.new()
	for d in Game.DIFFICULTY_NAMES:
		diff.add_item(d)
	diff.select(int(Game.settings["difficulty"]))
	diff.custom_minimum_size = Vector2(380 * u, 52 * u)
	diff.item_selected.connect(func(i: int): Game.set_value("difficulty", i))
	v.add_child(diff)
	v.add_child(UIKit.button("НАСТРОЙКИ", _open_settings, 380 * u, 60 * u))
	if not Game.last_result.is_empty():
		var r: Dictionary = Game.last_result
		var txt := "Прошлый матч: #%d из %d, устранений: %d" % [int(r["place"]), int(r["total"]), int(r["kills"])]
		v.add_child(UIKit.label(txt, int(18 * u), Color(0.8, 0.85, 1.0)))


func _sync_mode() -> void:
	var modes := ["build", "zero"]
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(Game.settings["mode"] == modes[i])


func _update_bots_label() -> void:
	_bots_label.text = "Боты: %d   (всего игроков: %d)" % [int(Game.settings["bots"]), int(Game.settings["bots"]) + 1]


func _open_settings() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.theme = UIKit.make_theme(u)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var panel := SettingsPanel.new()
	panel.build(u)
	panel.closed.connect(func():
		bg.queue_free()
		holder.queue_free())
	holder.add_child(panel)
	ui.add_child(holder)


func _process(delta: float) -> void:
	_t += delta
	if body:
		body.rotation.y = PI + sin(_t * 0.4) * 0.6
		body.animate(delta, "ground", 0.0, sin(_t * 0.7) * 0.1, true, false)
