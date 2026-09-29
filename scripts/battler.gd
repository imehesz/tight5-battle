class_name Battler
extends Fighter
## A 1v1 fighter: Tight 5 FIGHT!'s Player, with its moves and numbers kept
## as they are, but driven by a FighterController (a human at P1/P2's controls
## or the CPU) and carrying its own loadout. Both fighters have every move —
## punch, kick, the chargeable weapon swing and the beer bottles.

signal swing_ready_changed(ready: bool)
## Bottles in hand, and seconds left on the refill (0 when not refilling).
signal bottles_changed(count: int, cooldown_left: float)

## Baseline walk speed.
const BASE_SPEED := 140.0

## Melee swing: an overhead hit with double the punch/kick reach, gated by a
## cooldown (punch/kick have none). Damage is kick +15%. During the swing
## SwingSwoosh draws the weapon + arc; between swings the weapon rides on the
## fighter's back (see CARRY_* below). Which weapon is pure cosmetics — these
## numbers are the same for the mic stand and the chainsaw alike.
const SWING_DAMAGE := KICK_DAMAGE * 1.15
const SWING_COOLDOWN := 1.5
const SWING_TIME := 0.25
## CHARGED SWING. The swing fires on RELEASE, not press: holding the button
## freezes the weapon overhead at frame one of the sweep, and letting go drops
## it. A tap therefore still swings immediately. Hold past CHARGE_TIME and the
## same swing lands for CHARGE_MULT damage and CHARGE_KNOCKBACK times the
## normal recoil distance. A charge can only be STARTED off cooldown.
const CHARGE_TIME := 1.0
const CHARGE_MULT := 1.5
const CHARGE_KNOCKBACK := 4.0
## Safety valve: the swing goes off by itself if the release never arrives.
const CHARGE_MAX := 2.5
## Punch hitbox reaches ~29px from center (18 + 22/2); this box ends at ~58.
const SWING_BOX_SIZE := Vector2(48, 20)
const SWING_BOX_X := 34.0

## BEER BOTTLES (the one rule changed from T5F): every fighter starts each
## round with a full hand. Throwing the last one starts the refill, and when
## it runs out the whole hand comes back at once — no partial refills.
const BOTTLES_MAX := 3
const BOTTLE_COOLDOWN := 10.0
const THROW_LOCK := 0.35
const THROW_SPEED := 320.0

const CARRY_POS := Vector2(-5, -26)  # sprite center, x mirrors with facing
const CARRY_TILT := 0.4              # radians off vertical, toward the back
const CARRY_LEN := 47.6              # full weapon height in local px
const STRAP_COLOR := Color(0.42, 0.26, 0.14)
const STRAP_WIDTH := 2.0
const STRAP_TOP := Vector2(-5, 4)
const STRAP_BOTTOM := Vector2(3, 16)
const STRAP_DUCK_TOP := Vector2(-5, 3)
const STRAP_DUCK_BOTTOM := Vector2(4, 11)

var controller := FighterController.new()
## False while the announcer talks and after a round is decided: the fighter
## stands (or lies) still whatever the buttons say.
var input_enabled := false
## Loadout — set before add_child.
var weapon := Weapons.DEFAULT
var decor := Decorators.NONE

var bottles := BOTTLES_MAX
var bottle_cooldown := 0.0

var _throw_lock := 0.0
var _swing_lock := 0.0
var _swing_cooldown := 0.0
var _swing_box: Area2D
var _charging := false
var _charge_t := 0.0
var _charge_swoosh: SwingSwoosh
var _carried_weapon: Sprite2D
var _chest_strap: Line2D
var _chest_decor: Sprite2D


func _init() -> void:
	move_speed = BASE_SPEED


## Which side of the fight this is (1 or 2). Each side's hurtbox sits on its
## own collision layer and its attacks only look at the other's, so a fighter
## can never hit itself with a fist, a swing or its own bottle.
func set_side(side: int) -> void:
	hurt_layer = 2 if side == 1 else 4
	attack_mask = 4 if side == 1 else 2


