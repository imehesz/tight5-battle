class_name Fighter
extends CharacterBody2D
## Base combatant, ported from Tight 5 FIGHT!: modular body + socketed head,
## simple rectangular hurtbox/hitbox combat, ducking, hit reactions and defeat.
## The one mechanical change for the 1v1 game: a fighter with an `opponent`
## always turns to face them (walking away is a retreat, not a turn-around).

signal died(fighter: Fighter)
signal health_changed(current: float, maximum: float)

enum FState { IDLE, WALK, PUNCH, KICK, DUCK, HIT, DEAD, BLOCK, KNOCKDOWN }

const PUNCH_DAMAGE := 10.0
const KICK_DAMAGE := 16.0
## Combat juice tuning: longer hitstop on a killing blow, the white-blink
## flash on any hit, and the shake sizes for "player hurt" vs "somebody KO'd".
const KILL_HITSTOP := 0.09
## Launch speed of the recoil skid on any hit. The HIT state drags it to a
## stop at 300px/s², well inside the hit animation, so this is a real distance:
## ~6px. Attacks can ask for more through take_hit()'s knockback argument.
const KNOCKBACK := 60.0
const FLASH_COLOR := Color(6.0, 6.0, 6.0)
const FLASH_FADE := 0.12
const SHAKE_PLAYER_HURT := 3.0
const SHAKE_KO := 4.0
## BLOCK (Tight 5 BATTLE): holding guard stops punches, kicks and tapped
## swings from the front — no damage, a short guard-stun and a small push back.
## Unblockable hits (a CHARGED swing, bottles) go straight through the guard.
const BLOCKSTUN := 0.15
const BLOCK_PUSH := 1.5
const BLOCK_TEXT := Color(0.6, 0.85, 1.0)
## COMBO BREAKER: Tight 5 FIGHT!'s hit-stun (0.33s) outlasts a punch (0.3s), so
## a mashed punch lands before the victim recovers — one lucky jab could chain
## to a KO. The COMBO_MAX-th hit of an unbroken chain knocks the victim down
## instead: they drop, can't be hit while down, and get up with a moment's
## protection. A hit within CHAIN_GRACE of recovering still counts as the chain.
const COMBO_MAX := 3
const CHAIN_GRACE := 0.15
const KNOCKDOWN_TIME := 0.7
const GETUP_INVULN := 0.35
const KNOCKDOWN_PUSH := 2.0
const STAND_BOX := Rect2(-8, -44, 16, 44)
const DUCK_BOX := Rect2(-8, -26, 16, 26)
## Whole-fighter scale (boxes scale with it) and extra bobblehead scale for
## the head sprite — heads are real people's pixelated photos, go big.
## Head textures can be any size (200x200 photos, 16x16 pixel art...): they
## are normalized so every head displays as if it were 16px * HEAD_SCALE.
const BODY_SCALE := 1.4
const HEAD_SCALE := 2.4
const HEAD_BASE_PX := 16.0

## Roster name from characters.json ("CharacterName").
var char_name := ""
## Roster id from characters.json ("CharacterId") — the permanent identity.
var char_id := ""
var body_type := "M"
var skin_color := CharacterFactory.DEFAULT_SKIN
## Index into CharacterFactory.OUTFITS; set from the loadout before add_child.
var outfit := CharacterFactory.OUTFIT_BAKED
var head_path := ""
## Optional per-character head nudges (JSON "HeadOffsetX"/"HeadOffsetY", in
## body pixels). Positive Y moves the head DOWN — use it when long hair puts
## the chin well above the image bottom, so the chin still meets the neck.
## Positive X moves the head toward the facing direction (mirrors on flip).
## head_scale (JSON "HeadScale") is an extra zoom on top of normalization —
## bump it above 1.0 when big hair fills the crop and shrinks the face.
var head_offset_x := 0.0
var head_offset_y := 0.0
var head_scale := 1.0
## JSON "inWheelchair": legs are erased from the body frames and a chair
## sprite (behind the body) rides along. Kick plays the punch animation.
var in_wheelchair := false
var max_health := 100.0
var health := 100.0
var move_speed := 130.0
## Extra whole-fighter size multiplier on top of BODY_SCALE (boxes scale with
## it). Venues bump this to make the comedians roomier; set before add_child.
var size_scale := 1.0
var damage_scale := 1.0
var facing := 1
## Direction (+1/-1) the last hit pushed this fighter — AWAY from the attacker.
var last_hit_dir := 1.0
## The other fighter. While set, facing always points at them.
var opponent: Fighter
var state: FState = FState.IDLE
var hurt_layer := 2   # collision layer bit value of our hurtbox
var attack_mask := 4  # hurtbox layers our attacks connect with

