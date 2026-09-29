class_name CpuController
extends FighterController
## The CPU opponent. It "presses" the same buttons a human does (see
## FighterController), so it can't do anything a player can't, and difficulty
## never touches damage or health — a HARD CPU hits exactly as hard as you.
##
## What difficulty changes is how well it plays:
##   - reaction: how often it re-reads the fight (and so how late it responds)
##   - attack gap: how long it waits between attacks
##   - which moves it reaches for (swing/charged swing/bottles)
##   - how often it ducks an incoming bottle
##   - spacing: hanging back at swing range / backing off after attacking
##   - block: the odds it gets its guard up against each punch, kick or
##     swing you throw; guard: the odds it keeps its guard up while waiting
##     at close range; counter: the odds it punches back the instant a block
##     ends — a blocked attacker is still finishing their move, so a quick
##     counter lands (that's the reward for blocking, and the answer to mashing)
##   - punish: HARD backs out of a charged swing and rushes in while your
##     swing is cooling down or your bottles are empty
## Every choice is rolled, so no level plays the same fight twice.

const LEVELS := [
	{   # BEGINNER — walks straight in, mostly punches and kicks, slow to react
		"react": 0.5, "gap": [0.9, 1.6], "duck": 0.1,
		"throw_far": 0.04, "swing_mid": 0.15, "charge": 0.0,
		"weights": {"punch": 0.55, "kick": 0.35, "swing": 0.1},
		"hover": 0.0, "backoff": 0.0, "punish": false, "retreat": false,
		"block": 0.05, "guard": 0.0, "counter": 0.0, "block_hold": 0.4,
	},
	{   # NORMAL — uses everything, keeps a little distance, uncharged swings
		"react": 0.3, "gap": [0.45, 0.9], "duck": 0.45,
		"throw_far": 0.14, "swing_mid": 0.35, "charge": 0.0,
		"weights": {"punch": 0.4, "kick": 0.35, "swing": 0.25},
		"hover": 0.25, "backoff": 0.15, "punish": false, "retreat": false,
		"block": 0.55, "guard": 0.4, "counter": 0.7, "block_hold": 0.3,
	},
	{   # HARD — fast, spaces well, charges swings, punishes your cooldowns
		"react": 0.15, "gap": [0.2, 0.5], "duck": 0.8,
		"throw_far": 0.25, "swing_mid": 0.5, "charge": 0.45,
		"weights": {"punch": 0.35, "kick": 0.35, "swing": 0.3},
		"hover": 0.2, "backoff": 0.3, "punish": true, "retreat": true,
		"block": 0.6, "guard": 0.45, "counter": 0.85, "block_hold": 0.25,
	},
]
## A tapped button is held this long (a swing fires on release).
const TAP := 0.05

var level := 1
var _p: Dictionary
var _held := {}      # action -> seconds left to hold
var _just := {}      # actions pressed this tick
var _released := {}  # actions let go this tick
var _axis := 0.0
var _think := 0.0
var _attack_wait := 0.0
## Bottles already judged (instance id -> true), so each one gets ONE roll.
var _seen_bottles := {}
## The opponent's attack_count last tick: each NEW attack gets one block roll.
var _opp_attacks := -1
var _was_blockstun := false


func _init(difficulty := 1) -> void:
	level = clampi(difficulty, 0, LEVELS.size() - 1)
	_p = LEVELS[level]
	_attack_wait = randf_range(0.3, 0.8)


func axis() -> float:
	return 0.0 if _held.has("down") else _axis


func pressed(action: String) -> bool:
	return _held.has(action)


func just_pressed(action: String) -> bool:
	return _just.has(action)


func just_released(action: String) -> bool:
	return _released.has(action)


func tick(delta: float, me: Battler) -> void:
	_just.clear()
	_released.clear()
	for a in _held.keys():
		_held[a] -= delta
		if _held[a] <= 0.0:
			_held.erase(a)
			_released[a] = true
	_attack_wait -= delta
	_think -= delta
	var opp := me.opponent as Battler
	if not is_instance_valid(opp) or opp.state == Fighter.FState.DEAD:
		_axis = 0.0
		return
	# Hit or knocked down: whatever we were holding is gone (a hit breaks a
	# charge), except a guard we're buffering for the moment we recover.
	var reeling := me.state == Fighter.FState.HIT or me.state == Fighter.FState.KNOCKDOWN
	if reeling:
		for a in _held.keys():
			if a != "block":
				_held.erase(a)
				_released[a] = true
		_axis = 0.0
	_watch_attacks(me, opp)
	if reeling:
		return
	_watch_bottles(me)
	_counter_after_block(me)
	if _held.has("down") or _held.has("swing") or _held.has("block"):
		return  # committed to a duck, a wind-up or a guard
	if _think > 0.0:
		return
	_think = _p["react"] * randf_range(0.7, 1.3)
	_decide(me, opp)


func _press(action: String, hold := TAP) -> void:
	_just[action] = true
	_held[action] = hold


