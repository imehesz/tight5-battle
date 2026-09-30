class_name Fx
extends RefCounted
## Menu and HUD flair shared by every screen: the sweeping shine, ambient
## twinkling sparkles, one-shot sparkle bursts, the fade-in from black when a
## screen opens, and the generated art (logo, icons, announcer cards) with a
## lookup that returns null when a file is missing so callers can fall back to
## plain text.

const SHINE := preload("res://shared/shaders/shine.gdshader")
const SPARKLE := preload("res://shared/assets/fx/sparkle.png")
const GOLD := Color(1.0, 0.85, 0.4)
const LOGO := "res://shared/assets/ui/logo.png"
const ICON_DIR := "res://shared/assets/ui/icons/"
const CARD_DIR := "res://shared/assets/ui/cards/"
## Announcer text → card file (without .png).
const CARDS := {
	"FIGHT!": "fight", "K.O.!": "ko", "TIME!": "time", "FINAL ROUND": "final",
	"DRAW": "draw", "ROUND 1": "r1", "ROUND 2": "r2", "ROUND 3": "r3",
}


static func tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


static func icon(icon_name: String) -> Texture2D:
	return tex(ICON_DIR + icon_name + ".png")


static func card(text: String) -> Texture2D:
	return tex(CARD_DIR + String(CARDS[text]) + ".png") if CARDS.has(text) else null


## Put the sweeping shine on `ci`. `width` is the node's width in pixels.
static func shine(ci: CanvasItem, width: float, period := 2.6, offset := 0.0,
		strength := 0.75) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHINE
	m.set_shader_parameter("span", width)
	m.set_shader_parameter("period", period)
	m.set_shader_parameter("offset", offset)
	m.set_shader_parameter("strength", strength)
	ci.material = m
	return m


## Slow twinkling sparkles scattered over `rect` (in the parent's space).
static func twinkles(parent: Node, rect: Rect2, amount := 14, color := GOLD) -> CPUParticles2D:
	var p := _particles(amount, color)
	p.position = rect.get_center()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = rect.size / 2.0
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 4.0
	parent.add_child(p)
	return p


## A one-shot star burst at `pos` that frees itself.
static func burst(parent: Node, pos: Vector2, amount := 18, color := GOLD,
		speed := 110.0) -> void:
	var p := _particles(amount, color)
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.7
	p.spread = 180.0
	p.direction = Vector2.UP
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = 40.0
	p.damping_max = 80.0
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _particles(amount: int, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = SPARKLE
	p.amount = amount
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	# Pop in, hold, shrink away: reads as a twinkle.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(0.6, 0.8))
	c.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, color)
	p.color_ramp = g
	return p


## Fade the screen in from black. Call from the new scene's root.
static func fade_in(owner: Node, seconds := 0.25) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	owner.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(black, "color:a", 0.0, seconds)
	tw.tween_callback(layer.queue_free)


## A soft pulse on `c`'s scale around its centre, forever.
static func pulse(c: Control, amount := 0.06, seconds := 0.9) -> void:
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), seconds / 2.0) \
			.set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, seconds / 2.0).set_trans(Tween.TRANS_SINE)
