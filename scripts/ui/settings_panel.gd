class_name SettingsPanel
extends PanelContainer
## Graphics presets + individual options + controls. Used from the main menu and pause menu.

signal closed

var scale_f := 1.0
var _rows := {}
var _preset_buttons: Array[Button] = []
var _building := false


func build(s: float) -> void:
	scale_f = s
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(760 * s, 520 * s)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("НАСТРОЙКИ", int(34 * s), UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIKit.button("Готово", func(): closed.emit(), 140 * s, 54 * s))
	v.add_child(head)

	v.add_child(UIKit.label("Пресет графики", int(24 * s), UIKit.ACCENT2))
	var ph := HBoxContainer.new()
	for i in Game.PRESET_NAMES.size():
		var idx := i
		var b := UIKit.button(Game.PRESET_NAMES[i], func(): _apply_preset(idx), 120 * s, 60 * s)
		b.toggle_mode = true
		_preset_buttons.append(b)
		ph.add_child(b)
	v.add_child(ph)
	v.add_child(UIKit.label("RT — программная трассировка глобального освещения (SDFGI) + отражения SSR/SSIL. Самый тяжёлый режим.", int(16 * s), Color(0.7, 0.75, 0.9)))

	var g := GridContainer.new()
	g.columns = 2
	v.add_child(g)
	_slider(g, "render_scale", "Разрешение рендера", 0.4, 1.0, 0.05, true)
	_option(g, "upscaler", "Апскейлер", ["Билинейный", "MetalFX / FSR (простр.)", "MetalFX / FSR2 (времен.)"])
	_option(g, "shadows", "Тени", ["Низкие", "Средние", "Высокие", "Ультра"])
	_option(g, "grass", "Трава", ["Выкл", "Мало", "Много", "Максимум"])
	_slider(g, "view_dist", "Дальность прорисовки", 200.0, 700.0, 20.0, false)
	_check(g, "sdfgi", "Глобальное освещение (RT)")
	_check(g, "ssr", "Отражения (SSR)")
	_check(g, "ssao", "Затенение (SSAO)")
	_check(g, "ssil", "Непрямой свет (SSIL)")
	_check(g, "vol_fog", "Объёмный туман")
	_check(g, "glow", "Свечение (Bloom)")
	_option(g, "fps_limit", "Лимит FPS", ["30", "60", "120"], [30, 60, 120])
	_check(g, "show_fps", "Показывать FPS")

	v.add_child(UIKit.label("Управление", int(24 * s), UIKit.ACCENT2))
	var g2 := GridContainer.new()
	g2.columns = 2
	v.add_child(g2)
	_slider(g2, "sens", "Чувствительность", 0.2, 3.0, 0.05, false)
	_slider(g2, "ads_sens", "Чувствит. в прицеле", 0.2, 1.5, 0.05, false)
	_slider(g2, "joystick_size", "Размер кнопок", 0.7, 1.4, 0.05, false)
	_check(g2, "aim_assist", "Помощь в прицеливании")
	_check(g2, "auto_fire", "Полуавто как авто")
	_slider(g2, "master_volume", "Громкость", 0.0, 1.0, 0.05, true)
	_refresh()


func _apply_preset(i: int) -> void:
	Game.set_preset(i)
	_refresh()


func _refresh() -> void:
	_building = true
	for i in _preset_buttons.size():
		_preset_buttons[i].button_pressed = int(Game.settings["preset"]) == i
	for key in _rows.keys():
		var c: Control = _rows[key]["control"]
		var val = Game.settings[key]
		if c is HSlider:
			(c as HSlider).value = float(val)
			_update_slider_label(key)
		elif c is CheckButton:
			(c as CheckButton).button_pressed = bool(val)
		elif c is OptionButton:
			var values: Array = _rows[key]["values"]
			var idx := values.find(val)
			if idx < 0:
				idx = values.find(int(val))
			(c as OptionButton).select(maxi(idx, 0))
	_building = false


func _row_label(g: GridContainer, text: String) -> Label:
	var l := UIKit.label(text, int(20 * scale_f))
	l.custom_minimum_size = Vector2(320 * scale_f, 0)
	g.add_child(l)
	return l


func _slider(g: GridContainer, key: String, text: String, mn: float, mx: float, step: float, percent: bool) -> void:
	var l := _row_label(g, text)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.custom_minimum_size = Vector2(360 * scale_f, 44 * scale_f)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(vv: float):
		if _building:
			return
		Game.set_value(key, vv)
		_update_slider_label(key)
		_sync_presets())
	g.add_child(sl)
	_rows[key] = {"control": sl, "label": l, "text": text, "percent": percent}


func _update_slider_label(key: String) -> void:
	var r: Dictionary = _rows[key]
	var val := float(Game.settings[key])
	(r["label"] as Label).text = "%s: %s" % [r["text"], ("%d%%" % int(round(val * 100.0))) if r["percent"] else ("%.2f" % val if val < 10.0 else "%d" % int(val))]


func _check(g: GridContainer, key: String, text: String) -> void:
	_row_label(g, text)
	var cb := CheckButton.new()
	cb.custom_minimum_size = Vector2(0, 44 * scale_f)
	cb.toggled.connect(func(on: bool):
		if _building:
			return
		Game.set_value(key, on)
		_sync_presets())
	g.add_child(cb)
	_rows[key] = {"control": cb}


func _option(g: GridContainer, key: String, text: String, items: Array, values := []) -> void:
	_row_label(g, text)
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(it)
	ob.custom_minimum_size = Vector2(0, 48 * scale_f)
	var vals := values if not values.is_empty() else range(items.size())
	ob.item_selected.connect(func(i: int):
		if _building:
			return
		Game.set_value(key, vals[i])
		_sync_presets())
	g.add_child(ob)
	_rows[key] = {"control": ob, "values": vals}


func _sync_presets() -> void:
	for i in _preset_buttons.size():
		_preset_buttons[i].set_pressed_no_signal(int(Game.settings["preset"]) == i)
