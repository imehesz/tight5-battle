class_name FightHud
extends CanvasLayer
## The versus HUD: a health bar per fighter (mirrored, full end at the
## screen edge so damage eats in from the center), name + CPU tag, round-win
## pips, bottles in hand with the refill countdown, a swing-ready light, the
## round timer and the big announcer text in the middle.

const BAR_Y := 10.0
const BAR_H := 12.0
const BAR_W := 250.0
const EDGE := 12.0
const HEALTH_HI := Color(0.3, 0.9, 0.35)
const HEALTH_MID := Color(0.95, 0.8, 0.25)
const HEALTH_LO := Color(0.9, 0.25, 0.2)
const GOLD := Color(1.0, 0.85, 0.4)
const DIM := Color(0.45, 0.45, 0.5)
const PIP_ON := Color(1.0, 0.85, 0.4)
const PIP_OFF := Color(0, 0, 0, 0.55)
const BOTTLE_ICON_H := 12.0

var _fills: Array[ColorRect] = []
var _names: Array[Label] = []
var _pips: Array = [[], []]
var _bottle_icons: Array = [[], []]
var _bottle_labels: Array[Label] = []
var _swing_labels: Array[Label] = []
var _timer_label: Label
var _announce: Label
var _announce_tw: Tween


func _ready() -> void:
	layer = 10
	var w := 640.0
	for side in 2:
		var left := side == 0
		var x := EDGE if left else w - EDGE - BAR_W
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.6)
		bg.position = Vector2(x - 2, BAR_Y - 2)
		bg.size = Vector2(BAR_W + 4, BAR_H + 4)
		add_child(bg)
		var fill := ColorRect.new()
		fill.color = HEALTH_HI
		fill.position = Vector2(x, BAR_Y)
		fill.size = Vector2(BAR_W, BAR_H)
		add_child(fill)
		_fills.append(fill)

		var name_lbl := _label(8)
		name_lbl.position = Vector2(x, BAR_Y + BAR_H + 5)
		MenuScreen.size_later(name_lbl, Vector2(BAR_W, 10))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left \
				else HORIZONTAL_ALIGNMENT_RIGHT
		add_child(name_lbl)
		_names.append(name_lbl)

		# Round-win pips next to the timer end of the bar.
		for i in 2:
			var pip := ColorRect.new()
			pip.size = Vector2(8, 8)
			var px := (x + BAR_W - 10 - i * 12) if left else (x + 2 + i * 12)
			pip.position = Vector2(px, BAR_Y + BAR_H + 6)
			pip.color = PIP_OFF
			add_child(pip)
			_pips[side].append(pip)

		# Bottles: three icons under the name, then the refill countdown.
		var bottle_tex: Texture2D = null
		var bp := GameState.projectile_path()
		if bp != "" and ResourceLoader.exists(bp):
			bottle_tex = load(bp)
		for i in Battler.BOTTLES_MAX:
			var icon := TextureRect.new()
			icon.texture = bottle_tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size = Vector2(10, BOTTLE_ICON_H)
			var ix := (x + i * 12) if left else (x + BAR_W - 10 - i * 12)
			icon.position = Vector2(ix, BAR_Y + BAR_H + 18)
			add_child(icon)
			_bottle_icons[side].append(icon)
		var bl := _label(8)
		bl.position = Vector2(x + 40, BAR_Y + BAR_H + 20) if left \
				else Vector2(x + BAR_W - 40 - 40, BAR_Y + BAR_H + 20)
		MenuScreen.size_later(bl, Vector2(40, 10))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left \
				else HORIZONTAL_ALIGNMENT_RIGHT
		bl.modulate = GOLD
		add_child(bl)
		_bottle_labels.append(bl)

		var sl := _label(8)
		sl.text = "SWING"
		sl.position = Vector2(x + 90, BAR_Y + BAR_H + 20) if left \
				else Vector2(x + BAR_W - 90 - 40, BAR_Y + BAR_H + 20)
		MenuScreen.size_later(sl, Vector2(40, 10))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left \
				else HORIZONTAL_ALIGNMENT_RIGHT
		add_child(sl)
		_swing_labels.append(sl)

	_timer_label = _label(16)
	_timer_label.position = Vector2(w / 2.0 - 30, BAR_Y - 3)
	MenuScreen.size_later(_timer_label, Vector2(60, 20))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_timer_label)

	_announce = _label(28)
	_announce.add_theme_constant_override("outline_size", 8)
	_announce.position = Vector2(0, 120)
	MenuScreen.size_later(_announce, Vector2(w, 40))
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.visible = false
	add_child(_announce)


## Hook one fighter up to its side of the HUD (called again every round, since
## the fighters are rebuilt fresh each round).
func bind(side: int, f: Battler, display_name: String) -> void:
	_names[side].text = display_name
	f.health_changed.connect(func(cur: float, mx: float): _set_health(side, cur, mx))
	f.bottles_changed.connect(func(n: int, cd: float): _set_bottles(side, n, cd))
	f.swing_ready_changed.connect(func(ready: bool): _set_swing(side, ready))
	_set_health(side, f.health, f.max_health)
	_set_bottles(side, f.bottles, f.bottle_cooldown)
	_set_swing(side, f.swing_ready())


func set_round_wins(side: int, wins: int) -> void:
	for i in _pips[side].size():
		(_pips[side][i] as ColorRect).color = PIP_ON if i < wins else PIP_OFF


func set_timer(seconds: float) -> void:
	var s := ceili(maxf(seconds, 0.0))
	_timer_label.text = str(s)
	_timer_label.modulate = HEALTH_LO if s <= 10 else Color.WHITE


## Big center text. `hold` <= 0 keeps it up until the next announce/clear.
func announce(text: String, color := GOLD, hold := 0.0) -> void:
	if _announce_tw and _announce_tw.is_valid():
		_announce_tw.kill()
	_announce.text = text
	_announce.modulate = color
	_announce.visible = true
	_announce.scale = Vector2(1.0, 1.0)
	_announce.pivot_offset = _announce.size / 2.0
	_announce_tw = create_tween()
	_announce_tw.tween_property(_announce, "scale", Vector2(1.15, 1.15), 0.08)
	_announce_tw.tween_property(_announce, "scale", Vector2.ONE, 0.12)
	if hold > 0.0:
		_announce_tw.tween_interval(hold)
		_announce_tw.tween_callback(clear_announce)


func clear_announce() -> void:
	_announce.visible = false


func _set_health(side: int, cur: float, mx: float) -> void:
	var frac := clampf(cur / maxf(mx, 1.0), 0.0, 1.0)
	var fill := _fills[side]
	var x0 := EDGE if side == 0 else 640.0 - EDGE - BAR_W
	fill.size.x = BAR_W * frac
	# Left bar keeps its left (edge) end; right bar keeps its right end.
	fill.position.x = x0 if side == 0 else x0 + BAR_W * (1.0 - frac)
	fill.color = HEALTH_HI if frac > 0.5 else (HEALTH_MID if frac > 0.25 else HEALTH_LO)


func _set_bottles(side: int, n: int, cooldown: float) -> void:
	for i in _bottle_icons[side].size():
		(_bottle_icons[side][i] as TextureRect).modulate = Color.WHITE if i < n \
				else Color(0.3, 0.3, 0.35, 0.6)
	_bottle_labels[side].text = "%ds" % ceili(cooldown) if cooldown > 0.0 else ""


func _set_swing(side: int, ready: bool) -> void:
	_swing_labels[side].modulate = GOLD if ready else DIM


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l