## Reach, in parent px, at which a punch/kick (and the swing) can land: the
## hitbox's far edge plus the target's hurtbox half-width, at our scale.
## A little under the true figure so the CPU doesn't swing at air.
func _punch_reach(me: Battler) -> float:
	return (18.0 + 11.0 + 8.0) * me.scale.x * 0.9


func _swing_reach(me: Battler) -> float:
	return (Battler.SWING_BOX_X + Battler.SWING_BOX_SIZE.x / 2.0 + 8.0) * me.scale.x * 0.9


func _decide(me: Battler, opp: Battler) -> void:
	var dx := opp.position.x - me.position.x
	var dist := absf(dx)
	var toward := signf(dx) if dx != 0.0 else float(me.facing)
	var punch_r := _punch_reach(me)
	var swing_r := _swing_reach(me)
	# Opponent is exposed: swing cooling down or out of bottles.
	var punish: bool = _p["punish"] and (not opp.swing_ready() or opp.bottles == 0)

	# HARD: get out from under a charged swing.
	if _p["retreat"] and opp.is_charging() and dist < swing_r + 30.0:
		_axis = -toward
		return

	if dist > swing_r:
		if me.bottles > 0 and randf() < _p["throw_far"]:
			_axis = 0.0
			_press("throw")
			return
		_axis = toward
		return

	if dist > punch_r:
		if me.swing_ready() and _attack_wait <= 0.0 and randf() < _p["swing_mid"]:
			_axis = 0.0
			# A charge only pays with room to hold it: not up in their face.
			if randf() < _p["charge"] and dist > punch_r + 30.0:
				_press("swing", Battler.CHARGE_TIME + 0.1)
			else:
				_press("swing")
			_attack_wait = randf_range(_p["gap"][0], _p["gap"][1])
			return
		if not punish and randf() < _p["hover"]:
			_axis = 0.0  # hang back at swing range for a beat
		else:
			_axis = toward
		return

	# In punching range.
	if _attack_wait <= 0.0:
		_axis = 0.0
		_press(_pick_attack(me))
		var gap := randf_range(_p["gap"][0], _p["gap"][1])
		_attack_wait = gap * (0.6 if punish else 1.0)
		return
	# Waiting on the next attack, up close: guard up, back off, or stand.
	if randf() < _p["guard"]:
		_axis = 0.0
		_held["block"] = _p["block_hold"]
		return
	_axis = -toward if randf() < _p["backoff"] else 0.0


func _pick_attack(me: Battler) -> String:
	var w: Dictionary = _p["weights"].duplicate()
	if not me.swing_ready():
		w.erase("swing")
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "punch"


## Block the opponent's punches, kicks and swings — or not. Judged the moment
## an attack starts (a punch lands 0.1s later, faster than any reaction time,
## so the odds stand in for reading the opponent). A HARD CPU swings its own
## attack in the moment the guard comes down.
func _watch_attacks(me: Battler, opp: Battler) -> void:
	var started := _opp_attacks >= 0 and opp.attack_count != _opp_attacks
	_opp_attacks = opp.attack_count
	if not started or _held.has("block") or _held.has("swing"):
		return
	if absf(opp.position.x - me.position.x) > _swing_reach(me) + 20.0:
		return  # swinging at air
	if me.state == Fighter.FState.KNOCKDOWN or randf() >= _p["block"]:
		return
	# Still reeling from the last hit? Hold the guard through the stun so it
	# comes up the moment we recover (exactly what a human holding BLOCK gets).
	var hold: float = _p["block_hold"]
	if me.state == Fighter.FState.HIT:
		hold += 0.35
	_held.erase("down")
	_held["block"] = maxf(float(_held.get("block", 0.0)), hold)
	_axis = 0.0


## The moment a blocked hit's guard-stun wears off, maybe drop the guard and
## hit back while the attacker is still finishing their move.
func _counter_after_block(me: Battler) -> void:
	var bs := me.in_blockstun()
	var ended := _was_blockstun and not bs
	_was_blockstun = bs
	if not ended or randf() >= _p["counter"]:
		return
	_held.erase("block")
	_released["block"] = true
	_press(_pick_attack(me))
	_attack_wait = randf_range(_p["gap"][0], _p["gap"][1])
	_think = _p["react"]


## Duck incoming bottles — or not. Each bottle is judged once, when it gets
## close enough that our reaction time only just leaves room to get down.
func _watch_bottles(me: Battler) -> void:
	for b in me.get_tree().get_nodes_in_group("projectiles"):
		var p := b as Projectile
		if p == null or p.collision_mask_bits != me.hurt_layer:
			continue  # our own bottle
		var id := p.get_instance_id()
		if _seen_bottles.has(id):
			continue
		var dx := me.position.x - p.position.x
		if signf(dx) != signf(p.velocity.x):
			continue  # already past us
		var speed := maxf(absf(p.velocity.x), 1.0)
		if absf(dx) > speed * (_p["react"] + 0.25) + 60.0:
			continue  # not close enough to have noticed yet
		_seen_bottles[id] = true
		if randf() < _p["duck"] and me.can_act():
			_held.erase("swing")
			_held["down"] = absf(dx) / speed + 0.2
			_axis = 0.0
