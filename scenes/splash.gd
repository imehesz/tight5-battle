extends Control
## Boot/loading screen: the TIGHT 5 BATTLE splash art (it has PRESS START
## painted on). Any player's START or PUNCH goes to HOME.

var _armed := false


func _ready() -> void:
	var tex_path := GameState.splash_path()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists(tex_path):
		var art := TextureRect.new()
		art.texture = load(tex_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(art)
	Fx.twinkles(self, Rect2(0, 0, 640, 360), 16, Color(1.0, 0.9, 0.6))
	Fx.fade_in(self, 0.4)
	GameState.play_music("main")
	# A beat before input counts, so the button that got us here doesn't also
	# go straight through.
	await get_tree().create_timer(0.4).timeout
	_armed = true


func _process(_delta: float) -> void:
	if not _armed:
		return
	for a in ["p1_start", "p2_start", "p1_punch", "p2_punch"]:
		if Input.is_action_just_pressed(a):
			_armed = false
			GameState.play_sfx("click")
			get_tree().change_scene_to_file(GameState.SCENE_HOME)
			return
