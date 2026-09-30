extends Node2D
## One match: two fighters in the chosen venue, best of 3 rounds.
## Round flow: ROUND n → FIGHT! → (KO or TIME) → winner → next round, until
## someone has 2 round wins. A draw (equal health at TIME, or a double KO)
## replays the round and counts for nobody. Fighters are rebuilt fresh every
## round, so health, bottles and the swing cooldown all reset with them.

enum Phase { INTRO, FIGHT, ROUND_END, MATCH_END }

## Floor line and fighter size, from Tight 5 FIGHT!'s venue phase.
const GROUND_Y := 310.0
const FIGHTER_SCALE := 2.2425
const ROUND_TIME := 60.0
const WINS_NEEDED := 2
const START_X := [160.0, 480.0]
## The screen edges are walls.
const WALL := 30.0
## Closest two fighters' feet can get. Fighters in T5F never collide, but in a
## 1v1 standing inside each other makes every punch whiff, so they push apart.
## ~ one body width at venue scale; punch reach (~91px) still lands from here.
const MIN_GAP := 40.0
const INTRO_ROUND_S := 1.2
const INTRO_FIGHT_S := 0.7
const KO_CARD_S := 1.4
const WINNER_CARD_S := 2.2

var hud: FightHud
var _fighters: Array[Battler] = [null, null]
var _names: Array[String] = ["", ""]
var _wins: Array[int] = [0, 0]
var _round := 1
var _time_left := ROUND_TIME
## Fighting time across every round so far (VS CPU fastest win).
var _match_time := 0.0
var _phase := Phase.INTRO
var _ko_check_pending := false
var _pause_layer: CanvasLayer
var _pause_menu: MenuList
var _results_layer: CanvasLayer
var _unpaused_frame := -1


func _ready() -> void:
	# Run on its own (F6 in the editor): make up a random 1P vs 1P match.
	if GameState.match_setup.is_empty():
		GameState.random_match()
	GameState.resolve_match()
	var setup := GameState.match_setup
	_build_background(GameState.venue_data(int(setup.get("venue", 0))))
	# Foreground crowd along the bottom edge (sets its own z_index).
	add_child(CrowdRow.new())
	hud = FightHud.new()
	add_child(hud)
	for side in 2:
		var cfg := GameState.character_data(int(setup["sides"][side]["character"]))
		_names[side] = String(cfg.get("CharacterName", "P%d" % (side + 1))).to_upper()
	GameState.shake_requested.connect(_on_shake)
	GameState.play_music("venue")
	_build_pause_menu()
	Fx.fade_in(self, 0.3)
	_start_round(true)


# ---------------------------------------------------------------- setup
func _build_background(data: Dictionary) -> void:
	var view := get_viewport_rect().size
	var path := String(data.get("InteriorSpritePath", ""))
	if ResourceLoader.exists(path):
		var bg := Sprite2D.new()
		bg.texture = load(path)
		bg.centered = false
		bg.scale = view / bg.texture.get_size()
		bg.z_index = -10
		add_child(bg)
	else:
		var rect := ColorRect.new()
		rect.color = Color(0.2, 0.1, 0.15)
		rect.size = view
		rect.z_index = -10
		add_child(rect)


## Name over the health bar: a CPU fighter carries its difficulty.
func _hud_name(side: int) -> String:
	var s: Dictionary = GameState.match_setup["sides"][side]
	if not bool(s.get("cpu", false)):
		return _names[side]
	var tag := "CPU %s" % GameState.DIFFICULTY_NAMES[int(s.get("difficulty", 1))]
	return "%s  %s" % [_names[side], tag] if side == 0 else "%s  %s" % [tag, _names[side]]


func _spawn_fighter(side: int) -> Battler:
	var s: Dictionary = GameState.match_setup["sides"][side]
	var f := Battler.new()
	f.configure(GameState.character_data(int(s["character"])))
	f.set_side(side + 1)
	f.size_scale = FIGHTER_SCALE
	f.outfit = int(s["outfit"])
	f.weapon = int(s["weapon"])
	f.decor = int(s["decor"])
	if bool(s.get("cpu", false)):
		f.controller = CpuController.new(int(s.get("difficulty", GameState.Difficulty.NORMAL)))
	else:
		f.controller = FighterController.Human.new(side + 1)
	f.position = Vector2(START_X[side], GROUND_Y)
	f.facing = 1 if side == 0 else -1
	f.died.connect(_on_fighter_died)
	add_child(f)
	return f


