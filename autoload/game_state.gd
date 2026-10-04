extends Node
## Global state for Tight 5 BATTLE: the active city edition (games/<id>/),
## audio, hitstop/shake, the two-player input map and the match being set up.
## Trimmed down from Tight 5 FIGHT!'s GameState — no network, no economy.

## Screen shake request (in pixels); the fight scene listens and shakes itself.
signal shake_requested(pixels: float)
## Crowd reactions for CrowdRow: "boo", "laugh", "cheer", "celebrate".
signal crowd_reaction(kind: String)

const SCENE_SPLASH := "res://scenes/splash.tscn"
const SCENE_HOME := "res://scenes/home.tscn"
const SCENE_MODE := "res://scenes/mode_select.tscn"
const SCENE_DIFFICULTY := "res://scenes/difficulty_select.tscn"
const SCENE_FIGHTER_SELECT := "res://scenes/fighter_select.tscn"
const SCENE_VENUE_SELECT := "res://scenes/venue_select.tscn"
const SCENE_FIGHT := "res://scenes/fight.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"
const SCENE_LEADERBOARD := "res://scenes/leaderboard.tscn"

## Names the city edition this build uses (see games/<id>/).
const ACTIVE_GAME_PATH := "res://data/active_game.json"
## Operator settings for this build (the leaderboard reset password...).
const CONFIG_PATH := "res://data/config.json"
const SETTINGS_PATH := "user://%s_battle_settings.json"
## The local leaderboard's records (written by the leaderboard milestone).
const LEADERBOARD_PATH := "user://%s_battle_leaderboard.json"

## Shared defaults for body sheets; a game may override them in its manifest.
const DEFAULT_BODY := {
	"M": "res://shared/assets/bodies/body_male.png",
	"F": "res://shared/assets/bodies/body_female.png",
}

# ---------------------------------------------------------------- audio
const SFX_BASE := "res://shared/assets/sfx/sfx_"
const SFX_NAMES := ["punch", "kick", "hurt", "defeat", "smash", "clear", "click", "throw", "swing"]
## A sound with no file of its own borrows another's sample.
const SFX_ALIASES := {"swing": "throw"}
const HYPHEN_SFX_BASE := "res://shared/assets/sfx/sfx-"
const CROWD_NAMES := ["boo", "cheer", "laugh"]
## Per-name gap so two crowd cheers on the same frame never stack.
const CROWD_GAP_MS := 400
const SCREAM_PATH := "res://shared/assets/sfx/tight-5-fight-scream"
const SFX_POOL_SIZE := 8

# ---------------------------------------------------------------- hitstop
const HITSTOP_TIME := 0.05
const HITSTOP_SCALE := 0.05

# ---------------------------------------------------------------- match
enum Mode { PVP, PVC, CVC }
enum Difficulty { BEGINNER, NORMAL, HARD }
const DIFFICULTY_NAMES := ["BEGINNER", "NORMAL", "HARD"]
## A "?" pick anywhere in the setup: resolved to a real one when the fight loads.
const RANDOM := -2

var active_game := "tight5"
var manifest := {}
var characters: Array = []
## Indices into `characters` that can be picked (isDisabled ones dropped).
var playable: Array[int] = []
var venues: Array = []

var music_volume := 0.8
var sfx_volume := 0.8
## Remembered between sessions: the last CPU levels picked [left, right], each
## player's last loadout (by name/id — "?" means random) and last fighter.
var last_difficulty: Array[int] = [Difficulty.NORMAL, Difficulty.NORMAL]
var loadouts := {
	1: {"outfit": "BLUE", "weapon": "mic", "decor": ""},
	2: {"outfit": "CRIMSON", "weapon": "mic", "decor": ""},
}
var last_character := {1: RANDOM, 2: RANDOM}

## The fight to run next. Built by the menus (milestone 3); until then the
## splash builds a random one. Each side:
##   {"character": int, "outfit": int, "weapon": int, "decor": int,
##    "cpu": bool, "difficulty": Difficulty}
## Any of character/outfit/weapon/decor may be RANDOM.
var match_setup := {}

