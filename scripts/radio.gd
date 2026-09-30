class_name Radio
extends Control
## SETTINGS → RADIO: the old-school radio (generated art, shared/assets/ui/
## radio/) that picks the songs. Two bands: MENU (the menus' song) and FIGHT
## (the venue song). Either band can tune to any song on the dial. The glass
## shows the band, a dial with a needle and the station; the left knob turns
## with the band, the right knob with the tuning. The screen drives it: which
## band is focused, and tune(+1/-1).
##
## All positions are measured off radio.png (920x464, shown at half size) —
## see src/tmp/tight5battle-radio/process.py.

const ART := "res://shared/assets/ui/radio/radio.png"
const SIZE := Vector2(460, 232)
const GLASS := Rect2(203, 33, 220, 92)
const KNOBS := [Vector2(245.5, 172), Vector2(383.5, 172)]
const KNOB_SIZE := 44.0
const AMBER := Color(1.0, 0.72, 0.28)
const AMBER_DIM := Color(0.6, 0.42, 0.18)
const NEEDLE := Color(1.0, 0.25, 0.15)
const DIAL_X := Vector2(14, 206)
const SLOTS := ["main", "venue"]

## 0 = MENU band, 1 = FIGHT band.
var band := 0
var focused := false
var _glow: ColorRect
var _band_labels: Array[Label] = []
var _needle: ColorRect
var _station: Label
var _kind: Label
var _arrows: Array[Label] = []
var _knobs: Array[TextureRect] = []
var _tw: Tween


func _init() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var art := TextureRect.new()
	art.texture = Fx.tex(ART)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = SIZE
	add_child(art)
	for i in 2:
		var k := TextureRect.new()
		k.texture = Fx.tex("res://shared/assets/ui/radio/knob_%s.png" % ["left", "right"][i])
		k.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		k.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		k.size = Vector2(KNOB_SIZE, KNOB_SIZE)
		k.position = KNOBS[i] - k.size / 2.0
		k.pivot_offset = k.size / 2.0
		add_child(k)
		_knobs.append(k)

	# The lamp behind the glass.
	_glow = ColorRect.new()
	_glow.color = Color(AMBER, 0.06)
	_glow.position = GLASS.position + Vector2(4, 4)
	_glow.size = GLASS.size - Vector2(8, 8)
	add_child(_glow)
	for i in 2:
		var l := _label(["MENU", "FIGHT"][i], 8, Vector2(GLASS.position.x + 20 + i * 110,
				GLASS.position.y + 6), Vector2(70, 10))
		_band_labels.append(l)
	# Dial: a tick per song, a taller one where each station starts.
	var n := maxi(GameState.music_tracks.size(), 1)
	var base := ColorRect.new()
	base.color = AMBER_DIM
	base.position = GLASS.position + Vector2(DIAL_X.x, 40)
	base.size = Vector2(DIAL_X.y - DIAL_X.x, 1)
	add_child(base)
	for i in n:
		var t := ColorRect.new()
		var major := i % 2 == 0
		t.color = AMBER if major else AMBER_DIM
		t.size = Vector2(1, 8 if major else 4)
		t.position = GLASS.position + Vector2(_dial_x(i), 40 - t.size.y)
		add_child(t)
	_needle = ColorRect.new()
	_needle.color = NEEDLE
	_needle.size = Vector2(2, 22)
	_needle.position = GLASS.position + Vector2(_dial_x(0) - 1, 22)
	add_child(_needle)
	_station = _label("", 12, GLASS.position + Vector2(18, 50), Vector2(GLASS.size.x - 36, 16))
	_kind = _label("", 8, GLASS.position + Vector2(0, 70), Vector2(GLASS.size.x, 10))
	for i in 2:
		var a := _label(["<", ">"][i], 12, GLASS.position + Vector2(4 + i * (GLASS.size.x - 20), 50),
				Vector2(16, 16))
		_arrows.append(a)
		var tw := a.create_tween().set_loops()
		tw.tween_property(a, "modulate:a", 0.2, 0.4)
		tw.tween_property(a, "modulate:a", 1.0, 0.4)
	refresh(false)


func _label(text: String, font_size: int, pos: Vector2, sz: Vector2) -> Label:
	var l := MenuScreen.make_label(text, font_size, AMBER)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.06, 0.0))
	l.add_theme_constant_override("outline_size", 3)
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	MenuScreen.size_later(l, sz)
	add_child(l)
	return l


func _dial_x(i: int) -> float:
	var n := maxi(GameState.music_tracks.size() - 1, 1)
	return DIAL_X.x + (DIAL_X.y - DIAL_X.x) * i / float(n)


func _index() -> int:
	var id := GameState.music_track_id(SLOTS[band])
	for i in GameState.music_tracks.size():
		if GameState.music_tracks[i]["id"] == id:
			return i
	return 0


func set_band(b: int, is_focused: bool) -> void:
	var changed := b != band
	band = b
	focused = is_focused
	refresh(changed)


## Move this band's pick one song along the dial (wrapping) and play it.
func tune(step: int) -> void:
	var n := GameState.music_tracks.size()
	if n == 0:
		return
	var i := wrapi(_index() + step, 0, n)
	GameState.set_music_choice(SLOTS[band], String(GameState.music_tracks[i]["id"]))
	refresh(true)
	_station.modulate.a = 0.0
	_station.create_tween().tween_property(_station, "modulate:a", 1.0, 0.2)


func refresh(animate := true) -> void:
	if _station == null:
		return
	for i in 2:
		_band_labels[i].modulate = AMBER if (i == band and focused) else \
				(Color(AMBER, 0.8) if i == band else Color(AMBER_DIM, 0.5))
	for a in _arrows:
		a.visible = focused
	_glow.color = Color(AMBER, 0.12 if focused else 0.05)
	var i := _index()
	var t: Dictionary = GameState.music_tracks[i] if i < GameState.music_tracks.size() else {}
	_station.text = String(t.get("station", "NO SIGNAL"))
	_kind.text = "%s THEME" % String(t.get("kind", "")) if not t.is_empty() else ""
	_kind.modulate = Color(AMBER_DIM, 1.0)
	var needle_x := GLASS.position.x + _dial_x(i) - 1
	var band_rot := deg_to_rad(-45.0 if band == 0 else 45.0)
	var tune_rot := deg_to_rad(i * 24.0)
	if _tw and _tw.is_valid():
		_tw.kill()
	if not animate:
		_needle.position.x = needle_x
		_knobs[0].rotation = band_rot
		_knobs[1].rotation = tune_rot
		return
	_tw = create_tween().set_parallel()
	_tw.tween_property(_needle, "position:x", needle_x, 0.25).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	_tw.tween_property(_knobs[0], "rotation", band_rot, 0.2)
	_tw.tween_property(_knobs[1], "rotation", tune_rot, 0.25)