var body_sprite: AnimatedSprite2D
var head_sprite: Sprite2D
var wheel_sprite: Sprite2D
var _wheelie_tex: Array[Texture2D] = []
var hurtbox: Area2D
var hitbox: Area2D
var _hurt_shape: CollisionShape2D
var _attack_damage := 0.0
## Multiplier on the victim's recoil speed for the attack currently landing,
## alongside _attack_damage. 1.0 for everything except the charged swing.
var _attack_knockback := 1.0
## True for the attack landing now if a guard can't stop it (charged swing).
var _attack_unblockable := false
var _victims := {}
## Attacks started so far. Counted rather than watched as a state, because a
## masher starts the next punch on the very frame the last one ends — a
## "was attacking / is attacking" check would never see the gap.
var attack_count := 0
var _blockstun := 0.0
var _down_t := 0.0
var _invuln_t := 0.0
var _chain_hits := 0
var _since_recover := 99.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health = max_health
	scale = Vector2(BODY_SCALE, BODY_SCALE) * size_scale
	_build_visuals()
	_build_boxes()
	_play("idle")


func _build_visuals() -> void:
	# Chair first, so it draws behind the body (seat back behind the torso).
	if in_wheelchair:
		_wheelie_tex = CharacterFactory.wheelie_textures()
	if not _wheelie_tex.is_empty():
		wheel_sprite = Sprite2D.new()
		wheel_sprite.texture = _wheelie_tex[0]
		var ws := CharacterFactory.WHEELIE_BASE_PX \
				/ maxf(wheel_sprite.texture.get_width(), 1.0)
		wheel_sprite.scale = Vector2(ws, ws)
		wheel_sprite.position = CharacterFactory.WHEELIE_POS
		add_child(wheel_sprite)

	body_sprite = AnimatedSprite2D.new()
	body_sprite.sprite_frames = CharacterFactory.body_frames(
			body_type, skin_color, outfit, in_wheelchair)
	body_sprite.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	body_sprite.animation_finished.connect(_on_animation_finished)
	body_sprite.frame_changed.connect(_on_frame_changed)
	add_child(body_sprite)

	head_sprite = Sprite2D.new()
	head_sprite.texture = CharacterFactory.head_texture(head_path)
	var s := HEAD_SCALE * head_scale \
			* (HEAD_BASE_PX / maxf(head_sprite.texture.get_width(), 1.0))
	head_sprite.scale = Vector2(s, s)
	add_child(head_sprite)


func _build_boxes() -> void:
	# Body shape only silences move_and_slide; it collides with nothing.
	var body_shape := CollisionShape2D.new()
	var brect := RectangleShape2D.new()
	brect.size = Vector2(12, 30)
	body_shape.shape = brect
	body_shape.position = Vector2(0, -15)
	collision_layer = 0
	collision_mask = 0
	add_child(body_shape)

	hurtbox = Area2D.new()
	hurtbox.collision_layer = hurt_layer
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.set_meta("fighter", self)
	_hurt_shape = CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = STAND_BOX.size
	_hurt_shape.shape = hrect
	_hurt_shape.position = STAND_BOX.get_center()
	hurtbox.add_child(_hurt_shape)
	add_child(hurtbox)

	hitbox = Area2D.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = attack_mask
	hitbox.monitoring = false
	var hshape := CollisionShape2D.new()
	var arect := RectangleShape2D.new()
	arect.size = Vector2(22, 14)
	hshape.shape = arect
	hitbox.add_child(hshape)
	hitbox.position = Vector2(18, -30)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	add_child(hitbox)


func _process(_delta: float) -> void:
	body_sprite.flip_h = facing < 0
	head_sprite.flip_h = facing < 0
	var neck := CharacterFactory.head_offset(body_sprite.animation)
	# Lift the head so it sits on the neck, minus a little overlap.
	var lift := head_sprite.texture.get_height() * head_sprite.scale.y / 2.0 - 4.0
	head_sprite.position = Vector2((neck.x + head_offset_x) * facing,
			neck.y - lift + head_offset_y)
	hitbox.position.x = 18 * facing
	if wheel_sprite:
		wheel_sprite.flip_h = facing < 0
		wheel_sprite.position.x = CharacterFactory.WHEELIE_POS.x * facing
		# Wheels roll with the walk cycle; parked on frame 1 otherwise.
		var wf := body_sprite.frame % 2 if state == FState.WALK else 0
		wheel_sprite.texture = _wheelie_tex[wf]