# ---------------------------------------------------------------- rounds
func _start_round(first: bool) -> void:
	for f in _fighters:
		if is_instance_valid(f):
			f.queue_free()
	for b in get_tree().get_nodes_in_group("projectiles"):
		b.queue_free()
	for side in 2:
		_fighters[side] = _spawn_fighter(side)
	_fighters[0].opponent = _fighters[1]
	_fighters[1].opponent = _fighters[0]
	for side in 2:
		hud.bind(side, _fighters[side], _hud_name(side))
		hud.set_round_wins(side, _wins[side])
	_time_left = ROUND_TIME
	hud.set_timer(_time_left)
	_phase = Phase.INTRO
	var final: bool = _wins[0] == WINS_NEEDED - 1 and _wins[1] == WINS_NEEDED - 1
	hud.announce("FINAL ROUND" if final else "ROUND %d" % _round)
	await get_tree().create_timer(INTRO_ROUND_S).timeout
	hud.announce("FIGHT!", Color(1.0, 0.35, 0.25), INTRO_FIGHT_S)
	if first:
		GameState.play_scream()
	_phase = Phase.FIGHT
	for f in _fighters:
		f.set_input_enabled(true)


func _physics_process(delta: float) -> void:
	# Both controllers read the fight first (this node runs before its fighter
	# children), so the left fighter — updated first — gets no head start.
	for f in _fighters:
		if is_instance_valid(f) and f.state != Fighter.FState.DEAD:
			f.controller.tick(delta, f)
	if _phase == Phase.FIGHT:
		_time_left -= delta
		hud.set_timer(_time_left)
		if _time_left <= 0.0:
			_time_up()
	_keep_apart()


func _process(_delta: float) -> void:
	if _phase == Phase.FIGHT and not get_tree().paused \
			and Engine.get_process_frames() != _unpaused_frame \
			and (Input.is_action_just_pressed("p1_start")
				or Input.is_action_just_pressed("p2_start")):
		_pause(true)


## Walls at the screen edges, and no standing inside each other.
func _keep_apart() -> void:
	var a := _fighters[0]
	var b := _fighters[1]
	if not (is_instance_valid(a) and is_instance_valid(b)):
		return
	var right := get_viewport_rect().size.x - WALL
	if a.state != Fighter.FState.DEAD and b.state != Fighter.FState.DEAD:
		var dx := b.position.x - a.position.x
		if absf(dx) < MIN_GAP:
			var dir := signf(dx) if dx != 0.0 else float(a.facing)
			var push := (MIN_GAP - absf(dx)) / 2.0
			a.position.x -= dir * push
			b.position.x += dir * push
	for f in _fighters:
		f.position.x = clampf(f.position.x, WALL, right)


## A KO is resolved at the end of the frame, so two fighters dropping on the
## same frame read as a double KO (a draw) rather than whoever died first.
func _on_fighter_died(_f: Fighter) -> void:
	if _phase != Phase.FIGHT or _ko_check_pending:
		return
	_ko_check_pending = true
	_resolve_ko.call_deferred()


func _resolve_ko() -> void:
	_ko_check_pending = false
	if _phase != Phase.FIGHT:
		return
	var dead := [_fighters[0].state == Fighter.FState.DEAD,
			_fighters[1].state == Fighter.FState.DEAD]
	var winner := -1
	if dead[0] and not dead[1]:
		winner = 1
	elif dead[1] and not dead[0]:
		winner = 0
	_end_round(winner, "K.O.!")


func _time_up() -> void:
	var h0 := _fighters[0].health / _fighters[0].max_health
	var h1 := _fighters[1].health / _fighters[1].max_health
	var winner := -1
	if h0 > h1:
		winner = 0
	elif h1 > h0:
		winner = 1
	_end_round(winner, "TIME!")


## `winner` is 0/1, or -1 for a draw.
func _end_round(winner: int, card: String) -> void:
	_phase = Phase.ROUND_END
	_time_left = maxf(_time_left, 0.0)
	_match_time += ROUND_TIME - _time_left
	hud.set_timer(_time_left)
	for f in _fighters:
		f.set_input_enabled(false)
	hud.announce(card, Color(1.0, 0.35, 0.25))
	await get_tree().create_timer(KO_CARD_S).timeout
	if winner == -1:
		hud.announce("DRAW")
		GameState.play_crowd("boo")
		GameState.crowd_reaction.emit("boo")
		await get_tree().create_timer(WINNER_CARD_S).timeout
		_start_round(false)
		return
	_wins[winner] += 1
	hud.set_round_wins(winner, _wins[winner])
	GameState.play_crowd("cheer")
	GameState.crowd_reaction.emit("celebrate")
	GameState.play_sfx("clear")
	if _wins[winner] >= WINS_NEEDED:
		hud.announce("%s WINS!" % _names[winner])
		await get_tree().create_timer(WINNER_CARD_S).timeout
		_match_over(winner)
		return
	hud.announce("%s WINS" % _names[winner])
	await get_tree().create_timer(WINNER_CARD_S).timeout
	_round += 1
	_start_round(false)


