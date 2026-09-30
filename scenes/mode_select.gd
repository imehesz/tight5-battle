extends MenuScreen
## PLAY → pick who's fighting: two humans, a human against the CPU, or a CPU
## exhibition. CPU modes go on to the difficulty screen; 1P vs 1P goes
## straight to fighter select.

const MODES := [
	["1P VS 1P", "TWO PLAYERS, HEAD TO HEAD."],
	["1P VS CPU", "YOU ON THE LEFT, THE CPU ON THE RIGHT."],
	["CPU VS CPU", "SIT BACK AND WATCH TWO CPUS GO AT IT."],
]

var _menu: MenuList
var _desc: Label


func _ready() -> void:
	build_backdrop()
	add_title("CHOOSE A MODE", 40, 18)
	_menu = MenuList.new()
	_menu.position = Vector2(170, 110)
	_menu.size = Vector2(300, 120)
	add_child(_menu)
	var labels := []
	for m in MODES:
		labels.append(m[0])
	_menu.set_options(labels, [Fx.icon("pvp"), Fx.icon("pvc"), Fx.icon("cvc")])
	_desc = add_title("", 260, 8, INK)
	_menu.moved.connect(_show_desc)
	_menu.chosen.connect(_on_chosen)
	_menu.back_pressed.connect(func(): go(GameState.SCENE_HOME))
	_show_desc(0)
	add_hint()


func _show_desc(i: int) -> void:
	_desc.text = MODES[i][1]


func _on_chosen(i: int) -> void:
	GameState.begin_setup(i)
	if i == GameState.Mode.PVP:
		go(GameState.SCENE_FIGHTER_SELECT)
	else:
		go(GameState.SCENE_DIFFICULTY)
