class_name FightHud
extends CanvasLayer
## The versus HUD: a health bar per fighter (mirrored, full end at the
## screen edge so damage eats in from the center), name + CPU tag, round-win
## pips, bottles in hand with the refill countdown, a swing-ready light, the
## round timer and the big announcer in the middle — a generated title card
## (FIGHT!, K.O.!, ROUND 1...) that slams in with sparkles when one exists for
## the text, plain text otherwise. The bars are glossy, and damage leaves a
## pale trail that drains away a moment later.

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
const TRAIL := Color(1.0, 0.95, 0.8)
const TRAIL_DELAY := 0.35
const CARD_H := 72.0
const CARD_CENTER := Vector2(320, 140)
const ANNOUNCE_FONT := 36
const ANNOUNCE_BOX := Vector2(640, 56)

var _fills: Array[ColorRect] = []
var _trails: Array[ColorRect] = []
var _trail_tws: Array = [null, null]
var _pip_won: Array[int] = [0, 0]
var _card: TextureRect
var _flash: ColorRect
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
		var bg := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.6)
		sb.border_color = GOLD
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 3
		bg.add_theme_stylebox_override("panel", sb)
		bg.position = Vector2(x - 2, BAR_Y - 2)
		bg.size = Vector2(BAR_W + 4, BAR_H + 4)
		add_child(bg)
		var trail := ColorRect.new()
		trail.color = TRAIL
		trail.position = Vector2(x, BAR_Y)
		trail.size = Vector2(BAR_W, BAR_H)
		add_child(trail)
		_trails.append(trail)
		var fill := ColorRect.new()
		fill.color = HEALTH_HI
		fill.position = Vector2(x, BAR_Y)
		fill.size = Vector2(BAR_W, BAR_H)
		add_child(fill)
		_fills.append(fill)
		# Glossy top third and a darker bottom edge on the fill.
		var gloss := ColorRect.new()
		gloss.color = Color(1, 1, 1, 0.35)
		gloss.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		gloss.offset_top = 2
		gloss.offset_bottom = 5
		fill.add_child(gloss)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.25)
		shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		shade.offset_top = -3
		fill.add_child(shade)

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

	# The text announcer (winner lines, ROUND 4+) is built per announce by
	# Fx.title_label, since its font shrinks to fit each name.

	_card = TextureRect.new()
	_card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card.visible = false
	add_child(_card)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.size = Vector2(w, 360)
	add_child(_flash)


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
	# A freshly won pip pops with sparkles.
	if wins > _pip_won[side] and wins <= _pips[side].size():
		var pip: ColorRect = _pips[side][wins - 1]
		Fx.burst(self, pip.position + pip.size / 2.0, 14)
		pip.pivot_offset = pip.size / 2.0
		var tw := pip.create_tween()
		tw.tween_property(pip, "scale", Vector2(1.8, 1.8), 0.08)
		tw.tween_property(pip, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	_pip_won[side] = wins


func set_timer(seconds: float) -> void:
	var s := ceili(maxf(seconds, 0.0))
	var changed := _timer_label.text != str(s)
	_timer_label.text = str(s)
	_timer_label.modulate = HEALTH_LO if s <= 10 else Color.WHITE
	# The last ten seconds tick with a throb.
	if changed and s <= 10 and s > 0:
		_timer_label.pivot_offset = _timer_label.size / 2.0
		var tw := _timer_label.create_tween()
		tw.tween_property(_timer_label, "scale", Vector2(1.35, 1.35), 0.06)
		tw.tween_property(_timer_label, "scale", Vector2.ONE, 0.2)


## Big center text. `hold` <= 0 keeps it up until the next announce/clear.
func announce(text: String, color := GOLD, hold := 0.0) -> void:
	if _announce_tw and _announce_tw.is_valid():
		_announce_tw.kill()
	var card := Fx.card(text)
	if card:
		_show_card(card, text, hold)
		return
	_card.visible = false
	_free_announce()
	_announce = Fx.title_label(text, ANNOUNCE_FONT, 640.0, ANNOUNCE_BOX.y)
	_announce.position = Vector2(0, CARD_CENTER.y - _announce.size.y / 2.0)
	_announce.pivot_offset = _announce.size / 2.0
	add_child(_announce)
	# Same slam-in as the cards: big and see-through, down to size with an
	# overshoot, then a burst of sparkles.
	_announce.scale = Vector2(2.0, 2.0)
	_announce.modulate.a = 0.0
	_announce_tw = create_tween()
	_announce_tw.tween_property(_announce, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.parallel().tween_property(_announce, "modulate:a", 1.0, 0.12)
	_announce_tw.tween_callback(func(): Fx.burst(self, CARD_CENTER, 24, color, 160.0))
	if hold > 0.0:
		_announce_tw.tween_interval(hold)
		_announce_tw.tween_callback(clear_announce)


func clear_announce() -> void:
	_free_announce()
	_card.visible = false


func _free_announce() -> void:
	if is_instance_valid(_announce):
		_announce.queue_free()
	_announce = null


## Slam the title card in: big and see-through → full size with an
## overshoot, a sparkle burst, and the shine sweeping over it.
func _show_card(t: Texture2D, text: String, hold: float) -> void:
	_free_announce()
	var h := CARD_H * (1.33 if text == "FINAL ROUND" else 1.0)
	_card.texture = t
	_card.size = Vector2(h * t.get_width() / t.get_height(), h)
	_card.position = CARD_CENTER - _card.size / 2.0
	_card.pivot_offset = _card.size / 2.0
	_card.visible = true
	_card.scale = Vector2(2.4, 2.4)
	_card.modulate.a = 0.0
	Fx.shine(_card, _card.size.x, 1.2, 0.0, 0.6)
	_announce_tw = create_tween()
	_announce_tw.tween_property(_card, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.parallel().tween_property(_card, "modulate:a", 1.0, 0.12)
	_announce_tw.tween_callback(func(): Fx.burst(self, CARD_CENTER, 28, GOLD, 170.0))
	if text == "K.O.!":
		_flash.color.a = 0.7
		var ft := create_tween()
		ft.tween_property(_flash, "color:a", 0.0, 0.35)
	if hold > 0.0:
		_announce_tw.tween_interval(hold)
		_announce_tw.tween_callback(clear_announce)


func _set_health(side: int, cur: float, mx: float) -> void:
	var frac := clampf(cur / maxf(mx, 1.0), 0.0, 1.0)
	var fill := _fills[side]
	var x0 := EDGE if side == 0 else 640.0 - EDGE - BAR_W
	fill.size.x = BAR_W * frac
	# Left bar keeps its left (edge) end; right bar keeps its right end.
	fill.position.x = x0 if side == 0 else x0 + BAR_W * (1.0 - frac)
	fill.color = HEALTH_HI if frac > 0.5 else (HEALTH_MID if frac > 0.25 else HEALTH_LO)
	# The trail holds the old length for a beat, then drains to the new one;
	# a heal (a fresh round) snaps it.
	var trail := _trails[side]
	if _trail_tws[side] and (_trail_tws[side] as Tween).is_valid():
		(_trail_tws[side] as Tween).kill()
	if fill.size.x >= trail.size.x:
		trail.size.x = fill.size.x
		trail.position.x = fill.position.x
		return
	var tw := create_tween().set_parallel()
	tw.tween_property(trail, "size:x", fill.size.x, 0.3).set_delay(TRAIL_DELAY)
	tw.tween_property(trail, "position:x", fill.position.x, 0.3).set_delay(TRAIL_DELAY)
	_trail_tws[side] = tw


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
