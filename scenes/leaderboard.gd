extends MenuScreen
## LEADERBOARD, two tabs (records: scripts/leaderboard.gd):
##   TOP FIGHTERS — comedians by match wins, a page of ROWS at a time; the top
##     three get gold, silver and bronze.
##   VS CPU — a column per difficulty: best win streak, and the fastest wins.
## Left/right switches tabs, up/down turns TOP FIGHTERS' pages, KICK (or
## PUNCH/START) goes back to HOME.

enum Tab { TOP, VS_CPU }

const TABS := ["TOP FIGHTERS", "VS CPU"]
const TAB_SIZE := Vector2(180, 24)
const TAB_GAP := 10.0
const TAB_Y := 40.0
const BOX := Rect2(40, 74, 560, 256)
const ROWS := 8
const ROW_H := 28.0
const MEDALS := [Color(1.0, 0.85, 0.3), Color(0.82, 0.85, 0.92), Color(0.85, 0.55, 0.3)]
const COL_W := 176.0
const COL_GAP := 6.0
const ICONS := ["beginner", "normal", "hard"]

var _tab := Tab.TOP
var _page := 0
var _rows: Array = []
var _tab_panels: Array[Panel] = []
var _tab_labels: Array[Label] = []
var _top_page: Control
var _vs_page: Control
var _page_label: Label


func _ready() -> void:
	build_backdrop(0.6)
	var title := add_title("LEADERBOARD", 10, 18)
	for x in [168.0, 440.0]:
		add_icon("leaderboard", Rect2(x, 4, 32, 32))
	Fx.shine(title, 640, 3.0)
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
	var data := Leaderboard.load_data()
	_rows = Leaderboard.top_fighters(data)
	_top_page = _panel_page()
	_vs_page = _panel_page()
	_build_vs_cpu(data)
	_page_label = make_label("", 8, DIM)
	_page_label.position = Vector2(0, BOX.size.y - 16)
	MenuScreen.size_later(_page_label, Vector2(BOX.size.x, 10))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_page.add_child(_page_label)
	add_hint("STICK: TABS / PAGES    KICK: BACK")
	_refresh()


func _panel_page() -> Control:
	var c := Control.new()
	c.position = BOX.position
	c.size = BOX.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


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


