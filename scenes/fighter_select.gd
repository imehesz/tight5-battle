extends MenuScreen
## FIGHTER + LOADOUT select: a FighterPanel per side. In 1P vs 1P both panels
## run at once, P1 on the left and P2 on the right. In the CPU modes the sides
## are filled one after the other — left, then right — by whoever's at the
## controls (P1's or P2's buttons both work). Once both sides are READY the
## picks go into GameState.match_setup and venue select opens.

const READY_DELAY := 0.5

var _panels: Array[FighterPanel] = []
var _sequential := false
var _active := 0
var _ready_t := -1.0


func _ready() -> void:
	# Run on its own (F6 in the editor): set up a 1P vs 1P pick.
	if GameState.match_setup.is_empty():
		GameState.begin_setup(GameState.Mode.PVP)
	build_backdrop()
	add_title("CHOOSE YOUR FIGHTERS", 8, 14)
	_sequential = GameState.setup_mode() != GameState.Mode.PVP
	for side in 2:
		var panel := FighterPanel.new()
		panel.position = Vector2(8.0 if side == 0 else 324.0, 30.0)
		add_child(panel)
		var cpu := GameState.is_cpu(side)
		var player := side + 1
		var header := "P%d" % player
		var start_char := int(GameState.last_character.get(player, GameState.RANDOM))
		var loadout := GameState.remembered_loadout(player)
		if cpu:
			var lvl: int = GameState.match_setup["sides"][side]["difficulty"]
			header = "CPU  %s" % GameState.DIFFICULTY_NAMES[lvl]
			start_char = GameState.RANDOM
			loadout = {"outfit": GameState.RANDOM, "decor": GameState.RANDOM,
					"weapon": GameState.RANDOM}
		panel.setup(side, P_COLORS[player], header, start_char, loadout)
		var s: Dictionary = GameState.match_setup["sides"][side]
		if bool(s.get("locked", false)):
			panel.restore(s)
		panel.locked.connect(_on_locked.bind(side))
		panel.unlocked.connect(_on_unlocked.bind(side))
		panel.back_out.connect(_on_back_out.bind(side))
		_panels.append(panel)
	var vs := make_label("VS", 16, GOLD)
	vs.position = Vector2(300, 140)
	MenuScreen.size_later(vs, Vector2(40, 20))
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(vs)
	Fx.shine(vs, 40, 2.0)
	Fx.pulse(vs, 0.15, 1.0)
	if _sequential:
		_active = 0 if not _panels[0].is_ready() else 1
	_refresh_focus()
	add_hint("STICK: MOVE / CHANGE    PUNCH: OK    KICK: BACK")


func _process(delta: float) -> void:
	super(delta)
	if _ready_t >= 0.0:
		_ready_t -= delta
		if _ready_t < 0.0:
			go(GameState.SCENE_VENUE_SELECT)
		return
	if not input_ready():
		return
	if _sequential:
		for p in [1, 2]:
			_panels[_active].handle_input(p)
	else:
		_panels[0].handle_input(1)
		_panels[1].handle_input(2)


func _on_locked(side: int) -> void:
	var p := _panels[side].pick()
	var s: Dictionary = GameState.match_setup["sides"][side]
	for k in p:
		s[k] = p[k]
	s["locked"] = true
	Fx.burst(self, _panels[side].position + _panels[side].ready_point(), 26,
			P_COLORS[side + 1].lightened(0.3))
	if not GameState.is_cpu(side):
		GameState.remember_character(side + 1, int(p["character"]))
		GameState.remember_loadout(side + 1, int(p["outfit"]), int(p["weapon"]), int(p["decor"]))
	if _sequential and side == 0:
		_active = 1
		_refresh_focus()
	if _panels[0].is_ready() and _panels[1].is_ready():
		_ready_t = READY_DELAY


func _on_unlocked(side: int) -> void:
	GameState.match_setup["sides"][side]["locked"] = false
	_ready_t = -1.0


func _on_back_out(side: int) -> void:
	if _sequential and side == 1:
		# Right side empty: step back into the left side's loadout.
		_active = 0
		_panels[0].unlock()
		_refresh_focus()
		return
	if side == 0:
		for s in GameState.match_setup["sides"]:
			s["locked"] = false
		go(GameState.SCENE_MODE if GameState.setup_mode() == GameState.Mode.PVP
				else GameState.SCENE_DIFFICULTY)


## In the one-driver modes the side not being picked is dimmed.
func _refresh_focus() -> void:
	for side in 2:
		var dim := _sequential and side != _active and not _panels[side].is_ready()
		_panels[side].modulate = Color(1, 1, 1, 0.45) if dim else Color.WHITE
