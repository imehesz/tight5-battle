extends MenuScreen
## VENUE select: a carousel of the edition's venues, plus "?" for a random one.
## The highlighted venue's interior fills the screen behind; its exterior is
## the big card in the middle with the neighbours peeking in at the sides.
## Left/right browses, PUNCH/START starts the fight, KICK goes back to fighter
## select (both picks are kept).

const CARD := Vector2(256, 144)
const CARD_POS := Vector2(192, 70)
const SIDE_CARD := Vector2(144, 81)
const SIDE_Y := 102.0

var _entries: Array[int] = []
var _index := 0
var _bg: TextureRect
var _cards: Array[Panel] = []   # prev, current, next
var _card_art: Array[TextureRect] = []
var _card_q: Array[Label] = []
var _name: Label


func _ready() -> void:
	_entries = [GameState.RANDOM]
	for i in GameState.venues.size():
		_entries.append(i)
	_index = maxi(_entries.find(int(GameState.match_setup.get("venue", GameState.RANDOM))), 0)

	var base := ColorRect.new()
	base.color = Color(0.08, 0.07, 0.12)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	add_title("CHOOSE THE VENUE", 8, 14)
	var rects := [
		Rect2(Vector2(CARD_POS.x - SIDE_CARD.x - 16, SIDE_Y), SIDE_CARD),
		Rect2(CARD_POS, CARD),
		Rect2(Vector2(CARD_POS.x + CARD.x + 16, SIDE_Y), SIDE_CARD),
	]
	for i in 3:
		var r: Rect2 = rects[i]
		var p := Panel.new()
		p.position = r.position
		p.size = r.size
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.1)
		sb.border_color = GOLD if i == 1 else Color(0.3, 0.3, 0.38)
		sb.set_border_width_all(3 if i == 1 else 1)
		p.add_theme_stylebox_override("panel", sb)
		p.clip_contents = true
		p.modulate = Color.WHITE if i == 1 else Color(1, 1, 1, 0.5)
		add_child(p)
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.position = Vector2(3, 3)
		art.size = r.size - Vector2(6, 6)
		p.add_child(art)
		var q := make_label("?", 48 if i == 1 else 28, GOLD)
		MenuScreen.size_later(q, r.size)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(q)
		_cards.append(p)
		_card_art.append(art)
		_card_q.append(q)
	var arrows := make_label("<                              >", 16, GOLD)
	arrows.position = Vector2(0, CARD_POS.y + CARD.y / 2.0 - 10)
	MenuScreen.size_later(arrows, Vector2(640, 20))
	arrows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(arrows)
	_name = add_title("", CARD_POS.y + CARD.y + 14, 14, INK)
	add_hint("STICK: BROWSE    PUNCH: FIGHT!    KICK: BACK")
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	if not input_ready():
		return
	for p in [1, 2]:
		if just(p, "left"):
			_index = wrapi(_index - 1, 0, _entries.size())
			GameState.play_sfx("click")
			_refresh()
		elif just(p, "right"):
			_index = wrapi(_index + 1, 0, _entries.size())
			GameState.play_sfx("click")
			_refresh()
		elif confirm(p):
			GameState.play_sfx("clear")
			GameState.match_setup["venue"] = _entries[_index]
			go(GameState.SCENE_FIGHT)
			return
		elif just(p, "kick"):
			go(GameState.SCENE_FIGHTER_SELECT)
			return


func _refresh() -> void:
	for i in 3:
		var e := _entries[wrapi(_index + i - 1, 0, _entries.size())]
		_card_q[i].visible = e == GameState.RANDOM
		_card_art[i].texture = null
		if e != GameState.RANDOM:
			_card_art[i].texture = _load(String(GameState.venue_data(e).get("ExteriorSpritePath", "")))
	var cur := _entries[_index]
	if cur == GameState.RANDOM:
		_name.text = "RANDOM VENUE"
		_bg.texture = null
	else:
		var v := GameState.venue_data(cur)
		_name.text = String(v.get("VenueName", "")).to_upper()
		_bg.texture = _load(String(v.get("InteriorSpritePath", "")))


func _load(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null