## Apply a character entry from characters.json. Call before add_child().
func configure(cfg: Dictionary) -> void:
	char_name = String(cfg.get("CharacterName", ""))
	char_id = String(cfg.get("CharacterId", ""))
	body_type = String(cfg.get("BodyType", "M"))
	skin_color = Color.from_string(String(cfg.get("SkinColor", "")),
			CharacterFactory.DEFAULT_SKIN)
	head_path = String(cfg.get("HeadSpritePath", ""))
	head_offset_x = float(cfg.get("HeadOffsetX", 0))
	head_offset_y = float(cfg.get("HeadOffsetY", 0))
	head_scale = maxf(float(cfg.get("HeadScale", 1.0)), 0.1)
	in_wheelchair = bool(cfg.get("inWheelchair", false))


# ---------------------------------------------------------------- actions
func can_act() -> bool:
	return state == FState.IDLE or state == FState.WALK


func try_attack(kind: FState) -> void:
	if not can_act():
		return
	state = kind
	velocity.x = 0
	attack_count += 1
	_victims.clear()
	_attack_damage = (PUNCH_DAMAGE if kind == FState.PUNCH else KICK_DAMAGE) * damage_scale
	# Fists never launch anyone further than normal — and this clears a charged
	# swing's boost, which would otherwise ride along on the next punch.
	_attack_knockback = 1.0
	_attack_unblockable = false
	_play("punch" if kind == FState.PUNCH else "kick")
	GameState.play_sfx("punch" if kind == FState.PUNCH else "kick")


func set_ducking(on: bool) -> void:
	if on and can_act():
		state = FState.DUCK
		velocity.x = 0
		_play("duck")
		_set_hurt_rect(DUCK_BOX)
	elif not on and state == FState.DUCK:
		state = FState.IDLE
		_play("idle")
		_set_hurt_rect(STAND_BOX)


func is_ducking() -> bool:
	return state == FState.DUCK


## Guard up while `on`. Guard-stun keeps it up until it runs out, whatever
## the button says.
func set_blocking(on: bool) -> void:
	if on and (can_act() or state == FState.BLOCK):
		if state != FState.BLOCK:
			state = FState.BLOCK
			velocity.x = 0
			_play("block")
			_set_hurt_rect(STAND_BOX)
	elif not on and state == FState.BLOCK and _blockstun <= 0.0:
		state = FState.IDLE
		_play("idle")


func is_blocking() -> bool:
	return state == FState.BLOCK


## Just stopped a hit and can't drop the guard yet.
func in_blockstun() -> bool:
	return _blockstun > 0.0


## Down on the floor, or still protected after getting up.
func is_invulnerable() -> bool:
	return state == FState.KNOCKDOWN or _invuln_t > 0.0


## Would a hit from `from_x` be stopped by the guard?
func blocks(from_x: float, unblockable := false) -> bool:
	if state != FState.BLOCK or unblockable:
		return false
	var dx := from_x - global_position.x
	return absf(dx) < 1.0 or signf(dx) == float(facing)


## Guard-stun, knockdown and get-up protection. Called every physics frame by
## the subclass; returns true while one of them has the fighter held.
func tick_status(delta: float) -> bool:
	_since_recover += delta
	if _invuln_t > 0.0:
		_invuln_t -= delta
		# Blink while protected, so both players can see the window.
		modulate.a = 0.45 if fmod(_invuln_t, 0.12) < 0.06 else 1.0
		if _invuln_t <= 0.0:
			modulate.a = 1.0
			hurtbox.set_deferred("collision_layer", hurt_layer)
	if state == FState.KNOCKDOWN:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		_down_t -= delta
		if _down_t <= 0.0:
			state = FState.IDLE
			_play("idle")
			_set_hurt_rect(STAND_BOX)
			_chain_hits = 0
			_since_recover = 0.0
			_invuln_t = GETUP_INVULN
		return true
	if _blockstun > 0.0:
		_blockstun -= delta
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return true
	return false


## Turn toward the opponent. Only between actions, so a punch or a swing
## already under way is never spun around mid-move.
func face_opponent() -> void:
	if not is_instance_valid(opponent) or not (can_act() or state == FState.BLOCK):
		return
	var dx := opponent.global_position.x - global_position.x
	if absf(dx) > 1.0:
		facing = 1 if dx > 0 else -1


## Shared walk/idle handling; subclasses feed a -1..1 direction each frame.
func apply_locomotion(dir: float) -> void:
	if not can_act():
		move_and_slide()
		return
	velocity.x = dir * move_speed
	if absf(dir) > 0.01:
		# No opponent to square up to: face the way you walk, as in T5F.
		if not is_instance_valid(opponent):
			facing = 1 if dir > 0 else -1
		state = FState.WALK
		_play("walk")
	else:
		state = FState.IDLE
		_play("idle")
	move_and_slide()