## A label in `parent`, trimmed with "..." if the text is wider than `sz`.
func _cell(parent: Control, text: String, pos: Vector2, sz: Vector2, font_size: int,
		color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := make_label(text, font_size, color)
	l.position = pos
	MenuScreen.size_later(l, sz)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(l)
	return l


func _head(parent: Control, cid_or_idx, rect: Rect2) -> void:
	var tr := TextureRect.new()
	tr.texture = Leaderboard.head(cid_or_idx)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = rect.position
	tr.size = rect.size
	parent.add_child(tr)


# ---------------------------------------------------------------- TOP FIGHTERS
func _page_count() -> int:
	return maxi(ceili(_rows.size() / float(ROWS)), 1)


func _fill_top() -> void:
	for c in _top_page.get_children():
		if c != _page_label:
			c.queue_free()
	if _rows.is_empty():
		_cell(_top_page, "NO FIGHTS YET.", Vector2(0, 90), Vector2(BOX.size.x, 20), 14, GOLD,
				HORIZONTAL_ALIGNMENT_CENTER)
		_cell(_top_page, "EVERY MATCH WON PUTS A COMEDIAN ON THE BOARD.", Vector2(0, 120),
				Vector2(BOX.size.x, 12), 8, INK, HORIZONTAL_ALIGNMENT_CENTER)
		_page_label.text = ""
		return
	for i in ROWS:
		var rank := _page * ROWS + i
		if rank >= _rows.size():
			break
		var r: Dictionary = _rows[rank]
		var y := 8.0 + i * ROW_H
		var color: Color = MEDALS[rank] if rank < 3 else INK
		if i % 2 == 0 or rank < 3:
			var stripe := ColorRect.new()
			stripe.color = Color(color, 0.14) if rank < 3 else Color(1, 1, 1, 0.04)
			stripe.position = Vector2(8, y)
			stripe.size = Vector2(BOX.size.x - 16, ROW_H - 2)
			stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_top_page.add_child(stripe)
		_cell(_top_page, "#%d" % (rank + 1), Vector2(16, y), Vector2(44, ROW_H - 2),
				12 if rank < 3 else 10, color)
		if int(r["character"]) >= 0:
			_head(_top_page, int(r["character"]), Rect2(64, y + 1, 24, 24))
		var name_lbl := _cell(_top_page, r["name"], Vector2(96, y), Vector2(290, ROW_H - 2), 10, color)
		_cell(_top_page, "%d WIN%s" % [r["wins"], "" if r["wins"] == 1 else "S"],
				Vector2(380, y), Vector2(84, ROW_H - 2), 10, color, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(_top_page, "%d FIGHT%s" % [r["fights"], "" if r["fights"] == 1 else "S"],
				Vector2(468, y), Vector2(80, ROW_H - 2), 8, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		if rank == 0:
			Fx.shine(name_lbl, 290, 2.2)
	_page_label.text = "PAGE %d/%d" % [_page + 1, _page_count()] if _page_count() > 1 else ""


# ---------------------------------------------------------------- VS CPU
func _build_vs_cpu(data: Dictionary) -> void:
	var x0 := (BOX.size.x - 3 * COL_W - 2 * COL_GAP) / 2.0
	for lvl in 3:
		var x := x0 + lvl * (COL_W + COL_GAP)
		var col := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.04)
		sb.set_corner_radius_all(6)
		col.add_theme_stylebox_override("panel", sb)
		col.position = Vector2(x, 8)
		col.size = Vector2(COL_W, BOX.size.y - 16)
		_vs_page.add_child(col)
		var t := Fx.icon(ICONS[lvl])
		if t:
			var ic := TextureRect.new()
			ic.texture = t
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.position = Vector2((COL_W - 32) / 2.0, 6)
			ic.size = Vector2(32, 32)
			col.add_child(ic)
		_cell(col, GameState.DIFFICULTY_NAMES[lvl], Vector2(0, 40), Vector2(COL_W, 14), 10, GOLD,
				HORIZONTAL_ALIGNMENT_CENTER)

		var e: Dictionary = data["vs_cpu"][lvl]
		_cell(col, "BEST STREAK", Vector2(0, 62), Vector2(COL_W, 10), 8, DIM,
				HORIZONTAL_ALIGNMENT_CENTER)
		var streak := int(e["best_streak"]["streak"])
		_cell(col, str(streak) if streak > 0 else "-", Vector2(0, 76), Vector2(COL_W, 22), 20,
				INK, HORIZONTAL_ALIGNMENT_CENTER)
		if streak > 0:
			var cid := String(e["best_streak"]["character"])
			_head(col, cid, Rect2(8, 102, 16, 16))
			_cell(col, Leaderboard.display_name(cid), Vector2(28, 102), Vector2(COL_W - 34, 16),
					8, INK)

		_cell(col, "FASTEST WINS", Vector2(0, 132), Vector2(COL_W, 10), 8, DIM,
				HORIZONTAL_ALIGNMENT_CENTER)
		var fastest: Array = e["fastest"]
		for i in Leaderboard.FASTEST_KEEP:
			var y := 148.0 + i * 26.0
			if i >= fastest.size():
				_cell(col, "%d.  -" % (i + 1), Vector2(10, y), Vector2(COL_W - 16, 12), 8, DIM)
				continue
			var cid := String(fastest[i]["character"])
			var c: Color = MEDALS[i]
			_cell(col, "%d. %s" % [i + 1, Leaderboard.format_time(float(fastest[i]["time"]))],
					Vector2(10, y), Vector2(COL_W - 16, 12), 8, c)
			_head(col, cid, Rect2(10, y + 12, 12, 12))
			_cell(col, Leaderboard.display_name(cid), Vector2(26, y + 12), Vector2(COL_W - 32, 12),
					8, INK)


# ---------------------------------------------------------------- input
func _process(delta: float) -> void:
	super(delta)
	if not input_ready():
		return
	for p in [1, 2]:
		if just(p, "left") or just(p, "right"):
			_tab = (Tab.VS_CPU if _tab == Tab.TOP else Tab.TOP) as Tab
			GameState.play_sfx("click")
			_refresh()
		elif _tab == Tab.TOP and (just(p, "up") or just(p, "down")) and _page_count() > 1:
			_page = wrapi(_page + (1 if just(p, "down") else -1), 0, _page_count())
			GameState.play_sfx("click")
			_refresh()
		elif just(p, "kick") or confirm(p):
			GameState.play_sfx("click")
			go(GameState.SCENE_HOME)
			return


func _refresh() -> void:
	for i in TABS.size():
		var on := i == _tab
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.45, 0.12, 0.05, 0.85) if on else Color(0.05, 0.04, 0.1, 0.8)
		sb.border_color = GOLD if on else Color(0.35, 0.35, 0.45)
		sb.set_border_width_all(2 if on else 1)
		sb.set_corner_radius_all(8)
		if on:
			sb.shadow_color = Color(1.0, 0.55, 0.15, 0.5)
			sb.shadow_size = 6
		_tab_panels[i].add_theme_stylebox_override("panel", sb)
		_tab_labels[i].modulate = GOLD if on else DIM
		_tab_labels[i].material = null
	Fx.shine(_tab_labels[_tab], TAB_SIZE.x, 1.8)
	_top_page.visible = _tab == Tab.TOP
	_vs_page.visible = _tab == Tab.VS_CPU
	if _tab == Tab.TOP:
		_fill_top()
