class_name ButtonTest
extends Control
## SETTINGS → CONTROLS → BUTTON TEST: both players' panels drawn like the
## cabinet (8-way stick, buttons in the 2-3-3 layout, START) with a lamp per
## input that lights while it's held. The line along the bottom names the last
## RAW input — keyboard key, or gamepad number + button index / stick axis —
## and which action it's mapped to, so wiring an encoder shows exactly which
## index each physical button reports, the three spare buttons included.
## Every button is being tested, so leaving is HOLD START.

const HOLD_EXIT_S := 1.5
const PANEL := Vector2(290, 212)
const LAMP := 30.0
const STICK_CENTER := Vector2(62, 80)
const STICK_REACH := 34.0
const BTN_ORIGIN := Vector2(128, 26)
const BTN_STEP := Vector2(52, 50)
## The 2-3-3 panel; "" is a spare button with no action.
const BUTTON_ROWS := [["select", "back"], ["punch", "kick", "swing"], ["throw", "block", ""]]
const DIRS := {"up": Vector2(0, -1), "down": Vector2(0, 1),
		"left": Vector2(-1, 0), "right": Vector2(1, 0)}
const ARROWS := {"up": "^", "down": "v", "left": "<", "right": ">"}
const ACTIONS := ["left", "right", "up", "down", "punch", "kick", "throw", "swing",
		"block", "select", "back", "start"]

## [player][action] -> lamp Panel.
var _lamps := {1: {}, 2: {}}
var _last: Label
var _exit_fill: ColorRect
var _hold := 0.0
## Stick axes already reported past the deadzone, so a held stick is one line.
var _axis_on := {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_text("BUTTON TEST", Vector2(0, 10), Vector2(640, 20), 16, MenuScreen.GOLD)
	for player in [1, 2]:
		_build_panel(player, Vector2(20 if player == 1 else 330, 42))
	_last = _text("PRESS ANY BUTTON", Vector2(0, 268), Vector2(640, 12), 8, MenuScreen.INK)
	_text("HOLD START TO EXIT", Vector2(0, 300), Vector2(640, 12), 8, MenuScreen.DIM)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.position = Vector2(245, 316)
	track.size = Vector2(150, 4)
	add_child(track)
	_exit_fill = ColorRect.new()
	_exit_fill.color = MenuScreen.GOLD
	_exit_fill.position = track.position
	_exit_fill.size = Vector2(0, 4)
	add_child(_exit_fill)


func _build_panel(player: int, at: Vector2) -> void:
	var accent: Color = MenuScreen.P_COLORS[player]
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.1, 0.9)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", sb)
	box.position = at
	box.size = PANEL
	add_child(box)
	_text("P%d" % player, at + Vector2(10, 8), Vector2(40, 12), 10, accent)
	# Stick: a lamp per direction around the gate (diagonals light two).
	var gate := _circle(LAMP + STICK_REACH * 2.0 - 8.0, Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.2))
	gate.position = at + STICK_CENTER - gate.size / 2.0
	add_child(gate)
	for d in DIRS:
		var lamp := _lamp(at + STICK_CENTER + DIRS[d] * STICK_REACH, ARROWS[d], 10)
		_lamps[player][d] = lamp
	_text("STICK", at + STICK_CENTER + Vector2(-30, STICK_REACH + 22), Vector2(60, 10), 8,
			MenuScreen.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	# Buttons, 2-3-3, the top pair pushed right like the real panel.
	for r in BUTTON_ROWS.size():
		for c in BUTTON_ROWS[r].size():
			var action: String = BUTTON_ROWS[r][c]
			var col: int = c + (1 if BUTTON_ROWS[r].size() == 2 else 0)
			var center := at + BTN_ORIGIN + Vector2(col * BTN_STEP.x, r * BTN_STEP.y) \
					+ Vector2(LAMP, LAMP) / 2.0
			var lamp := _lamp(center, "", 8)
			if action != "":
				_lamps[player][action] = lamp
			_text(action.to_upper() if action != "" else "-", center + Vector2(-26, LAMP / 2.0 + 3),
					Vector2(52, 10), 8, MenuScreen.INK if action != "" else MenuScreen.DIM,
					HORIZONTAL_ALIGNMENT_CENTER)
	var start := _lamp(at + Vector2(34, 184), "", 8, Color(0.9, 0.9, 0.95, 0.25))
	_lamps[player]["start"] = start
	_text("START", at + Vector2(54, 179), Vector2(60, 10), 8, MenuScreen.INK)


func _circle(d: float, fill: Color, border: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(d / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(d, d)
	return p


func _lamp(center: Vector2, caption: String, font_size: int,
		off := Color(1, 1, 1, 0.1)) -> Panel:
	var p := _circle(LAMP, off, Color(1, 1, 1, 0.35))
	p.position = center - p.size / 2.0
	add_child(p)
	if caption != "":
		var l := MenuScreen.make_label(caption, font_size)
		MenuScreen.size_later(l, p.size)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	p.set_meta("off", off)
	return p


func _text(t: String, pos: Vector2, sz: Vector2, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := MenuScreen.make_label(t, font_size, color)
	l.position = pos
	l.horizontal_alignment = align
	MenuScreen.size_later(l, sz)
	add_child(l)
	return l


func _process(delta: float) -> void:
	for player in [1, 2]:
		var accent: Color = MenuScreen.P_COLORS[player]
		for action in _lamps[player]:
			var on := Input.is_action_pressed("p%d_%s" % [player, action])
			var lamp: Panel = _lamps[player][action]
			var sb := lamp.get_theme_stylebox("panel") as StyleBoxFlat
			sb.bg_color = accent if on else lamp.get_meta("off")
			sb.shadow_color = Color(accent, 0.6)
			sb.shadow_size = 6 if on else 0
	var holding := Input.is_action_pressed("p1_start") or Input.is_action_pressed("p2_start")
	_hold = _hold + delta if holding else 0.0
	_exit_fill.size.x = 150.0 * clampf(_hold / HOLD_EXIT_S, 0.0, 1.0)
	if _hold >= HOLD_EXIT_S:
		GameState.play_sfx("click")
		queue_free()


func _input(event: InputEvent) -> void:
	var raw := ""
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		raw = "KEYBOARD  %s" % OS.get_keycode_string(code).to_upper()
	elif event is InputEventJoypadButton and event.pressed:
		raw = "GAMEPAD %d  BUTTON %d" % [event.device + 1, event.button_index]
	elif event is InputEventJoypadMotion:
		var key := "%d:%d" % [event.device, event.axis]
		var past: bool = absf(event.axis_value) >= GameState.STICK_DEADZONE
		if past and not _axis_on.get(key, false):
			raw = "GAMEPAD %d  AXIS %d %s" % [event.device + 1, event.axis,
					"+" if event.axis_value > 0.0 else "-"]
		_axis_on[key] = past
	if raw == "":
		return
	var mapped: Array[String] = []
	for player in [1, 2]:
		for action in ACTIONS:
			var a := "p%d_%s" % [player, action]
			if InputMap.event_is_action(event, a):
				mapped.append("P%d %s" % [player, action.to_upper()])
	_last.text = "%s  ->  %s" % [raw, ", ".join(mapped) if mapped else "NOT MAPPED"]
	_last.modulate = MenuScreen.GOLD if mapped else Color(1.0, 0.5, 0.4)
