class_name FighterPanel
extends Control
## One side of the fighter select screen. Four picture grids, one after the
## other in the same spot, then READY:
##   ROSTER  4x6 heads, paged, "?" first
##   COLOR   5x5 outfit swatches, "?" first
##   DECAL   5x7 chest decals, "?" and NONE first
##   WEAPON  4x4 weapons (taller tiles), "?" first
## Beside the grids, a live preview of the comedian wearing whatever is
## highlighted right now. PUNCH/START picks and moves on; KICK steps back.
##
## The owning screen feeds one player's input at a time via handle_input();
## the panel never reads the Input singleton itself, so the same panel works
## whichever player drives it.

signal locked
signal unlocked
## KICK on the roster: the screen decides where that goes.
signal back_out

enum Stage { ROSTER, COLOR, DECAL, WEAPON, READY }

const PANEL_W := 308.0
const AREA_W := 172.0
const AREA_Y := 26.0
const AREA_H := 260.0
const PREVIEW_W := 126.0
## Preview fighter: feet at this y, this much bigger than BODY_SCALE.
const PREVIEW_FEET_Y := 206.0
const PREVIEW_SIZE := 1.6
## The preview is rebuilt once the cursor has rested this long, so scrolling
## through a grid doesn't recolour a body sheet for every tile passed.
const PREVIEW_DEBOUNCE := 0.08
const STEP_NAMES := {Stage.COLOR: "COLOR", Stage.DECAL: "DECAL", Stage.WEAPON: "WEAPON"}

var side := 0                 # 0 = left, 1 = right
var accent := Color.WHITE
var stage := Stage.ROSTER
## What's been picked so far (RANDOM = "?").
var character := GameState.RANDOM
var outfit := GameState.RANDOM
var decor := GameState.RANDOM
var weapon := GameState.RANDOM
var _default_loadout := {}

var _header: Label
var _grids := {}              # Stage -> OptionGrid
var _step_label: Label
var _info_label: Label        # page number, or the highlighted option's name
var _summary: Label
var _ready_label: Label
var _preview_holder: Node2D
var _preview: Battler
var _preview_q: Label
var _name_label: Label
var _preview_wait := 0.0
var _preview_key := ""


## `header`: "P1", "P2", "CPU HARD"... `loadout`: indices from
## GameState.remembered_loadout(), or all RANDOM for a CPU.
## Centre of the READY! caption, in the panel's space (the lock-in burst).
func ready_point() -> Vector2:
	return _ready_label.position + _ready_label.size / 2.0


func setup(p_side: int, p_accent: Color, header: String, start_char: int,
		loadout: Dictionary) -> void:
	side = p_side
	accent = p_accent
	_default_loadout = loadout
	_build(header)
	_grids[Stage.ROSTER].set_items(_roster_items(), start_char)
	_grids[Stage.COLOR].set_items(_color_items(), int(loadout.get("outfit", GameState.RANDOM)))
	_grids[Stage.DECAL].set_items(_decal_items(), int(loadout.get("decor", GameState.RANDOM)))
	_grids[Stage.WEAPON].set_items(_weapon_items(), int(loadout.get("weapon", GameState.RANDOM)))
	_refresh()


func set_header(text: String) -> void:
	_header.text = text


func is_ready() -> bool:
	return stage == Stage.READY


## The finished pick, for the screen to write into GameState.match_setup.
func pick() -> Dictionary:
	return {"character": character, "outfit": outfit, "decor": decor, "weapon": weapon}


## Jump straight to READY with an existing pick (coming back from venue select).
func restore(p: Dictionary) -> void:
	character = int(p.get("character", GameState.RANDOM))
	outfit = int(p.get("outfit", GameState.RANDOM))
	decor = int(p.get("decor", GameState.RANDOM))
	weapon = int(p.get("weapon", GameState.RANDOM))
	_grids[Stage.ROSTER].set_items(_grids[Stage.ROSTER].items, character)
	_grids[Stage.COLOR].set_items(_grids[Stage.COLOR].items, outfit)
	_grids[Stage.DECAL].set_items(_grids[Stage.DECAL].items, decor)
	_grids[Stage.WEAPON].set_items(_grids[Stage.WEAPON].items, weapon)
	stage = Stage.READY
	_refresh()


## Step back from READY to the weapon grid (the screen does this when the next
## panel backs out in a one-driver mode).
func unlock() -> void:
	if stage != Stage.READY:
		return
	stage = Stage.WEAPON
	_click()
	unlocked.emit()


# ---------------------------------------------------------------- items
func _roster_items() -> Array:
	var out := [{"value": GameState.RANDOM, "kind": "random"}]
	for i in GameState.playable:
		out.append({"value": i, "kind": "head",
				"path": String(GameState.character_data(i).get("HeadSpritePath", ""))})
	return out