func _ready() -> void:
	super()
	_build_swing_box()
	_build_carried_weapon()
	_build_chest_strap()
	_build_chest_decor()
	# Place head, weapon, strap and decal NOW. They're positioned in _process,
	# which first runs a frame later — and the frame drawn in between showed a
	# full-size head sitting down at the feet (a flash on every new preview in
	# fighter select, and on every round start).
	_process(0.0)


func set_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		_cancel_charge()


func swing_ready() -> bool:
	return _swing_cooldown <= 0.0


## Holding a weapon overhead right now (what a HARD CPU backs away from).
func is_charging() -> bool:
	return _charging


## A punch, kick or swing is under way — what a CPU decides to block.
func is_attacking() -> bool:
	return state == FState.PUNCH or state == FState.KICK or _swing_lock > 0.0


## The between-swings weapon on the back. Child index 0 keeps it behind the
## body/head sprites without z_index.
func _build_carried_weapon() -> void:
	var tex := Weapons.texture(weapon)
	if tex == null:
		return
	_carried_weapon = Sprite2D.new()
	_carried_weapon.texture = tex
	var s := CARRY_LEN / tex.get_height()
	_carried_weapon.scale = Vector2(s, s)
	_carried_weapon.position = CARRY_POS
	add_child(_carried_weapon)
	move_child(_carried_weapon, 0)


## The strap sits in front of the body sprite (the weapon behind it), so it
## reads as worn rather than floating.
func _build_chest_strap() -> void:
	_chest_strap = Line2D.new()
	_chest_strap.width = STRAP_WIDTH
	_chest_strap.default_color = STRAP_COLOR
	_chest_strap.begin_cap_mode = Line2D.LINE_CAP_NONE
	_chest_strap.end_cap_mode = Line2D.LINE_CAP_NONE
	_chest_strap.antialiased = false
	add_child(_chest_strap)
	move_child(_chest_strap, body_sprite.get_index() + 1)


## The chest decoration (decal) from the loadout. Wearing one hides the strap,
## so the art is never crossed out by it. Nothing is built for NONE.
func _build_chest_decor() -> void:
	var tex := Decorators.texture(decor)
	if tex == null:
		return
	_chest_decor = Sprite2D.new()
	_chest_decor.texture = tex
	_chest_decor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_chest_decor)
	move_child(_chest_decor, _chest_strap.get_index())


func _process(delta: float) -> void:
	super(delta)
	if _carried_weapon:
		# Hidden while the SwingSwoosh draws its own copy, and on defeat.
		_carried_weapon.visible = _swing_lock <= 0.0 and not _charging \
				and state != FState.DEAD
		_carried_weapon.position.x = CARRY_POS.x * facing
		_carried_weapon.flip_h = facing < 0
		_carried_weapon.rotation = -CARRY_TILT * facing + Weapons.carry_spin(weapon)
	if _chest_strap:
		_chest_strap.visible = state != FState.DEAD and _chest_decor == null
		if _chest_strap.visible:
			var ducking := body_sprite.animation == "duck"
			var top := STRAP_DUCK_TOP if ducking else STRAP_TOP
			var bottom := STRAP_DUCK_BOTTOM if ducking else STRAP_BOTTOM
			var neck := CharacterFactory.head_offset(body_sprite.animation)
			_chest_strap.points = PackedVector2Array([
				Vector2((neck.x + top.x) * facing, neck.y + top.y),
				Vector2((neck.x + bottom.x) * facing, neck.y + bottom.y),
			])
	if _chest_decor:
		_chest_decor.visible = state != FState.DEAD
		if _chest_decor.visible:
			var anim := body_sprite.animation
			_chest_decor.position = Decorators.chest_offset(anim, facing)
			var ds := Decorators.chest_scale(decor, anim)
			_chest_decor.scale = Vector2(ds, ds)
			_chest_decor.flip_h = facing < 0