func _match_over(winner: int) -> void:
	_phase = Phase.MATCH_END
	hud.clear_announce()
	var broke := Leaderboard.record_match(GameState.match_setup, winner, _match_time)
	_results_layer = CanvasLayer.new()
	_results_layer.layer = 20
	add_child(_results_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = get_viewport_rect().size
	_results_layer.add_child(dim)
	var title := _big_label("%s WINS!" % _names[winner], 20)
	title.position = Vector2(0, 90)
	_results_layer.add_child(title)
	Fx.shine(title, 640, 2.0)
	Fx.twinkles(_results_layer, Rect2(80, 70, 480, 80), 16)
	Fx.burst(_results_layer, Vector2(320, 100), 40, Color(1.0, 0.85, 0.4), 200.0)
	var score := _big_label("%d - %d" % [_wins[0], _wins[1]], 16)
	score.position = Vector2(0, 124)
	_results_layer.add_child(score)
	_show_records(winner, broke)
	var menu := MenuList.new()
	menu.position = Vector2(220, 175)
	menu.size = Vector2(200, 120)
	_results_layer.add_child(menu)
	menu.set_options(["REMATCH", "NEW FIGHT", "HOME"])
	menu.chosen.connect(_on_results_chosen)


## Under the score: the running VS CPU streak, and a flashing NEW RECORD!
## for any leaderboard record this match just set.
func _show_records(winner: int, broke: Dictionary) -> void:
	var lines: Array[String] = []
	if broke.has("fastest"):
		lines.append("NEW RECORD!  #%d FASTEST WIN  %s" % [broke["fastest"],
				Leaderboard.format_time(snappedf(_match_time, 0.1))])
	if broke.has("streak"):
		lines.append("NEW RECORD!  BEST STREAK  %d" % broke["streak"])
	elif GameState.setup_mode() == GameState.Mode.PVC and winner == 0:
		var lvl := int(GameState.match_setup["sides"][1].get("difficulty", 0))
		lines.append("WIN STREAK  %d" % GameState.vs_cpu_streak[lvl])
	for i in lines.size():
		var record := lines[i].begins_with("NEW")
		var l := _big_label(lines[i], 8)
		l.position = Vector2(0, 146 + i * 12)
		l.modulate = Color(0.55, 1.0, 0.6) if record else Color(0.85, 0.85, 0.9)
		_results_layer.add_child(l)
		if record:
			Fx.shine(l, 640, 1.4)
			var tw := l.create_tween().set_loops()
			tw.tween_property(l, "modulate:a", 0.45, 0.35)
			tw.tween_property(l, "modulate:a", 1.0, 0.35)


func _on_results_chosen(i: int) -> void:
	match i:
		0:  # same fighters, same venue: the setup is already resolved
			get_tree().reload_current_scene()
		1:  # same mode and CPU levels, pick new fighters
			GameState.reroll_match()
			get_tree().change_scene_to_file(GameState.SCENE_FIGHTER_SELECT)
		2:
			get_tree().change_scene_to_file(GameState.SCENE_HOME)


# ---------------------------------------------------------------- pause
func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 30
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.visible = false
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = get_viewport_rect().size
	_pause_layer.add_child(dim)
	var title := _big_label("PAUSED", 20)
	title.position = Vector2(0, 110)
	_pause_layer.add_child(title)
	_pause_menu = MenuList.new()
	_pause_menu.position = Vector2(220, 160)
	_pause_menu.size = Vector2(200, 80)
	_pause_layer.add_child(_pause_menu)
	_pause_menu.set_options(["RESUME", "QUIT"])
	_pause_menu.chosen.connect(_on_pause_chosen)
	_pause_menu.back_pressed.connect(func(): _pause(false))


func _pause(on: bool) -> void:
	get_tree().paused = on
	_pause_layer.visible = on
	if on:
		_pause_menu.set_options(["RESUME", "QUIT"])
	else:
		_unpaused_frame = Engine.get_process_frames()


func _on_pause_chosen(i: int) -> void:
	_pause(false)
	if i == 1:
		get_tree().change_scene_to_file(GameState.SCENE_HOME)


# ---------------------------------------------------------------- juice
## Screen shake: the room has no camera, so bump the scene root. The HUD and
## menus are CanvasLayers and correctly stay still.
func _on_shake(px: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "position",
				Vector2(randf_range(-px, px), randf_range(-px, px)), 0.03)
	tw.tween_property(self, "position", Vector2.ZERO, 0.03)


func _big_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	MenuScreen.size_later(l, Vector2(get_viewport_rect().size.x, 30))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.modulate = Color(1.0, 0.85, 0.4)
	return l