var _settings_file := ""
var _leaderboard_file := ""
## Current 1P VS CPU win streak per difficulty (Leaderboard). Lives for one
## sitting: HOME resets it.
var vs_cpu_streak: Array[int] = [0, 0, 0]
## SETTINGS → CONTROLS → SIDES: when true, gamepad 2 (the right-hand
## controls) plays P1 and gamepad 1 plays P2 — someone at the right-hand stick
## can take on the CPU, and it fixes the two identical cabinet encoders coming
## up in the wrong order. Keyboards never swap.
var swap_pads := false
## HOME → DEMO: endless random CPU vs CPU fights until any button is pressed.
var demo_mode := false
## data/config.json, loaded at boot.
var config := {}
var _music_player: AudioStreamPlayer
var _music_streams := {}
var _music_track := ""
## SETTINGS → RADIO: every song on the dial, [{id, station, kind, path}] with
## kind "MENU" or "FIGHT" (from shared/assets/music/stations.json).
var music_tracks: Array = []
## The song picked per music slot ("main" = menus, "venue" = fights), by track
## id; "" = the edition's own song from game.json.
var music_choice := {"main": "", "venue": ""}
## The edition's own song per slot, by track id (found by path).
var _music_default := {"main": "", "venue": ""}
var _sfx_streams := {}
var _crowd_streams := {}
var _crowd_last_ms := {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _scream_player: AudioStreamPlayer
var _in_hitstop := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_active_game()
	_load_roster()
	_load_settings()
	_register_input_actions()
	_apply_pad_sides()
	_setup_audio()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs
				else DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- edition
func _load_active_game() -> void:
	active_game = String(_load_json(ACTIVE_GAME_PATH).get("active", "tight5"))
	config = _load_json(CONFIG_PATH)
	manifest = _load_json(game_path("game.json"))
	_settings_file = SETTINGS_PATH % active_game
	_leaderboard_file = LEADERBOARD_PATH % active_game


## Prefix a game-relative path (as stored in game.json / characters.json /
## venues.json) with this build's game folder. The one place game ids turn into
## res:// paths — engine code never hardcodes res://games/... itself.
func game_path(rel: String) -> String:
	return "res://games/%s/%s" % [active_game, rel]


func _load_roster() -> void:
	var chars: Array = _load_json(game_path(String(manifest.get("characters", "characters.json")))).get("characters", [])
	for c in chars:
		if String(c.get("HeadSpritePath", "")) != "":
			c["HeadSpritePath"] = game_path(String(c["HeadSpritePath"]))
	characters = chars
	playable = []
	for i in characters.size():
		if not bool(characters[i].get("isDisabled", false)):
			playable.append(i)
	venues = []
	for v in _load_json(game_path(String(manifest.get("venues", "venues.json")))).get("venues", []):
		if bool(v.get("isDisabled", false)):
			continue
		for k in ["ExteriorSpritePath", "InteriorSpritePath"]:
			if String(v.get(k, "")) != "":
				v[k] = game_path(String(v[k]))
		venues.append(v)
	Weapons.load_roster(game_path(String(manifest.get("weapons", "weapons.json"))))
	Decorators.load_roster(game_path(String(manifest.get("decorators", "decorators.json"))))


func body_path(body_type: String) -> String:
	var ov: Dictionary = manifest.get("overrides", {})
	var p = ov.get("bodyMale" if body_type == "M" else "bodyFemale", null)
	if p != null and String(p) != "":
		return game_path(String(p))
	return DEFAULT_BODY.get(body_type, DEFAULT_BODY["M"])


func projectile_path() -> String:
	var p = manifest.get("projectileSprite", null)
	return game_path(String(p)) if p != null and String(p) != "" else ""


func splash_path() -> String:
	return game_path(String(manifest.get("backgrounds", {}).get("splash", "assets/backgrounds/splash.png")))


# ---------------------------------------------------------------- match setup
## Start setting up a fight in `mode`: who's CPU is decided, everything else
## is still to be picked. CPU sides take the remembered difficulty.
func begin_setup(mode: int) -> void:
	match_setup = {
		"mode": mode,
		"venue": RANDOM,
		"sides": [
			_random_side(mode == Mode.CVC, last_difficulty[0]),
			_random_side(mode != Mode.PVP, last_difficulty[1]),
		],
	}


func is_cpu(side: int) -> bool:
	var sides: Array = match_setup.get("sides", [])
	return side < sides.size() and bool(sides[side].get("cpu", false))


func setup_mode() -> int:
	return int(match_setup.get("mode", Mode.PVP))


func set_difficulty(side: int, level: int) -> void:
	match_setup["sides"][side]["difficulty"] = level
	last_difficulty[side] = level
	_save_settings()


## A player's remembered loadout as indices ("?" -> RANDOM).
func remembered_loadout(player: int) -> Dictionary:
	var l: Dictionary = loadouts.get(player, {})
	var o := String(l.get("outfit", "BLUE"))
	var w := String(l.get("weapon", "mic"))
	var d := String(l.get("decor", ""))
	return {
		"outfit": RANDOM if o == "?" else CharacterFactory.outfit_index_by_name(o),
		"weapon": RANDOM if w == "?" else Weapons.index_by_id(w),
		"decor": RANDOM if d == "?" else Decorators.index_by_id(d),
	}


func remember_loadout(player: int, outfit: int, weapon: int, decor: int) -> void:
	loadouts[player] = {
		"outfit": "?" if outfit == RANDOM else String(CharacterFactory.OUTFITS[outfit]["name"]),
		"weapon": "?" if weapon == RANDOM else Weapons.id_of(weapon),
		"decor": "?" if decor == RANDOM else Decorators.id_of(decor),
	}
	_save_settings()


func remember_character(player: int, idx: int) -> void:
	last_character[player] = idx
	_save_settings()


## A fully random fight: two random comedians (never the same one), random
## loadouts, random venue. `mode` decides who is CPU-controlled.
func random_match(mode := Mode.PVP, difficulty := Difficulty.NORMAL) -> void:
	match_setup = {
		"mode": mode,
		"venue": RANDOM,
		"sides": [
			_random_side(mode == Mode.CVC, difficulty),
			_random_side(mode != Mode.PVP, difficulty),
		],
	}


## Same mode and same CPU difficulties, fresh random fighters/loadouts/venue.
func reroll_match() -> void:
	match_setup["venue"] = RANDOM
	for side in match_setup.get("sides", []):
		for k in ["character", "outfit", "weapon", "decor"]:
			side[k] = RANDOM
		side["locked"] = false


## DEMO: a fresh all-random CPU vs CPU fight, both sides HARD (the most
## action). The fight scene chains them until someone presses a button.
func start_demo() -> void:
	random_match(Mode.CVC, Difficulty.HARD)
	demo_mode = true


## CPU vs CPU with its own difficulty per side (an exhibition).
func cpu_exhibition(left: int, right: int) -> void:
	random_match(Mode.CVC)
	match_setup["sides"][0]["difficulty"] = left
	match_setup["sides"][1]["difficulty"] = right


func _random_side(cpu: bool, difficulty: int) -> Dictionary:
	return {"character": RANDOM, "outfit": RANDOM, "weapon": RANDOM,
			"decor": RANDOM, "cpu": cpu, "difficulty": difficulty}


## Turn every RANDOM in match_setup into a real pick. Called once per match
## (not per round), so a "?" fighter stays the same comedian all match.
func resolve_match() -> void:
	var sides: Array = match_setup.get("sides", [])
	var taken := -1
	for s in sides:
		if int(s["character"]) == RANDOM:
			var pool := playable.filter(func(i): return i != taken)
			s["character"] = pool.pick_random() if not pool.is_empty() else playable[0]
		taken = int(s["character"])
		if int(s["outfit"]) == RANDOM:
			s["outfit"] = randi() % CharacterFactory.OUTFITS.size()
		if int(s["weapon"]) == RANDOM:
			var ws := Weapons.available()
			s["weapon"] = ws.pick_random() if not ws.is_empty() else Weapons.DEFAULT
		if int(s["decor"]) == RANDOM:
			# NONE is one of the options, so a random fighter is sometimes bare.
			var ds: Array = Decorators.available()
			ds.append(Decorators.NONE)
			s["decor"] = ds.pick_random()
	# Mirror match in the same shirt: step the right-hand fighter to the next
	# outfit so the two can always be told apart.
	if sides.size() == 2 and int(sides[0]["character"]) == int(sides[1]["character"]) \
			and int(sides[0]["outfit"]) == int(sides[1]["outfit"]):
		sides[1]["outfit"] = (int(sides[1]["outfit"]) + 1) % CharacterFactory.OUTFITS.size()
	if int(match_setup.get("venue", RANDOM)) == RANDOM:
		match_setup["venue"] = randi() % maxi(venues.size(), 1)


func character_data(idx: int) -> Dictionary:
	if idx < 0 or idx >= characters.size():
		return {}
	return characters[idx]


func venue_data(idx: int) -> Dictionary:
	if idx < 0 or idx >= venues.size():
		return {}
	return venues[idx]


# ---------------------------------------------------------------- input
## Every action exists once per player ("p1_punch", "p2_punch"...), so the
## cabinet's two control sets — and later its encoder mapping — are pure data.
## Keyboard for PC testing, plus gamepad 0 -> P1 and gamepad 1 -> P2.
const KEYS := {
	1: {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
		"punch": KEY_J, "kick": KEY_K, "throw": KEY_L, "swing": KEY_U,
		"block": KEY_I, "select": KEY_O, "back": KEY_P, "start": KEY_ENTER},
	2: {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
		"punch": KEY_KP_1, "kick": KEY_KP_2, "throw": KEY_KP_3, "swing": KEY_KP_4,
		"block": KEY_KP_5, "select": KEY_KP_6, "back": KEY_KP_7, "start": KEY_KP_ENTER},
}
## Raw indices off the cabinet encoder's BUTTON TEST, not Xbox names.
const PAD_BUTTONS := {
	"select": 0, "back": 1, "punch": 2, "kick": 3, "swing": 4, "block": 5,
	"throw": 7, "start": JOY_BUTTON_START,
	# The cabinet encoders report the stick as a D-pad with both directions
	# reversed (BUTTON TEST: left 14, right 13, up 12, down 11).
	"left": JOY_BUTTON_DPAD_RIGHT, "right": JOY_BUTTON_DPAD_LEFT,
	"up": JOY_BUTTON_DPAD_DOWN, "down": JOY_BUTTON_DPAD_UP,
}
## Stick directions: [axis, sign]. The encoders can also report the stick as
## axes (mode switch / replug), reversed too: left 0+, right 0-, up 1+, down 1-.
const PAD_AXES := {
	"left": [JOY_AXIS_LEFT_X, 1.0], "right": [JOY_AXIS_LEFT_X, -1.0],
	"up": [JOY_AXIS_LEFT_Y, 1.0], "down": [JOY_AXIS_LEFT_Y, -1.0],
}
const STICK_DEADZONE := 0.5


func _register_input_actions() -> void:
	for player in KEYS:
		var device: int = player - 1
		for action in KEYS[player]:
			var name := "p%d_%s" % [player, action]
			if InputMap.has_action(name):
				continue
			InputMap.add_action(name, STICK_DEADZONE)
			var k := InputEventKey.new()
			k.physical_keycode = KEYS[player][action]
			k.device = -1
			InputMap.action_add_event(name, k)
			if PAD_BUTTONS.has(action):
				var b := InputEventJoypadButton.new()
				b.button_index = PAD_BUTTONS[action]
				b.device = device
				InputMap.action_add_event(name, b)
			if PAD_AXES.has(action):
				var m := InputEventJoypadMotion.new()
				m.axis = PAD_AXES[action][0]
				m.axis_value = PAD_AXES[action][1]
				m.device = device
				InputMap.action_add_event(name, m)
	# Esc pauses too (P1's side), for PC play.
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.device = -1
	InputMap.action_add_event("p1_start", esc)


## Point every gamepad binding at the pad its player uses (see swap_pads).
func _apply_pad_sides() -> void:
	for player in KEYS:
		var device: int = (player - 1) if not swap_pads else (2 - player)
		for action in KEYS[player]:
			for e in InputMap.action_get_events("p%d_%s" % [player, action]):
				if e is InputEventJoypadButton or e is InputEventJoypadMotion:
					e.device = device


func set_swap_pads(v: bool) -> void:
	swap_pads = v
	_apply_pad_sides()
	_save_settings()


# ---------------------------------------------------------------- juice
## Freeze the whole game briefly on a solid hit. Uses Engine.time_scale, so
## physics, animations and tweens all pause together; the restore timer runs
## on real time (ignore_time_scale) or it would never fire.
func hitstop(duration := HITSTOP_TIME, frozen_scale := HITSTOP_SCALE) -> void:
	if _in_hitstop:
		return
	_in_hitstop = true
	Engine.time_scale = frozen_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_in_hitstop = false


func request_shake(pixels := 3.0) -> void:
	shake_requested.emit(pixels)


# ---------------------------------------------------------------- audio
func _setup_audio() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	_apply_volume("Music", music_volume)
	_apply_volume("SFX", sfx_volume)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_load_stations()
	var tracks: Dictionary = manifest.get("audio", {})
	for pair in [["main", "musicMain"], ["venue", "musicVenue"]]:
		var rel = tracks.get(pair[1], null)
		if rel == null or String(rel) == "":
			continue
		var path := game_path(String(rel))
		for t in music_tracks:
			if t["path"] == path:
				_music_default[pair[0]] = t["id"]
		var s := _load_stream(path)
		if s:
			_set_looping(s)
			_music_streams[pair[0]] = s
	# The RADIO picks replace the edition's songs.
	for slot in music_choice:
		if music_choice[slot] != "":
			_load_music_slot(slot, music_choice[slot])
	for sfx_name in SFX_NAMES:
		var s := _load_stream(SFX_BASE + sfx_name)
		if s:
			_sfx_streams[sfx_name] = s
	for crowd_name in CROWD_NAMES:
		var s := _load_stream(HYPHEN_SFX_BASE + crowd_name)
		if s:
			_crowd_streams[crowd_name] = s
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	var scream := _load_stream(SCREAM_PATH)
	if scream:
		_scream_player = AudioStreamPlayer.new()
		_scream_player.bus = "SFX"
		_scream_player.stream = scream
		add_child(_scream_player)


const STATIONS_PATH := "res://shared/assets/music/stations.json"


func _load_stations() -> void:
	music_tracks.clear()
	for st in _load_json(STATIONS_PATH).get("stations", []):
		for kind in ["menu", "fight"]:
			var path := String(st.get(kind, ""))
			if path != "" and _load_stream_exists(path):
				music_tracks.append({"id": "%s_%s" % [st.get("id", ""), kind],
						"station": String(st.get("name", "")), "kind": kind.to_upper(),
						"path": path})


func _load_stream_exists(base_path: String) -> bool:
	for ext in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(base_path + ext):
			return true
	return false


func music_track(id: String) -> Dictionary:
	for t in music_tracks:
		if t["id"] == id:
			return t
	return {}


## The track id playing in `slot` ("main"/"venue"): the RADIO pick, else the
## edition's own song.
func music_track_id(slot: String) -> String:
	return music_choice[slot] if music_choice[slot] != "" else _music_default[slot]


## RADIO: put track `id` in `slot`, save it, and if that slot is the one
## playing, switch to the new song straight away.
func set_music_choice(slot: String, id: String) -> void:
	music_choice[slot] = "" if id == _music_default[slot] else id
	_load_music_slot(slot, id)
	_save_settings()
	if _music_track == slot:
		_music_track = ""
		play_music(slot)


func _load_music_slot(slot: String, id: String) -> void:
	var t := music_track(id)
	if t.is_empty():
		music_choice[slot] = ""
		return
	var s := _load_stream(String(t["path"]))
	if s:
		_set_looping(s)
		_music_streams[slot] = s


## Swap the looping background track; no-op if it's already playing.
func play_music(track: String) -> void:
	if not _music_streams.has(track) or track == _music_track:
		return
	_music_track = track
	_music_player.stream = _music_streams[track]
	_music_player.play()


func play_sfx(sfx_name: String) -> void:
	var stream_name := sfx_name
	if not _sfx_streams.has(stream_name):
		stream_name = str(SFX_ALIASES.get(sfx_name, sfx_name))
	if not _sfx_streams.has(stream_name):
		return
	_play_pooled(_sfx_streams[stream_name])


func play_crowd(crowd_name: String) -> void:
	if not _crowd_streams.has(crowd_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_crowd_last_ms.get(crowd_name, -CROWD_GAP_MS)) < CROWD_GAP_MS:
		return
	_crowd_last_ms[crowd_name] = now
	_play_pooled(_crowd_streams[crowd_name])


## The FIGHT! battle cry.
func play_scream() -> void:
	if is_instance_valid(_scream_player):
		_scream_player.play()


func _play_pooled(stream: AudioStream) -> void:
	var p: AudioStreamPlayer = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.play()


func _load_stream(base_path: String) -> AudioStream:
	for ext in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(base_path + ext):
			return load(base_path + ext)
	return null


func _set_looping(s: AudioStream) -> void:
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.data.size() / (2.0 * (2 if s.stereo else 1)))


