class_name FighterController
extends RefCounted
## What a Battler reads instead of the Input singleton, so a human and the CPU
## drive a fighter through exactly the same buttons — the CPU can never do
## something a player can't. Actions: "left", "right", "down", "punch", "kick",
## "throw", "swing", "block".
##
## This base class presses nothing (a fighter with no controller stands still).

## Called once per physics frame by the fight scene for BOTH fighters, before
## either of them moves — so each side decides from the same moment and neither
## gets to react to the other's move a frame early. Runs while stunned too: a
## CPU's timers must keep going, and a human's hands don't stop either.
func tick(_delta: float, _me: Battler) -> void:
	pass


func axis() -> float:
	return 0.0


func pressed(_action: String) -> bool:
	return false


func just_pressed(_action: String) -> bool:
	return false


func just_released(_action: String) -> bool:
	return false


## A human at P1 or P2's controls: reads the "p1_*"/"p2_*" input actions.
class Human:
	extends FighterController

	var _prefix := ""

	func _init(player: int) -> void:
		_prefix = "p%d_" % player

	func axis() -> float:
		return Input.get_axis(_prefix + "left", _prefix + "right")

	func pressed(action: String) -> bool:
		return Input.is_action_pressed(_prefix + action)

	func just_pressed(action: String) -> bool:
		return Input.is_action_just_pressed(_prefix + action)

	func just_released(action: String) -> bool:
		return Input.is_action_just_released(_prefix + action)
