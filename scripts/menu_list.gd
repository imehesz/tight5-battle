class_name MenuList
extends VBoxContainer
## A vertical list of options driven by the joystick: up/down moves, PUNCH or
## START confirms, KICK backs out. Either player's controls work. Keeps
## working while the tree is paused (the pause menu is one of these).

signal chosen(index: int)
signal back_pressed
## The cursor landed on a new option.
signal moved(index: int)

const FONT_SIZE := 14
const ON := Color(1.0, 0.85, 0.4)
const OFF := Color(0.75, 0.75, 0.8)

var index := 0
var _labels: Array[Label] = []
## The button that opened this list (START opens the pause menu) must not also
## confirm it, so a freshly shown list ignores its first frame.
var _skip_frame := true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 10)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_skip_frame = true


func set_options(options: Array) -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	for o in options:
		var l := Label.new()
		l.text = String(o)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", FONT_SIZE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		add_child(l)
		_labels.append(l)
	index = 0
	_refresh()


func _process(_delta: float) -> void:
	if _labels.is_empty() or not is_visible_in_tree():
		return
	if _skip_frame:
		_skip_frame = false
		return
	for p in [1, 2]:
		var pre := "p%d_" % p
		if Input.is_action_just_pressed(pre + "up"):
			_move(-1)
		elif Input.is_action_just_pressed(pre + "down"):
			_move(1)
		elif Input.is_action_just_pressed(pre + "punch") \
				or Input.is_action_just_pressed(pre + "start"):
			GameState.play_sfx("click")
			chosen.emit(index)
			return
		elif Input.is_action_just_pressed(pre + "kick"):
			back_pressed.emit()
			return


func _move(step: int) -> void:
	index = wrapi(index + step, 0, _labels.size())
	GameState.play_sfx("click")
	_refresh()
	moved.emit(index)


func _refresh() -> void:
	for i in _labels.size():
		var on := i == index
		_labels[i].modulate = ON if on else OFF
		_labels[i].text = ("> %s <" if on else "%s") % _labels[i].text.trim_prefix("> ").trim_suffix(" <")