# ---------------------------------------------------------------- settings
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volume("Music", music_volume)
	_save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volume("SFX", sfx_volume)
	_save_settings()


func _apply_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _load_settings() -> void:
	var d := _load_json(_settings_file)
	music_volume = clampf(float(d.get("music", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(d.get("sfx", 0.8)), 0.0, 1.0)
	var mc: Dictionary = d.get("music_choice", {}) if d.get("music_choice") is Dictionary else {}
	for slot in music_choice:
		music_choice[slot] = String(mc.get(slot, ""))
	swap_pads = bool(d.get("swap_pads", false))
	var diff: Array = d.get("difficulty", [])
	for i in mini(diff.size(), 2):
		last_difficulty[i] = clampi(int(diff[i]), 0, Difficulty.HARD)
	var lo: Dictionary = d.get("loadouts", {})
	for p in [1, 2]:
		if lo.get(str(p)) is Dictionary:
			loadouts[p] = lo[str(p)]
	var lc: Dictionary = d.get("last_character", {})
	for p in [1, 2]:
		if lc.has(str(p)):
			last_character[p] = int(lc[str(p)])


func _save_settings() -> void:
	_save_json(_settings_file, {
		"music": music_volume, "sfx": sfx_volume,
		"music_choice": music_choice,
		"swap_pads": swap_pads,
		"difficulty": last_difficulty,
		"loadouts": {"1": loadouts[1], "2": loadouts[2]},
		"last_character": {"1": last_character[1], "2": last_character[2]},
	})


## The digits SETTINGS asks for before a leaderboard reset. Empty = no password.
func reset_password() -> String:
	return str(config.get("leaderboardResetPassword", ""))


## Wipe every leaderboard record (SETTINGS → LEADERBOARD, before an event).
func reset_leaderboard() -> void:
	if FileAccess.file_exists(_leaderboard_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_leaderboard_file))


# ---------------------------------------------------------------- json helpers
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _save_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
