extends MenuScreen
## SETTINGS, in four tabs: SOUNDS (music + SFX volume), RADIO (the songs for
## the menus and the fights, see Radio), CONTROLS (both players' bindings, read
## live from the input map, and the BUTTON TEST) and LEADERBOARD (reset, behind
## a password and a NO/YES confirm). Joystick-driven like every
## screen: on the tab row left/right switches tabs and down or PUNCH steps into
## the tab; inside, up/down picks a row, left/right changes a volume, PUNCH
## opens, KICK goes back up to the tabs and from there to HOME. Volumes and
## songs are saved the moment they change. On the RADIO's FIGHT band the
## fight song plays, so it can be heard before it's picked.

enum Tab { SOUNDS, RADIO, CONTROLS, LEADERBOARD }

const TABS := ["SOUNDS", "RADIO", "CONTROLS", "LEADERBOARD"]
const TAB_SIZE := Vector2(128, 24)
const TAB_GAP := 8.0
## The RADIO's rows are its two bands (MENU, FIGHT), drawn by the radio itself.
const RADIO_ROWS := 2
const TAB_Y := 40.0
const BOX := Rect2(40, 74, 560, 256)
const SEGMENTS := 10
const SEG := Vector2(16, 12)
## Rows of the bindings table: [action, caption].
const ACTIONS := [
	["left", "LEFT"], ["right", "RIGHT"], ["up", "UP"], ["down", "DOWN / DUCK"],
	["punch", "PUNCH / OK"], ["kick", "KICK / BACK"], ["throw", "THROW"],
	["swing", "SWING"], ["block", "BLOCK"], ["start", "START / PAUSE"],
]
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_BACK: "BACK", JOY_BUTTON_START: "START",
	JOY_BUTTON_DPAD_LEFT: "D-PAD", JOY_BUTTON_DPAD_RIGHT: "D-PAD",
	JOY_BUTTON_DPAD_UP: "D-PAD", JOY_BUTTON_DPAD_DOWN: "D-PAD",
}

var _tab := Tab.SOUNDS
## 0 = the tab row; 1.. = the rows inside the current tab.
var _row := 0
var _tab_panels: Array[Panel] = []
var _tab_labels: Array[Label] = []
var _pages: Array[Control] = []
## Per tab, the focusable rows: [highlight panel, label].
var _items: Array = [[], [], [], []]
var _radio: Radio
var _segments: Array = [[], []]   # SOUNDS: music, sfx
var _confirm: Control
var _confirm_list: MenuList
var _test: ButtonTest
var _pin: PinPad


