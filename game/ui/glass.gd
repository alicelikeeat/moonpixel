class_name Glass
extends PanelContainer
## "Liquid glass" style panel: blurred, slightly refracted backdrop, soft tint,
## bright rim and top sheen, rounded like iOS capsules and sheets.
## This is a shader look-alike drawn by the game, not the native iOS control
## (Godot cannot host UIKit glass views).

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 size = vec2(100.0, 40.0);
uniform float radius = 20.0;
uniform vec4 tint : source_color = vec4(0.10, 0.13, 0.20, 0.38);
uniform float blur = 2.6;
float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float r = min(radius, min(size.x, size.y) * 0.5);
	float d = sd_box(p, size * 0.5, r);
	float a = 1.0 - smoothstep(-1.0, 0.4, d);
	float edge = smoothstep(-12.0, 0.0, d);
	vec2 off = normalize(p + vec2(0.0001)) * edge * 0.010;
	vec3 bg = textureLod(screen_tex, SCREEN_UV - off, blur).rgb;
	bg = mix(bg, tint.rgb, tint.a);
	bg += vec3(0.09) * (1.0 - UV.y);
	float rim = smoothstep(-2.0, -0.5, d);
	bg = mix(bg, vec3(1.0), rim * (0.18 + 0.30 * (1.0 - UV.y)));
	COLOR = vec4(bg, a);
}
"""

static var _shader: Shader = null
static var _theme: Theme = null

var radius := 20.0


static func make(p_radius: float = 20.0, margin: int = 10) -> Glass:
	var g := Glass.new()
	g.radius = p_radius
	var sb := StyleBoxEmpty.new()
	sb.set_content_margin_all(margin)
	g.add_theme_stylebox_override("panel", sb)
	g.theme = ui_theme()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("radius", p_radius)
	g.material = m
	g.resized.connect(g._sync)
	return g


func _sync() -> void:
	(material as ShaderMaterial).set_shader_parameter("size", size)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


static func _pill(alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, alpha)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Shared theme: white text, pill buttons, 44pt-class touch targets.
static func ui_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = Loc.ui_font()
	t.default_font_size = 13
	t.set_stylebox("normal", "Button", _pill(0.10))
	t.set_stylebox("hover", "Button", _pill(0.18))
	t.set_stylebox("pressed", "Button", _pill(0.34))
	t.set_stylebox("disabled", "Button", _pill(0.04))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(1, 1, 1, 0.95))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", Color(1, 1, 1, 0.95))
	for cls in ["OptionButton", "LineEdit"]:
		t.set_stylebox("normal", cls, _pill(0.12))
		t.set_stylebox("focus", cls, _pill(0.2))
		t.set_color("font_color", cls, Color.WHITE)
	t.set_stylebox("hover", "OptionButton", _pill(0.18))
	t.set_stylebox("pressed", "OptionButton", _pill(0.3))
	_theme = t
	return t


static func button(text: String, on_press: Callable, min_w: float = 44.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 36)
	b.pressed.connect(func():
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(12)
		on_press.call())
	return b