## `knockback` scales the recoil skid only — damage is already in `damage`.
## Defaulted so every plain caller keeps the stock shove and only the charged
## swing sends anyone further. `unblockable` hits go through a guard.
func take_hit(damage: float, from_x: float, knockback := 1.0,
		unblockable := false) -> void:
	if state == FState.DEAD or is_invulnerable():
		return
	last_hit_dir = signf(global_position.x - from_x)
	if last_hit_dir == 0.0:
		last_hit_dir = float(-facing)
	if blocks(from_x, unblockable):
		_on_blocked()
		return
	if state == FState.BLOCK:
		_float_text("GUARD BREAK!", Color(1.0, 0.45, 0.3))
	# Part of an unbroken chain? (still reeling, or only just recovered)
	if state == FState.HIT or _since_recover < CHAIN_GRACE:
		_chain_hits += 1
	else:
		_chain_hits = 1
	flash()
	if health - damage <= 0.0:
		GameState.hitstop(KILL_HITSTOP)
	else:
		GameState.hitstop()
	health = maxf(health - damage, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
		return
	if _chain_hits >= COMBO_MAX:
		_knockdown()
		return
	GameState.request_shake(SHAKE_PLAYER_HURT)
	state = FState.HIT
	_set_hurt_rect(STAND_BOX)
	hitbox.set_deferred("monitoring", false)
	velocity.x = last_hit_dir * KNOCKBACK * knockback
	_play("hit")
	GameState.play_sfx("hurt")


func _on_blocked() -> void:
	_blockstun = BLOCKSTUN
	velocity.x = last_hit_dir * KNOCKBACK * BLOCK_PUSH
	GameState.hitstop()
	GameState.play_sfx("click")
	_float_text("BLOCK", BLOCK_TEXT)


## The combo breaker: down on the floor, untouchable, then back up.
func _knockdown() -> void:
	state = FState.KNOCKDOWN
	_down_t = KNOCKDOWN_TIME
	_chain_hits = 0
	hurtbox.set_deferred("collision_layer", 0)
	hitbox.set_deferred("monitoring", false)
	velocity.x = last_hit_dir * KNOCKBACK * KNOCKDOWN_PUSH
	GameState.request_shake(SHAKE_KO)
	GameState.play_sfx("hurt")
	_play("defeated")
	_float_text("KNOCKDOWN!", Color(1.0, 0.85, 0.4))


func _float_text(text: String, color: Color) -> void:
	var top := global_position + Vector2(0, STAND_BOX.position.y * scale.y - 6.0)
	FloatingText.spawn(get_parent(), top, text, color)


## Blink the whole fighter (body + head + wheelchair) white for a moment.
## Modulating self covers all child sprites; values above 1.0 saturate the
## bright pixels toward white, which is exactly the arcade "hit blink".
func flash() -> void:
	modulate = FLASH_COLOR
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, FLASH_FADE)


func _die() -> void:
	state = FState.DEAD
	velocity = Vector2.ZERO
	hurtbox.set_deferred("collision_layer", 0)
	hitbox.set_deferred("monitoring", false)
	GameState.request_shake(SHAKE_KO)
	_play("defeated")
	GameState.play_sfx("defeat")
	died.emit(self)


# ---------------------------------------------------------------- internals
func _set_hurt_rect(r: Rect2) -> void:
	# Deferred: this can run from inside a physics signal callback.
	(_hurt_shape.shape as RectangleShape2D).set_deferred("size", r.size)
	_hurt_shape.set_deferred("position", r.get_center())


func _play(anim: String) -> void:
	if body_sprite.animation != anim or not body_sprite.is_playing():
		body_sprite.play(anim)


func _on_frame_changed() -> void:
	var attacking := state == FState.PUNCH or state == FState.KICK
	hitbox.monitoring = attacking and body_sprite.frame == 1


func _on_animation_finished() -> void:
	if state == FState.HIT:
		_since_recover = 0.0
	if state == FState.PUNCH or state == FState.KICK or state == FState.HIT:
		state = FState.IDLE
		hitbox.monitoring = false
		_play("idle")


func _on_hitbox_area_entered(area: Area2D) -> void:
	if _victims.has(area) or not area.has_meta("fighter"):
		return
	_victims[area] = true
	var target: Fighter = area.get_meta("fighter")
	target.take_hit(_attack_damage, global_position.x, _attack_knockback,
			_attack_unblockable)
