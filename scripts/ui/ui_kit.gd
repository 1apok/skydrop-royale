class_name UIKit
## Theme and small widget helpers shared by menu, HUD and settings.

const ACCENT := Color(1.0, 0.78, 0.22)
const ACCENT2 := Color(0.3, 0.7, 1.0)
const PANEL := Color(0.06, 0.08, 0.16, 0.92)


static func make_theme(scale: float) -> Theme:
	var t := Theme.new()
	t.default_font_size = int(22 * scale)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.17, 0.3, 0.95)
	sb.set_corner_radius_all(int(10 * scale))
	sb.set_content_margin_all(12 * scale)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(int(max(1.0, 2 * scale)))
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.2, 0.26, 0.45, 0.98)
	sbh.border_color = ACCENT
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = ACCENT.darkened(0.2)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, sb)
		t.set_stylebox("hover", cls, sbh)
		t.set_stylebox("pressed", cls, sbp)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, Color.WHITE)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color(0.08, 0.08, 0.1))
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(int(16 * scale))
	panel.set_content_margin_all(20 * scale)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(int(max(1.0, 2 * scale)))
	t.set_stylebox("panel", "PanelContainer", panel)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.18)
	grab.set_corner_radius_all(int(6 * scale))
	grab.content_margin_top = 6 * scale
	grab.content_margin_bottom = 6 * scale
	t.set_stylebox("slider", "HSlider", grab)
	var fill := grab.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_constant("separation", "VBoxContainer", int(10 * scale))
	t.set_constant("separation", "HBoxContainer", int(10 * scale))
	t.set_constant("h_separation", "GridContainer", int(14 * scale))
	t.set_constant("v_separation", "GridContainer", int(10 * scale))
	t.set_color("font_color", "Label", Color(0.92, 0.94, 1.0))
	return t


static func label(text: String, size := 22, color := Color(0.92, 0.94, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w := 0.0, min_h := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.pressed.connect(func():
		Sfx.play("ui", -6.0)
		cb.call())
	return b
