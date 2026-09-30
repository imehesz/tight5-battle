class_name PinPad
extends Control
## A password prompt for the joystick: an input field (digits shown as dots)
## over a 0-9 keypad laid out like a phone's, with DEL and OK on the bottom
## row. Stick moves over the keys, PUNCH presses one, START submits, KICK
## cancels. On PC the number keys, Backspace and Enter work too. A right password emits
## `accepted` and closes; a wrong one shakes the field and clears it.

signal accepted

const KEYS := [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["DEL", "0", "OK"]]
const KEY_SIZE := Vector2(48, 30)
const KEY_GAP := 8.0
const PAD_TOP := 150.0
const FIELD := Rect2(220, 104, 200, 30)
const MAX_DIGITS := 8

var password := ""
var _entry := ""
var _cursor := Vector2i(0, 0)
var _keys: Array = []   # [row][col] -> Panel
var _field: Panel
var _field_text: Label
var _message: Label
## The PUNCH that opened the pad mustn't also press a key.
var _settle := 2


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_text("ENTER PASSWORD", Vector2(0, 60), Vector2(640, 20), 16, MenuScreen.GOLD)
	_message = _text("", Vector2(0, 84), Vector2(640, 12), 8, MenuScreen.DIM)
	_field = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.7)
	sb.border_color = MenuScreen.GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_field.add_theme_stylebox_override("panel", sb)
	_field.position = FIELD.position
	_field.size = FIELD.size
	add_child(_field)
	_field_text = MenuScreen.make_label("", 16)
	MenuScreen.size_later(_field_text, FIELD.size)
	_field_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_field.add_child(_field_text)
	var width := 3 * KEY_SIZE.x + 2 * KEY_GAP
	for r in KEYS.size():
		var row := []
		for c in KEYS[r].size():
			var k := Panel.new()
			k.position = Vector2((640.0 - width) / 2.0 + c * (KEY_SIZE.x + KEY_GAP),
					PAD_TOP + r * (KEY_SIZE.y + KEY_GAP))
			k.size = KEY_SIZE
			add_child(k)
			var l := MenuScreen.make_label(KEYS[r][c], 12 if KEYS[r][c].length() == 1 else 8)
			MenuScreen.size_later(l, KEY_SIZE)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			k.add_child(l)
			row.append(k)
		_keys.append(row)
	_text("STICK: MOVE    PUNCH: PRESS    START: OK    KICK: CANCEL", Vector2(0, 342), Vector2(640, 14),
			8, MenuScreen.DIM)
	_refresh()


func _text(t: String, pos: Vector2, sz: Vector2, font_size: int, color: Color) -> Label:
	var l := MenuScreen.make_label(t, font_size, color)
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuScreen.size_later(l, sz)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if _settle > 0:
		_settle -= 1
		return
	for p in [1, 2]:
		var pre := "p%d_" % p
		if Input.is_action_just_pressed(pre + "left"):
			_move(Vector2i(-1, 0))
		elif Input.is_action_just_pressed(pre + "right"):
			_move(Vector2i(1, 0))
		elif Input.is_action_just_pressed(pre + "up"):
			_move(Vector2i(0, -1))
		elif Input.is_action_just_pressed(pre + "down"):
			_move(Vector2i(0, 1))
		elif Input.is_action_just_pressed(pre + "punch"):
			_press(KEYS[_cursor.y][_cursor.x])
			return
		elif Input.is_action_just_pressed(pre + "start"):
			_press("OK")
			return
		elif Input.is_action_just_pressed(pre + "kick"):
			_close()
			return


## PC shortcuts: the top-row digits type, Backspace deletes, and Enter (P1's
## START) submits. The numpad isn't a shortcut — it's P2's buttons.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _settle > 0:
		return
	var code := k.physical_keycode
	if code >= KEY_0 and code <= KEY_9:
		_press(str(code - KEY_0))
	elif code == KEY_BACKSPACE:
		_press("DEL")


func _move(step: Vector2i) -> void:
	_cursor.x = wrapi(_cursor.x + step.x, 0, 3)
	_cursor.y = wrapi(_cursor.y + step.y, 0, KEYS.size())
	GameState.play_sfx("click")
	_refresh()


func _press(key: String) -> void:
	GameState.play_sfx("click")
	match key:
		"DEL":
			_entry = _entry.left(-1)
		"OK":
			_check()
			return
		_:
			if _entry.length() < MAX_DIGITS:
				_entry += key
	_message.text = ""
	_refresh()


func _check() -> void:
	if _entry == password:
		accepted.emit()
		_close()
		return
	GameState.play_sfx("hurt")
	_entry = ""
	_message.text = "WRONG PASSWORD"
	_message.modulate = Color(1.0, 0.45, 0.35)
	_refresh()
	var tw := _field.create_tween()
	for i in 3:
		tw.tween_property(_field, "position:x", FIELD.position.x - 6, 0.03)
		tw.tween_property(_field, "position:x", FIELD.position.x + 6, 0.03)
	tw.tween_property(_field, "position:x", FIELD.position.x, 0.03)


func _close() -> void:
	queue_free()


func _refresh() -> void:
	_field_text.text = "*".repeat(_entry.length()) if _entry != "" else "_"
	_field_text.modulate = MenuScreen.INK if _entry != "" else MenuScreen.DIM
	for r in _keys.size():
		for c in _keys[r].size():
			var on := Vector2i(c, r) == _cursor
			var k: Panel = _keys[r][c]
			var sb: StyleBoxFlat = MenuList.pill_style() if on else StyleBoxFlat.new()
			if not on:
				sb.bg_color = Color(0.08, 0.07, 0.14, 0.9)
				sb.border_color = Color(0.4, 0.4, 0.5)
				sb.set_border_width_all(1)
				sb.set_corner_radius_all(6)
			k.add_theme_stylebox_override("panel", sb)
			(k.get_child(0) as Label).modulate = MenuScreen.GOLD if on else MenuScreen.INK
