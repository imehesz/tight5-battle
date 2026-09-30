extends MenuScreen
## HOME: PLAY, SETTINGS, LEADERBOARD, DEMO, and a coffee mug that shows a
## QR code for the Buy Me a Coffee page (a cabinet can't open websites).
## KICK goes back to the splash.

const COFFEE_ICON := "res://shared/assets/ui/social_coffee.png"
## https://buymeacoffee.com/tight5games, 37x37 (1px per module, 4 quiet).
const COFFEE_QR := "res://shared/assets/ui/qr_coffee.png"
const QR_SCALE := 4.0

var _menu: MenuList
var _qr: Control


func _ready() -> void:
	build_backdrop(0.5)
	if add_logo(Vector2(320, 82), 260) == null:
		add_title("TIGHT 5", 56, 20, INK)
		add_title("BATTLE", 84, 36)
	_menu = MenuList.new()
	_menu.position = Vector2(170, 162)
	_menu.size = Vector2(300, 130)
	add_child(_menu)
	_menu.set_options(["PLAY", "SETTINGS", "LEADERBOARD", "DEMO", ""],
			[Fx.icon("play"), Fx.icon("settings"), Fx.icon("leaderboard"), Fx.icon("cvc"),
			Fx.tex(COFFEE_ICON)])
	_menu.chosen.connect(_on_chosen)
	_menu.back_pressed.connect(func(): go(GameState.SCENE_SPLASH))
	add_hint()
	GameState.play_music("main")
	# Back at HOME = the sitting is over; VS CPU streaks start again.
	GameState.vs_cpu_streak = [0, 0, 0]
	GameState.demo_mode = false


func _on_chosen(i: int) -> void:
	match i:
		0:
			go(GameState.SCENE_MODE)
		1:
			go(GameState.SCENE_SETTINGS)
		2:
			go(GameState.SCENE_LEADERBOARD)
		3:
			GameState.start_demo()
			go(GameState.SCENE_FIGHT)
		4:
			_show_qr()


## The coffee QR over everything; PUNCH, KICK or START closes it.
func _show_qr() -> void:
	_menu.visible = false
	_qr = Control.new()
	_qr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_qr)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_qr.add_child(dim)
	var t := make_label("BUY US A COFFEE", 16, GOLD)
	t.position = Vector2(0, 22)
	MenuScreen.size_later(t, Vector2(640, 20))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qr.add_child(t)
	Fx.shine(t, 640, 2.2)
	var tex := Fx.tex(COFFEE_QR)
	var side := (tex.get_width() if tex else 37) * QR_SCALE
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(1.0, 0.6, 0.15, 0.5)
	sb.shadow_size = 8
	card.add_theme_stylebox_override("panel", sb)
	card.size = Vector2(side + 16, side + 16)
	card.position = Vector2(320 - card.size.x / 2.0, 52)
	_qr.add_child(card)
	if tex:
		var qr := TextureRect.new()
		qr.texture = tex
		# Hard pixel edges: phones read a crisp code far better than a blurred one.
		qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		qr.position = Vector2(8, 8)
		qr.size = Vector2(side, side)
		card.add_child(qr)
	for i in 2:
		var l := make_label(["SCAN IT WITH YOUR PHONE", "BUYMEACOFFEE.COM/TIGHT5GAMES"][i], 8,
				[INK, DIM][i])
		l.position = Vector2(0, card.position.y + card.size.y + 14 + i * 16)
		MenuScreen.size_later(l, Vector2(640, 10))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_qr.add_child(l)
	Fx.twinkles(_qr, Rect2(card.position - Vector2(16, 16), card.size + Vector2(32, 32)), 10)
	var hint := make_label("PUNCH / KICK: CLOSE", 8, DIM)
	hint.position = Vector2(0, 342)
	MenuScreen.size_later(hint, Vector2(640, 14))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qr.add_child(hint)
	_settle = 2


func _process(delta: float) -> void:
	super(delta)
	if _qr == null or not input_ready():
		return
	if any_confirm() or any_just("kick"):
		GameState.play_sfx("click")
		_qr.queue_free()
		_qr = null
		_menu.visible = true