func _color_items() -> Array:
	var out := [{"value": GameState.RANDOM, "kind": "random"}]
	for i in CharacterFactory.OUTFITS.size():
		out.append({"value": i, "kind": "color",
				"c1": CharacterFactory.outfit_color(i), "c2": CharacterFactory.outfit_color2(i)})
	return out


func _decal_items() -> Array:
	var out := [{"value": GameState.RANDOM, "kind": "random"},
			{"value": Decorators.NONE, "kind": "none"}]
	for i in Decorators.available():
		out.append({"value": i, "kind": "decal", "idx": i})
	return out


func _weapon_items() -> Array:
	var out := [{"value": GameState.RANDOM, "kind": "random"}]
	for i in Weapons.available():
		out.append({"value": i, "kind": "weapon", "idx": i})
	return out


# ---------------------------------------------------------------- input
func handle_input(player: int) -> void:
	var pre := "p%d_" % player
	var j := func(a: String) -> bool: return Input.is_action_just_pressed(pre + a)
	if stage == Stage.READY:
		if j.call("kick"):
			unlock()
		return
	var grid: OptionGrid = _grids[stage]
	if j.call("left"):
		_moved(grid.move(-1, 0))
	elif j.call("right"):
		_moved(grid.move(1, 0))
	elif j.call("up"):
		_moved(grid.move(0, -1))
	elif j.call("down"):
		_moved(grid.move(0, 1))
	elif j.call("punch") or j.call("start"):
		_confirm(grid.value())
	elif j.call("kick"):
		if stage == Stage.ROSTER:
			back_out.emit()
		else:
			stage = (stage - 1) as Stage
			_click()


func _moved(did: bool) -> void:
	if did:
		_click()


func _confirm(v: int) -> void:
	match stage:
		Stage.ROSTER:
			character = v
			# A "?" comedian gets "?" everything: you can't dress a comedian
			# you haven't seen yet (each grid can still be set by hand).
			if character == GameState.RANDOM:
				for s in [Stage.COLOR, Stage.DECAL, Stage.WEAPON]:
					_grids[s].set_items(_grids[s].items, GameState.RANDOM)
			stage = Stage.COLOR
		Stage.COLOR:
			outfit = v
			stage = Stage.DECAL
		Stage.DECAL:
			decor = v
			stage = Stage.WEAPON
		Stage.WEAPON:
			weapon = v
			stage = Stage.READY
			GameState.play_sfx("clear")
			_refresh()
			locked.emit()
			return
	_click()


func _click() -> void:
	GameState.play_sfx("click")
	_refresh()


# ---------------------------------------------------------------- build
func _build(header: String) -> void:
	size = Vector2(PANEL_W, AREA_Y + AREA_H + 20)
	var left := side == 0
	var area_x := 0.0 if left else PANEL_W - AREA_W
	var prev_x := AREA_W + 8.0 if left else 0.0
	var align := HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT

	_header = _label(header, 10, accent, Vector2(area_x, 4), Vector2(AREA_W, 14), align)

	# [stage, cols, rows, tile, gap, y offset inside the area]
	var specs := [
		[Stage.ROSTER, 4, 6, Vector2(40, 40), 4.0, 0.0],
		[Stage.COLOR, 5, 5, Vector2(32, 32), 3.0, 16.0],
		[Stage.DECAL, 5, 7, Vector2(32, 32), 3.0, 16.0],
		[Stage.WEAPON, 4, 4, Vector2(40, 52), 4.0, 16.0],
	]
	for sp in specs:
		var g := OptionGrid.new()
		add_child(g)
		g.configure(sp[1], sp[2], sp[3], sp[4], accent)
		g.position = Vector2(area_x + (AREA_W - g.size.x) / 2.0, AREA_Y + sp[5])
		_grids[sp[0]] = g

	_step_label = _label("", 10, MenuScreen.GOLD, Vector2(area_x, AREA_Y), Vector2(AREA_W, 14),
			HORIZONTAL_ALIGNMENT_CENTER)
	_info_label = _label("", 8, MenuScreen.INK, Vector2(area_x, AREA_Y + AREA_H + 6),
			Vector2(AREA_W, 10), align)
	_summary = _label("", 10, MenuScreen.INK, Vector2(area_x, AREA_Y + 40), Vector2(AREA_W, 90),
			HORIZONTAL_ALIGNMENT_CENTER)
	_ready_label = _label("READY!", 20, accent, Vector2(area_x, AREA_Y + 150), Vector2(AREA_W, 24),
			HORIZONTAL_ALIGNMENT_CENTER)
	Fx.shine(_ready_label, AREA_W, 1.6)
	Fx.pulse(_ready_label, 0.08, 0.8)

	_preview_holder = Node2D.new()
	_preview_holder.position = Vector2(prev_x + PREVIEW_W / 2.0, PREVIEW_FEET_Y)
	add_child(_preview_holder)
	_preview_q = _label("?", 64, MenuScreen.GOLD, Vector2(prev_x, 70), Vector2(PREVIEW_W, 80),
			HORIZONTAL_ALIGNMENT_CENTER)
	_name_label = _label("", 10, MenuScreen.INK, Vector2(prev_x - 10, PREVIEW_FEET_Y + 10),
			Vector2(PREVIEW_W + 20, 14), HORIZONTAL_ALIGNMENT_CENTER)


