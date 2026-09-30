class_name Leaderboard
extends RefCounted
## The local leaderboard's records, in user://<game>_battle_leaderboard.json
## (GameState.LEADERBOARD_PATH; SETTINGS wipes the file). Written after every
## completed match. Comedians are keyed by CharacterId, which never changes, so
## a renamed comedian keeps their record.
##
##   fighters: { "<CharacterId>": {"wins": n, "fights": n} }  — any mode, human or CPU
##   vs_cpu:   one entry per difficulty, human (left side, 1P VS CPU) wins only:
##     best_streak: {"streak": n, "character": id}  — longest run of wins
##     fastest:     [{"time": seconds, "character": id}, ...]  — top FASTEST_KEEP
##
## A streak is "one sitting": it keeps counting through REMATCH and NEW FIGHT,
## and ends on a loss or on going back to HOME (GameState.vs_cpu_streak).

const FASTEST_KEEP := 3


static func load_data() -> Dictionary:
	var d := GameState._load_json(GameState._leaderboard_file)
	if not (d.get("fighters") is Dictionary):
		d["fighters"] = {}
	var vs: Array = d.get("vs_cpu") if d.get("vs_cpu") is Array else []
	while vs.size() < GameState.DIFFICULTY_NAMES.size():
		vs.append({})
	for e in vs:
		if not (e.get("best_streak") is Dictionary):
			e["best_streak"] = {"streak": 0, "character": ""}
		if not (e.get("fastest") is Array):
			e["fastest"] = []
	d["vs_cpu"] = vs
	return d


## Record a finished match. `winner` is the winning side (0/1), `seconds` the
## fighting time across all its rounds. Returns what it broke, for the results
## screen: {"streak": n} and/or {"fastest": rank (1-based)}.
static func record_match(setup: Dictionary, winner: int, seconds: float) -> Dictionary:
	var d := load_data()
	var sides: Array = setup["sides"]
	var ids: Array[String] = []
	for side in 2:
		var cid := character_id(int(sides[side]["character"]))
		ids.append(cid)
		var f: Dictionary = d["fighters"].get(cid, {"wins": 0, "fights": 0})
		f["fights"] = int(f["fights"]) + 1
		if side == winner:
			f["wins"] = int(f["wins"]) + 1
		d["fighters"][cid] = f

	var broke := {}
	if int(setup.get("mode", -1)) == GameState.Mode.PVC:
		var lvl := int(sides[1].get("difficulty", 0))
		var e: Dictionary = d["vs_cpu"][lvl]
		if winner == 0:
			GameState.vs_cpu_streak[lvl] += 1
			var n: int = GameState.vs_cpu_streak[lvl]
			if n > int(e["best_streak"]["streak"]):
				e["best_streak"] = {"streak": n, "character": ids[0]}
				broke["streak"] = n
			var fastest: Array = e["fastest"]
			var t := snappedf(seconds, 0.1)
			var rank := fastest.size()
			for i in fastest.size():
				if t < float(fastest[i]["time"]):
					rank = i
					break
			if rank < FASTEST_KEEP:
				fastest.insert(rank, {"time": t, "character": ids[0]})
				e["fastest"] = fastest.slice(0, FASTEST_KEEP)
				broke["fastest"] = rank + 1
		else:
			GameState.vs_cpu_streak[lvl] = 0
	GameState._save_json(GameState._leaderboard_file, d)
	return broke


## TOP FIGHTERS rows, most wins first (then fewest fights, then name):
## [{"character": index or -1, "name", "wins", "fights"}]. Comedians who
## have left the roster still show, by their id.
static func top_fighters(d: Dictionary) -> Array:
	var rows := []
	for cid in d["fighters"]:
		var f: Dictionary = d["fighters"][cid]
		var idx := character_index(cid)
		rows.append({"character": idx, "name": display_name(cid),
				"wins": int(f.get("wins", 0)), "fights": int(f.get("fights", 0))})
	rows.sort_custom(func(a, b):
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		if a["fights"] != b["fights"]:
			return a["fights"] < b["fights"]
		return a["name"] < b["name"])
	return rows


static func character_id(idx: int) -> String:
	var c := GameState.character_data(idx)
	return String(c.get("CharacterId", "character-%d" % idx))


static func character_index(cid: String) -> int:
	for i in GameState.characters.size():
		if String(GameState.characters[i].get("CharacterId", "")) == cid:
			return i
	return -1


static func display_name(cid: String) -> String:
	var idx := character_index(cid)
	if idx < 0:
		return cid.replace("-", " ").to_upper()
	return String(GameState.character_data(idx).get("CharacterName", cid)).to_upper()


static func head(cid_or_idx) -> Texture2D:
	var idx: int = cid_or_idx if cid_or_idx is int else character_index(String(cid_or_idx))
	# Already a full res:// path: GameState resolves it when the roster loads.
	return CharacterFactory.head_texture(String(GameState.character_data(idx).get("HeadSpritePath", "")))


## 42.3 -> "0:42.3"
static func format_time(seconds: float) -> String:
	var m := int(seconds) / 60
	return "%d:%04.1f" % [m, seconds - m * 60]