func _ready() -> void:
	build_backdrop(0.6)
	add_title("SETTINGS", 10, 18)
	_build_tabs()
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.07, 0.8)
	sb.border_color = Color(GOLD, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = BOX.position
	box.size = BOX.size
	add_child(box)
	_pages = [_build_sounds(), _build_radio(), _build_controls(), _build_leaderboard()]
	for p in _pages:
		add_child(p)
	_build_confirm()
	add_hint("STICK: MOVE / CHANGE    PUNCH: OK    KICK: BACK")
	_refresh()


# ---------------------------------------------------------------- build
func _build_tabs() -> void:
	var total := TABS.size() * TAB_SIZE.x + (TABS.size() - 1) * TAB_GAP
	var x0 := (640.0 - total) / 2.0
	for i in TABS.size():
		var p := Panel.new()
		p.position = Vector2(x0 + i * (TAB_SIZE.x + TAB_GAP), TAB_Y)
		p.size = TAB_SIZE
		add_child(p)
		var l := make_label(TABS[i], 10)
		MenuScreen.size_later(l, TAB_SIZE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		_tab_panels.append(p)
		_tab_labels.append(l)


func _page() -> Control:
	var c := Control.new()
	c.position = BOX.position
	c.size = BOX.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A focusable row: a highlight pill (hidden until selected) with a caption.
func _add_item(page: Control, tab: Tab, text: String, rect: Rect2,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var hl := Panel.new()
	hl.add_theme_stylebox_override("panel", MenuList.pill_style())
	hl.position = rect.position
	hl.size = rect.size
	hl.visible = false
	page.add_child(hl)
	var l := make_label(text, 12)
	l.position = rect.position + Vector2(12, 0)
	MenuScreen.size_later(l, rect.size - Vector2(24, 0))
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page.add_child(l)
	_items[tab].append([hl, l])
	return l


func _build_sounds() -> Control:
	var page := _page()
	for i in 2:
		var y := 60.0 + i * 70.0
		_add_item(page, Tab.SOUNDS, ["MUSIC", "SOUND FX"][i], Rect2(60, y, 440, 36),
				HORIZONTAL_ALIGNMENT_LEFT)
		for s in SEGMENTS:
			var seg := ColorRect.new()
			seg.size = SEG
			seg.position = Vector2(250 + s * (SEG.x + 4), y + (36 - SEG.y) / 2.0)
			page.add_child(seg)
			_segments[i].append(seg)
	var note := make_label("VOLUMES ARE SAVED RIGHT AWAY.", 8, DIM)
	note.position = Vector2(0, 220)
	MenuScreen.size_later(note, Vector2(BOX.size.x, 10))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(note)
	return page


func _build_radio() -> Control:
	var page := _page()
	_radio = Radio.new()
	_radio.position = Vector2((BOX.size.x - Radio.SIZE.x) / 2.0, 6)
	page.add_child(_radio)
	var l := make_label("UP/DOWN: MENU OR FIGHT BAND    LEFT/RIGHT: TUNE", 8, DIM)
	l.position = Vector2(0, 240)
	MenuScreen.size_later(l, Vector2(BOX.size.x, 10))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(l)
	return page


func _build_controls() -> Control:
	var page := _page()
	var cols := [[16.0, "BUTTON"], [170.0, "P1 KEYS"], [290.0, "P2 KEYS"], [410.0, "GAMEPAD"]]
	for c in cols:
		var h := make_label(c[1], 8, GOLD)
		h.position = Vector2(c[0], 12)
		MenuScreen.size_later(h, Vector2(140, 10))
		page.add_child(h)
	for r in ACTIONS.size():
		var action: String = ACTIONS[r][0]
		var y := 28.0 + r * 15.0
		var cells := [ACTIONS[r][1], _keys_text(1, action), _keys_text(2, action),
				_pad_text(action)]
		for c in cols.size():
			var l := make_label(cells[c], 8, INK if c == 0 else Color(0.8, 0.85, 1.0))
			l.position = Vector2(cols[c][0], y)
			MenuScreen.size_later(l, Vector2(140, 10))
			page.add_child(l)
	var pads := make_label("GAMEPAD 1 PLAYS P1, GAMEPAD 2 PLAYS P2.", 8, DIM)
	pads.position = Vector2(0, 184)
	MenuScreen.size_later(pads, Vector2(BOX.size.x, 10))
	pads.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(pads)
	_add_item(page, Tab.CONTROLS, "BUTTON TEST", Rect2(170, 206, 220, 32))
	return page


func _build_leaderboard() -> Control:
	var page := _page()
	for i in 2:
		var l := make_label(["WIPES EVERY LEADERBOARD RECORD:",
				"TOP FIGHTERS AND VS CPU. USE IT BEFORE AN EVENT."][i], 8, INK)
		l.position = Vector2(0, 60 + i * 16)
		MenuScreen.size_later(l, Vector2(BOX.size.x, 10))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page.add_child(l)
	_add_item(page, Tab.LEADERBOARD, "RESET LEADERBOARD", Rect2(130, 120, 300, 32))
	return page


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	for i in 2:
		var l := make_label(["RESET THE LEADERBOARD?", "THIS CAN'T BE UNDONE."][i],
				[16, 8][i], [GOLD, INK][i])
		l.position = Vector2(0, 110 + i * 28)
		MenuScreen.size_later(l, Vector2(640, 20))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_confirm.add_child(l)
	_confirm_list = MenuList.new()
	_confirm_list.position = Vector2(220, 180)
	_confirm_list.size = Vector2(200, 80)
	_confirm.add_child(_confirm_list)
	_confirm_list.chosen.connect(_on_confirm_chosen)
	_confirm_list.back_pressed.connect(_on_confirm_chosen.bind(0))


# ---------------------------------------------------------------- bindings text
func _keys_text(player: int, action: String) -> String:
	var keys: Array[String] = []
	for e in InputMap.action_get_events("p%d_%s" % [player, action]):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode else e.keycode
			keys.append(OS.get_keycode_string(code).to_upper().replace("ESCAPE", "ESC") \
					.replace("KP ", "NUM "))
	return " / ".join(keys) if keys else "-"


## Gamepad bindings are the same for both players (each on their own pad).
func _pad_text(action: String) -> String:
	var parts: Array[String] = []
	for e in InputMap.action_get_events("p1_" + action):
		var t := ""
		if e is InputEventJoypadButton:
			t = PAD_NAMES.get(e.button_index, "BTN %d" % e.button_index)
		elif e is InputEventJoypadMotion:
			t = "STICK"
		if t != "" and not parts.has(t):
			parts.append(t)
	return " / ".join(parts) if parts else "-"


# ---------------------------------------------------------------- input
func _process(delta: float) -> void:
	super(delta)
	if not input_ready() or _confirm.visible or is_instance_valid(_test) \
			or is_instance_valid(_pin):
		return
	for p in [1, 2]:
		if _row == 0:
			if just(p, "left"):
				_set_tab(wrapi(_tab - 1, 0, TABS.size()))
			elif just(p, "right"):
				_set_tab(wrapi(_tab + 1, 0, TABS.size()))
			elif just(p, "down") or confirm(p):
				_move_row(1)
			elif just(p, "kick"):
				go(GameState.SCENE_HOME)
				return
		else:
			if just(p, "up"):
				_move_row(-1)
			elif just(p, "down"):
				_move_row(1)
			elif _tab == Tab.SOUNDS and just(p, "left"):
				_nudge_volume(-1)
			elif _tab == Tab.SOUNDS and just(p, "right"):
				_nudge_volume(1)
			elif _tab == Tab.RADIO and (just(p, "left") or just(p, "right")):
				_radio.tune(1 if just(p, "right") else -1)
				GameState.play_sfx("click")
			elif confirm(p):
				_activate()
			elif just(p, "kick"):
				_row = 0
				GameState.play_sfx("click")
				_refresh()


func _set_tab(t: int) -> void:
	_tab = t as Tab
	GameState.play_sfx("click")
	_refresh()


## Up from the first row lands back on the tabs; down past the last stops.
func _move_row(step: int) -> void:
	var n: int = RADIO_ROWS if _tab == Tab.RADIO else _items[_tab].size()
	var to := clampi(_row + step, 0, n)
	if to == _row:
		return
	_row = to
	GameState.play_sfx("click")
	_refresh()


func _nudge_volume(step: int) -> void:
	var music := _row == 1
	var v := (GameState.music_volume if music else GameState.sfx_volume) + step / float(SEGMENTS)
	v = snappedf(clampf(v, 0.0, 1.0), 1.0 / SEGMENTS)
	if music:
		GameState.set_music_volume(v)
	else:
		GameState.set_sfx_volume(v)
	# The SFX bar plays the getting-hit sound at the new level so the change is audible.
	GameState.play_sfx("click" if music else "hurt")
	_refresh()


func _activate() -> void:
	GameState.play_sfx("click")
	match _tab:
		Tab.CONTROLS:
			_test = ButtonTest.new()
			add_child(_test)
			_test.tree_exited.connect(func():
				_settle = 2
				_refresh())
		Tab.LEADERBOARD:
			# Password first (data/config.json), then the NO/YES confirm.
			if GameState.reset_password() == "":
				_open_confirm()
				return
			_pin = PinPad.new()
			_pin.password = GameState.reset_password()
			add_child(_pin)
			_pin.accepted.connect(_open_confirm)
			_pin.tree_exited.connect(func(): _settle = 2)


func _open_confirm() -> void:
	_confirm.visible = true
	_confirm_list.set_options(["NO", "YES, RESET"])


func _on_confirm_chosen(i: int) -> void:
	_confirm.visible = false
	_settle = 2
	if i == 1:
		GameState.reset_leaderboard()
		GameState.play_sfx("smash")
		toast("LEADERBOARD CLEARED")


# ---------------------------------------------------------------- display
func _refresh() -> void:
	for i in TABS.size():
		var on := i == _tab
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.45, 0.12, 0.05, 0.85) if on else Color(0.05, 0.04, 0.1, 0.8)
		sb.border_color = GOLD if on else Color(0.35, 0.35, 0.45)
		sb.set_border_width_all(2 if on else 1)
		sb.set_corner_radius_all(8)
		if on and _row == 0:
			sb.shadow_color = Color(1.0, 0.55, 0.15, 0.5)
			sb.shadow_size = 6
		_tab_panels[i].add_theme_stylebox_override("panel", sb)
		_tab_labels[i].modulate = GOLD if on else DIM
		_tab_labels[i].material = null
		_pages[i].visible = on
	if _row == 0:
		Fx.shine(_tab_labels[_tab], TAB_SIZE.x, 1.8)
	for t in _items.size():
		for r in _items[t].size():
			var on: bool = t == _tab and r + 1 == _row
			(_items[t][r][0] as Panel).visible = on
			var l: Label = _items[t][r][1]
			l.modulate = GOLD if on else INK
			l.material = null
			if on:
				Fx.shine(l, l.size.x, 1.8)
	_radio.set_band(maxi(_row - 1, 0) if _tab == Tab.RADIO else 0,
			_tab == Tab.RADIO and _row > 0)
	# Tuned to the FIGHT band, the fight song plays; everywhere else the menu song.
	GameState.play_music("venue" if _tab == Tab.RADIO and _row == 2 else "main")
	var vols := [GameState.music_volume, GameState.sfx_volume]
	for i in 2:
		var lit := roundi(vols[i] * SEGMENTS)
		for s in SEGMENTS:
			(_segments[i][s] as ColorRect).color = \
					Color(1.0, 0.85 - s * 0.05, 0.3) if s < lit else Color(1, 1, 1, 0.12)
