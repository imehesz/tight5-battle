extends MenuScreen
## HOME: PLAY, SETTINGS, LEADERBOARD. KICK goes back to the splash.

var _menu: MenuList


func _ready() -> void:
	build_backdrop(0.5)
	add_title("TIGHT 5", 56, 20, INK)
	add_title("BATTLE", 84, 36)
	add_title(String(GameState.manifest.get("title", "")).to_upper(), 132, 8, DIM)
	_menu = MenuList.new()
	_menu.position = Vector2(170, 180)
	_menu.size = Vector2(300, 130)
	add_child(_menu)
	_menu.set_options(["PLAY", "SETTINGS", "LEADERBOARD"])
	_menu.chosen.connect(_on_chosen)
	_menu.back_pressed.connect(func(): go(GameState.SCENE_SPLASH))
	add_hint()
	GameState.play_music("main")


func _on_chosen(i: int) -> void:
	match i:
		0:
			go(GameState.SCENE_MODE)
		_:
			toast("COMING IN THE NEXT BUILD")
