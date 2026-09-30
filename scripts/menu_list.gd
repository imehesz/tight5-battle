class_name MenuList
extends VBoxContainer
## A vertical list of options driven by the joystick: up/down moves, PUNCH or
## START confirms, KICK backs out. Either player's controls work. Keeps
## working while the tree is paused (the pause menu is one of these).
## The selected option sits on a glossy pill that glides between rows, its
## text carries a sweeping shine, and each row can have an icon.

signal chosen(index: int)
signal back_pressed
## The cursor landed on a new option.
signal moved(index: int)

const FONT_SIZE := 14
const ON := Color(1.0, 0.85, 0.4)
const OFF := Color(0.75, 0.75, 0.8)
const ICON_SIZE := 24.0
const PILL_PAD := Vector2(14, 5)

var index := 0
var _labels: Array[Label] = []
var _rows: Array[Control] = []
var _icons: Array[TextureRect] = []
var _pill := Rect2()
var _pill_style: StyleBoxFlat
var _pill_tw: Tween
## The button that opened this list (START opens the pause menu) must not also
## confirm it, so a freshly shown list ignores its first frame.
var _skip_frame := true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 10)
	_pill_style = pill_style()
	sort_children.connect(_snap_pill)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_skip_frame = true


## The glossy highlight behind a selected option; other screens use it too.
static func pill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.12, 0.05, 0.75)
	sb.border_color = ON
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(1.0, 0.55, 0.15, 0.45)
	sb.shadow_size = 6
	return sb


## `icons` (optional) holds a Texture2D or null per option. An option with
## empty text and an icon is an icon-only row.
func set_options(options: Array, icons: Array = []) -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	_labels.clear()
	_icons.clear()
	for i in options.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var ic: Texture2D = icons[i] if i < icons.size() else null
		var tr: TextureRect = null
		if ic:
			tr = TextureRect.new()
			tr.texture = ic
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			tr.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) / 2.0
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			row.add_child(tr)
		var l := Label.new()
		l.text = String(options[i])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", FONT_SIZE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.visible = l.text != ""
		row.add_child(l)
		add_child(row)
		_rows.append(row)
		_labels.append(l)
		_icons.append(tr)
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
		_labels[i].material = null
		if _icons[i]:
			_icons[i].modulate = Color.WHITE if on else Color(0.6, 0.6, 0.65)
			_icons[i].scale = Vector2.ONE
	if _labels.is_empty():
		return
	Fx.shine(_labels[index], _labels[index].size.x + 40.0, 1.8)
	var ic := _icons[index]
	if ic:
		var tw := ic.create_tween()
		tw.tween_property(ic, "scale", Vector2(1.3, 1.3), 0.07)
		tw.tween_property(ic, "scale", Vector2.ONE, 0.12)
	_glide_pill()


## The pill's rect around the selected row's content (icon + text).
func _target_pill() -> Rect2:
	if _rows.is_empty():
		return Rect2()
	var row := _rows[index]
	var w := row.get_combined_minimum_size().x
	var r := Rect2(row.position.x + (row.size.x - w) / 2.0, row.position.y, w, row.size.y)
	return r.grow_individual(PILL_PAD.x, PILL_PAD.y, PILL_PAD.x, PILL_PAD.y)


func _glide_pill() -> void:
	if _pill_tw and _pill_tw.is_valid():
		_pill_tw.kill()
	var to := _target_pill()
	if _pill.size == Vector2.ZERO:
		_set_pill(to)
		return
	_pill_tw = create_tween()
	_pill_tw.tween_method(_set_pill, _pill, to, 0.12).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)


## Layout just (re)placed the rows: put the pill straight onto the selection.
func _snap_pill() -> void:
	if _pill_tw and _pill_tw.is_valid():
		_pill_tw.kill()
	_set_pill(_target_pill())
	if not _labels.is_empty() and _labels[index].material:
		(_labels[index].material as ShaderMaterial).set_shader_parameter(
				"span", _labels[index].size.x + 40.0)


func _set_pill(r: Rect2) -> void:
	_pill = r
	queue_redraw()


func _draw() -> void:
	if _pill.size != Vector2.ZERO:
		draw_style_box(_pill_style, _pill)
		# Glossy top half.
		var hi := Rect2(_pill.position + Vector2(6, 3), Vector2(_pill.size.x - 12, _pill.size.y * 0.35))
		draw_rect(hi, Color(1, 1, 1, 0.12))