## Separate hitbox for the melee swing so the shared punch/kick hitbox
## (and everyone's hurtboxes) keep their tuned sizes untouched.
func _build_swing_box() -> void:
	_swing_box = Area2D.new()
	_swing_box.collision_layer = 0
	_swing_box.collision_mask = attack_mask
	_swing_box.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SWING_BOX_SIZE
	shape.shape = rect
	_swing_box.add_child(shape)
	_swing_box.position = Vector2(SWING_BOX_X, -30)
	_swing_box.area_entered.connect(_on_hitbox_area_entered)
	add_child(_swing_box)


func take_hit(damage: float, from_x: float, knockback := 1.0,
		unblockable := false) -> void:
	# Ignored, or stopped by the guard: nothing we're doing gets interrupted.
	if state == FState.DEAD or is_invulnerable() or blocks(from_x, unblockable):
		super(damage, from_x, knockback, unblockable)
		return
	# Getting hit interrupts a swing in progress (the cooldown still runs).
	if _swing_lock > 0.0:
		_swing_lock = 0.0
		_swing_box.set_deferred("monitoring", false)
	# A charge is broken outright — but no swing happened, so no cooldown.
	_cancel_charge()
	super(damage, from_x, knockback, unblockable)


func _die() -> void:
	_cancel_charge()
	super()


func _physics_process(delta: float) -> void:
	_tick_bottles(delta)
	if state == FState.DEAD:
		return
	if _swing_cooldown > 0.0:
		_swing_cooldown -= delta
		if _swing_cooldown <= 0.0:
			swing_ready_changed.emit(true)
	if tick_status(delta):
		return
	if state == FState.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return
	if _throw_lock > 0.0:
		_throw_lock -= delta
		velocity.x = 0
		move_and_slide()
		return
	if _swing_lock > 0.0:
		_swing_lock -= delta
		if _swing_lock <= 0.0:
			_swing_box.set_deferred("monitoring", false)
		velocity.x = 0
		move_and_slide()
		return

	# Winding up: rooted and committed — no walking, no turning, no punching
	# out of it. The only way out is the swing itself.
	if _charging:
		var was_ready := _charge_t >= CHARGE_TIME
		_charge_t += delta
		if not was_ready and _charge_t >= CHARGE_TIME \
				and is_instance_valid(_charge_swoosh):
			_charge_swoosh.mark_charged()
		if controller.just_released("swing") or not controller.pressed("swing") \
				or _charge_t >= CHARGE_MAX:
			_release_swing()
		velocity.x = 0
		move_and_slide()
		return

	face_opponent()
	if not input_enabled:
		set_blocking(false)
		set_ducking(false)
		apply_locomotion(0.0)
		return

	# Guard wins over everything else: while it's up you can't move or attack.
	set_blocking(controller.pressed("block"))
	if state == FState.BLOCK:
		velocity.x = 0
		move_and_slide()
		return

	set_ducking(controller.pressed("down"))
	if state == FState.DUCK:
		return

	if controller.just_pressed("throw") and _try_throw():
		return
	if controller.just_pressed("swing") and _begin_charge():
		return
	if controller.just_pressed("punch"):
		try_attack(FState.PUNCH)
	elif controller.just_pressed("kick"):
		try_attack(FState.KICK)

	apply_locomotion(controller.axis())


func _tick_bottles(delta: float) -> void:
	if bottle_cooldown <= 0.0:
		return
	bottle_cooldown = maxf(bottle_cooldown - delta, 0.0)
	if bottle_cooldown <= 0.0:
		bottles = BOTTLES_MAX
	bottles_changed.emit(bottles, bottle_cooldown)


