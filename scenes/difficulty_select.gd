extends MenuScreen
## CPU level for each CPU side: one row in 1P vs CPU, two in CPU vs CPU (so a
## HARD vs BEGINNER exhibition is possible). Up/down picks the row, left/right
## changes the level, PUNCH/START goes on to fighter select, KICK goes back.
## Starts on the levels picked last time.

const DESC := [
	"SLOW TO REACT, RARELY BLOCKS. GOOD FOR A FIRST FIGHT.",
	"USES EVERY MOVE AND BLOCKS. A FAIR FIGHT.",
	"FAST, BLOCKS, COUNTERS AND PUNISHES. GOOD LUCK.",
]
const ROW_Y := 130.0
const ROW_GAP := 44.0

## Which sides have a row: [side index, caption].
var _rows: Array = []
var _row := 0
var _values: Array[int] = []
var _labels: Array[Label] = []
var _desc: Label


func _ready() -> void:
	build_backdrop()
	add_title("CPU LEVEL", 40, 18)
	if GameState.setup_mode() == GameState.Mode.CVC:
		_rows = [[0, "LEFT CPU"], [1, "RIGHT CPU"]]
	else:
		_rows = [[1, "CPU"]]
	for i in _rows.size():
		var side: int = _rows[i][0]
		_values.append(GameState.last_difficulty[side])
		var l := make_label("", 14)
		l.position = Vector2(0, ROW_Y + i * ROW_GAP)
		MenuScreen.size_later(l, Vector2(640, 20))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
		_labels.append(l)
	_desc = add_title("", 250, 8, INK)
	add_hint("STICK: CHOOSE    PUNCH: OK    KICK: BACK")
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	if not input_ready():
		return
	for p in [1, 2]:
		if just(p, "up") and _rows.size() > 1:
			_row = wrapi(_row - 1, 0, _rows.size())
			_click()
		elif just(p, "down") and _rows.size() > 1:
			_row = wrapi(_row + 1, 0, _rows.size())
			_click()
		elif just(p, "left"):
			_values[_row] = wrapi(_values[_row] - 1, 0, 3)
			_click()
		elif just(p, "right"):
			_values[_row] = wrapi(_values[_row] + 1, 0, 3)
			_click()
		elif confirm(p):
			GameState.play_sfx("click")
			for i in _rows.size():
				GameState.set_difficulty(_rows[i][0], _values[i])
			go(GameState.SCENE_FIGHTER_SELECT)
			return
		elif just(p, "kick"):
			go(GameState.SCENE_MODE)
			return


func _click() -> void:
	GameState.play_sfx("click")
	_refresh()


func _refresh() -> void:
	for i in _rows.size():
		var on := i == _row
		var name: String = GameState.DIFFICULTY_NAMES[_values[i]]
		_labels[i].text = "%s   %s %s %s" % [_rows[i][1], "<" if on else " ", name, ">" if on else " "]
		_labels[i].modulate = GOLD if on else DIM
	_desc.text = DESC[_values[_row]]