func _label(text: String, font_size: int, color: Color, pos: Vector2, sz: Vector2,
		align: HorizontalAlignment) -> Label:
	var l := MenuScreen.make_label(text, font_size, color)
	l.position = pos
	l.horizontal_alignment = align
	add_child(l)
	MenuScreen.size_later(l, sz)
	return l


# ---------------------------------------------------------------- display
func _process(delta: float) -> void:
	if _preview_wait > 0.0:
		_preview_wait -= delta
		if _preview_wait <= 0.0:
			_rebuild_preview()


func _refresh() -> void:
	for s in _grids:
		_grids[s].visible = s == stage
	var picking := stage != Stage.ROSTER and stage != Stage.READY
	_step_label.visible = picking
	_summary.visible = stage == Stage.READY
	_ready_label.visible = stage == Stage.READY
	_info_label.visible = stage != Stage.READY
	if stage == Stage.ROSTER:
		var g: OptionGrid = _grids[Stage.ROSTER]
		_info_label.text = "PAGE %d/%d" % [g.page() + 1, g.page_count()]
	elif picking:
		_step_label.text = "%d/3  %s" % [int(stage), STEP_NAMES[stage]]
		_info_label.text = _option_name(stage, _grids[stage].value())
	if stage == Stage.READY:
		_summary.text = "%s\n\n%s\n\n%s" % [_option_name(Stage.COLOR, outfit),
				_option_name(Stage.DECAL, decor), _option_name(Stage.WEAPON, weapon)]
	var ch := _shown_character()
	# One word per line: two-word names fit the preview column, and the name
	# reads as a stacked title card under the fighter.
	_name_label.text = "RANDOM" if ch == GameState.RANDOM \
			else "\n".join(String(GameState.character_data(ch).get("CharacterName", "")) \
				.to_upper().split(" ", false))
	_preview_wait = PREVIEW_DEBOUNCE


func _option_name(s: Stage, v: int) -> String:
	if v == GameState.RANDOM:
		return "RANDOM"
	match s:
		Stage.COLOR:
			return String(CharacterFactory.OUTFITS[v]["name"])
		Stage.DECAL:
			return "NO DECAL" if v == Decorators.NONE else Decorators.decor_name(v).to_upper()
		_:
			return Weapons.weapon_name(v).to_upper()


## The comedian on show: the highlighted one while browsing, the picked one after.
func _shown_character() -> int:
	return _grids[Stage.ROSTER].value() if stage == Stage.ROSTER else character


## What the preview wears: picks already made, the HIGHLIGHTED tile on the grid
## being browsed, and the remembered loadout for steps not reached yet. "?"
## shows the plainest option rather than a random one.
func _shown_loadout() -> Dictionary:
	var o := outfit
	var d := decor
	var w := weapon
	var order := [Stage.ROSTER, Stage.COLOR, Stage.DECAL, Stage.WEAPON]
	var at := order.find(stage) if stage != Stage.READY else 99
	if at < 1:
		o = int(_default_loadout.get("outfit", 0))
	if at < 2:
		d = int(_default_loadout.get("decor", Decorators.NONE))
	if at < 3:
		w = int(_default_loadout.get("weapon", Weapons.DEFAULT))
	match stage:
		Stage.COLOR:
			o = _grids[Stage.COLOR].value()
		Stage.DECAL:
			d = _grids[Stage.DECAL].value()
		Stage.WEAPON:
			w = _grids[Stage.WEAPON].value()
	return {
		"outfit": side if o == GameState.RANDOM else o,  # BLUE / CRIMSON
		"decor": Decorators.NONE if d == GameState.RANDOM else d,
		"weapon": Weapons.DEFAULT if w == GameState.RANDOM else w,
	}


func _rebuild_preview() -> void:
	var ch := _shown_character()
	var lo := _shown_loadout()
	var key := "%d|%d|%d|%d" % [ch, lo["outfit"], lo["decor"], lo["weapon"]]
	if key == _preview_key:
		return
	_preview_key = key
	if is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
	_preview_q.visible = ch == GameState.RANDOM
	if ch == GameState.RANDOM:
		return
	_preview = Battler.new()
	_preview.configure(GameState.character_data(ch))
	_preview.size_scale = PREVIEW_SIZE
	_preview.outfit = int(lo["outfit"])
	_preview.decor = int(lo["decor"])
	_preview.weapon = int(lo["weapon"])
	# Both previews face the middle of the screen, squared up.
	_preview.facing = 1 if side == 0 else -1
	_preview_holder.add_child(_preview)
