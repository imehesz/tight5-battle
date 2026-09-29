class_name MenuScreen
extends Control
## Shared scaffolding for the menu screens: the edition's menu background
## under a dark shade, a title, a button-hint footer and per-player input
## helpers. Every screen is fully driven by the joystick and buttons — PUNCH
## (or START) confirms, KICK goes back. Screens build their UI in code.

const GOLD := Color(1.0, 0.85, 0.4)
const INK := Color(0.92, 0.92, 0.95)
const DIM := Color(0.55, 0.55, 0.62)
## Cursor colours per player, used wherever two cursors could share a screen.
const P_COLORS := {1: Color(1.0, 0.55, 0.2), 2: Color(0.35, 0.7, 1.0)}
const HINT := "STICK: MOVE    PUNCH: OK    KICK: BACK"

## Frames to ignore after the screen opens, so the press that brought us here
## can never also act on this screen.
var _settle := 2


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if _settle > 0:
		_settle -= 1


func input_ready() -> bool:
	return _settle <= 0


func build_backdrop(shade := 0.55) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var path := GameState.game_path(String(GameState.manifest.get("backgrounds", {}).get(
			"menu", "assets/backgrounds/menu_bg.png")))
	if ResourceLoader.exists(path):
		var art := TextureRect.new()
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(art)
	var dark := ColorRect.new()
	dark.color = Color(0, 0, 0, shade)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dark)


## Centered across the full width.
func add_title(text: String, y: float, font_size := 16, color := GOLD) -> Label:
	var l := make_label(text, font_size, color)
	l.position = Vector2(0, y)
	size_later(l, Vector2(640, font_size + 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func add_hint(text := HINT) -> Label:
	var l := add_title(text, 342, 8, DIM)
	return l


## Size a Control at the end of the current frame. A Label sized before its
## font_size override has taken effect (before it's in the tree, and even
## right as it enters) is measured with the theme's default 16px font, so a
## long 8px caption gets its box stretched to twice its width and keeps it.
## Deferred, the override is live and the box comes out as asked. Every label
## box in this game goes through here so that can never happen.
static func size_later(c: Control, sz: Vector2) -> void:
	c.size = sz
	c.set_deferred("size", sz)


static func make_label(text: String, font_size := 8, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.modulate = color
	return l


## Just pressed by `player` (1 or 2): "left", "right", "up", "down", "punch",
## "kick", "start"... Confirm = PUNCH or START.
func just(player: int, action: String) -> bool:
	return Input.is_action_just_pressed("p%d_%s" % [player, action])


func confirm(player: int) -> bool:
	return just(player, "punch") or just(player, "start")


func any_just(action: String) -> bool:
	return just(1, action) or just(2, action)


func any_confirm() -> bool:
	return confirm(1) or confirm(2)


func go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)


## A short message across the middle of the screen.
func toast(text: String) -> void:
	var l := make_label(text, 12, GOLD)
	l.position = Vector2(0, 300)
	size_later(l, Vector2(640, 20))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