## Throw a beer bottle straight forward. It flies at the height that meets a
## standing opponent but clears a ducking one (Tight 5 FIGHT!'s boss fastball
## rule), so ducking is the answer to it. Returns true if one was thrown.
func _try_throw() -> bool:
	if not can_act() or bottles <= 0:
		return false
	bottles -= 1
	if bottles == 0:
		bottle_cooldown = BOTTLE_COOLDOWN
	bottles_changed.emit(bottles, bottle_cooldown)
	_throw_lock = THROW_LOCK
	velocity.x = 0
	_play("punch")  # reuse the wind-up pose; state stays IDLE so no fist hitbox
	GameState.play_sfx("throw")
	var b := Projectile.new()
	b.collision_mask_bits = attack_mask
	b.position = Vector2(position.x + facing * 22.0 * scale.x, _bottle_y())
	b.velocity = Vector2(facing * THROW_SPEED, 0.0)
	get_parent().add_child(b)
	return true


## Parent-space height midway between the standing and ducking hurtbox tops.
## Both fighters share a scale, so our own does for the target's.
func _bottle_y() -> float:
	var s := scale.y
	var stand_top := position.y + Fighter.STAND_BOX.position.y * s
	var duck_top := position.y + Fighter.DUCK_BOX.position.y * s
	return (stand_top + duck_top) * 0.5


## Press the swing button off cooldown: the weapon comes up overhead and STAYS
## there until the button is let go. Nothing is committed here — no cooldown,
## no hitbox, no sound — because the swing has not happened yet.
func _begin_charge() -> bool:
	if not can_act() or _swing_cooldown > 0.0:
		return false
	_charging = true
	_charge_t = 0.0
	velocity.x = 0
	# Paused on frame 0 of the punch row — arms back, the wind-up.
	_play("punch")
	body_sprite.frame = 0
	body_sprite.pause()
	_charge_swoosh = SwingSwoosh.new()
	_charge_swoosh.facing = facing
	_charge_swoosh.weapon = weapon
	_charge_swoosh.duration = SWING_TIME
	_charge_swoosh.charging = true
	add_child(_charge_swoosh)
	return true


## Button released (or CHARGE_MAX reached): the held weapon drops into its
## sweep. Held past CHARGE_TIME, it lands for CHARGE_MULT damage.
func _release_swing() -> void:
	var charged := _charge_t >= CHARGE_TIME
	var held := _charge_swoosh
	_charging = false
	_charge_t = 0.0
	_charge_swoosh = null
	if _try_swing(charged, held):
		return
	if is_instance_valid(held):
		held.queue_free()


## Give up a wind-up with no swing: the raised weapon goes away.
func _cancel_charge() -> void:
	if not _charging:
		return
	_charging = false
	_charge_t = 0.0
	if is_instance_valid(_charge_swoosh):
		_charge_swoosh.queue_free()
	_charge_swoosh = null


## Overhead weapon swing, released from a charge. Returns true if it started.
func _try_swing(charged: bool, held: SwingSwoosh = null) -> bool:
	if not can_act() or _swing_cooldown > 0.0:
		return false
	_swing_lock = SWING_TIME
	_swing_cooldown = SWING_COOLDOWN
	attack_count += 1
	swing_ready_changed.emit(false)
	velocity.x = 0
	_victims.clear()
	_attack_damage = SWING_DAMAGE * damage_scale
	# Skid distance goes with the SQUARE of launch speed: √ of the multiplier.
	_attack_knockback = sqrt(CHARGE_KNOCKBACK) if charged else 1.0
	# A charged swing breaks a guard; a tapped one is blocked like a fist.
	_attack_unblockable = charged
	if charged:
		_attack_damage *= CHARGE_MULT
	_swing_box.position = Vector2(SWING_BOX_X * facing, -30)
	_swing_box.monitoring = true
	_play("punch")
	GameState.play_sfx("swing")
	if is_instance_valid(held):
		held.release()
		return true
	var sw := SwingSwoosh.new()
	sw.facing = facing
	sw.weapon = weapon
	sw.duration = SWING_TIME
	add_child(sw)
	return true
