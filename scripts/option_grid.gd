class_name OptionGrid
extends Control
## A paged grid of picture tiles with one cursor — the roster heads, outfit
## colours, decals and weapons on the fighter select screen all use it.
## Stick left/right past an edge flips the page; up/down wraps within the
## page. The owner feeds directions via move() and reads value().
##
## Items are dictionaries: {"value": int, "kind": String, ...}
##   kind "random"  → a "?" tile
##   kind "none"    → a "NONE" tile
##   kind "head"    → "path": head sprite path
##   kind "color"   → "c1", "c2": top/bottom of the swatch (equal = flat)
##   kind "decal"   → "idx": Decorators index
##   kind "weapon"  → "idx": Weapons index
## Tile art is only built for the page on screen.

var cols := 4
var rows := 6
var tile := Vector2(40, 40)
var gap := 4.0
var accent := Color.WHITE
var items: Array = []
var cursor := 0

var _tiles: Array[Panel] = []

const TILE_BG := Color(0.06, 0.05, 0.1, 0.85)
const TILE_EDGE := Color(0.3, 0.3, 0.38)


func configure(p_cols: int, p_rows: int, p_tile: Vector2, p_gap: float,
		p_accent: Color) -> void:
	cols = p_cols
	rows = p_rows
	tile = p_tile
	gap = p_gap
	accent = p_accent
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	for i in page_size():
		var t := Panel.new()
		t.position = Vector2((i % cols) * (tile.x + gap), (i / cols) * (tile.y + gap))
		t.size = tile
		t.clip_contents = true
		add_child(t)
		_tiles.append(t)
	size = grid_size()


func grid_size() -> Vector2:
	return Vector2(cols * tile.x + (cols - 1) * gap, rows * tile.y + (rows - 1) * gap)


func page_size() -> int:
	return cols * rows


func page_count() -> int:
	return maxi(ceili(items.size() / float(page_size())), 1)


func page() -> int:
	return cursor / page_size()


## Replace the items; the cursor lands on `value` if it's there, else the first.
func set_items(p_items: Array, value: int) -> void:
	items = p_items
	cursor = 0
	for i in items.size():
		if int(items[i]["value"]) == value:
			cursor = i
			break
	refresh()


func value() -> int:
	return int(items[cursor]["value"]) if cursor < items.size() else 0


func current() -> Dictionary:
	return items[cursor] if cursor < items.size() else {}


## Move the cursor; returns true if it moved.
func move(dx: int, dy: int) -> bool:
	if items.is_empty():
		return false
	var before := cursor
	var ps := page_size()
	var pg := page()
	var slot := cursor % ps
	var col := slot % cols
	var r := slot / cols
	var on_page := mini(ps, items.size() - pg * ps)
	if dx != 0:
		var last_col_here := col == cols - 1 or pg * ps + slot + 1 >= items.size()
		if dx < 0 and col == 0:
			pg = wrapi(pg - 1, 0, page_count())
			col = cols - 1
		elif dx > 0 and last_col_here:
			pg = wrapi(pg + 1, 0, page_count())
			col = 0
		else:
			col += dx
		cursor = mini(pg * ps + r * cols + col, items.size() - 1)
	elif dy != 0:
		var rows_here := ceili(on_page / float(cols))
		r = wrapi(r + dy, 0, rows_here)
		cursor = mini(pg * ps + r * cols + col, pg * ps + on_page - 1)
	if cursor != before:
		refresh()
		return true
	return false


func refresh() -> void:
	var ps := page_size()
	var base := page() * ps
	for i in _tiles.size():
		var t := _tiles[i]
		for c in t.get_children():
			c.queue_free()
		var e := base + i
		var has := e < items.size()
		var sb := StyleBoxFlat.new()
		sb.bg_color = TILE_BG if has else Color(0, 0, 0, 0.25)
		var on := has and e == cursor
		sb.border_color = accent if on else TILE_EDGE
		sb.set_border_width_all(3 if on else 1)
		t.add_theme_stylebox_override("panel", sb)
		if has:
			_fill(t, items[e])
		# The selected tile draws its border over the art.
		t.z_index = 1 if on else 0


func _fill(t: Panel, it: Dictionary) -> void:
	var inset := Rect2(Vector2(3, 3), tile - Vector2(6, 6))
	match String(it.get("kind", "")):
		"random":
			_center_label(t, "?", int(minf(tile.x, tile.y) * 0.5), MenuScreen.GOLD)
		"none":
			_center_label(t, "NONE", 8, MenuScreen.DIM)
		"head":
			_art(t, CharacterFactory.head_texture(String(it.get("path", ""))), inset)
		"decal":
			_art(t, Decorators.texture(int(it["idx"])), inset)
		"weapon":
			var tr := _art(t, Weapons.texture(int(it["idx"])), inset)
			if tr:
				# Shown the way it's worn: handle-up weapons turned over.
				tr.flip_v = Weapons.grip_up(int(it["idx"]))
		"color":
			var g := Gradient.new()
			g.set_color(0, it["c1"])
			g.set_color(1, it["c2"])
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.fill_from = Vector2(0, 0)
			gt.fill_to = Vector2(0, 1)
			gt.width = 8
			gt.height = 32
			var sw := TextureRect.new()
			sw.texture = gt
			sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sw.stretch_mode = TextureRect.STRETCH_SCALE
			sw.position = Vector2(4, 4)
			sw.size = tile - Vector2(8, 8)
			t.add_child(sw)


func _art(t: Panel, tex: Texture2D, r: Rect2) -> TextureRect:
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = r.position
	tr.size = r.size
	t.add_child(tr)
	return tr


func _center_label(t: Panel, text: String, font_size: int, color: Color) -> void:
	var l := MenuScreen.make_label(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.add_child(l)
	MenuScreen.size_later(l, tile)
