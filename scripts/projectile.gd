class_name Projectile
extends Area2D
## Thrown beer bottle, from Tight 5 FIGHT!: flies straight at a height that
## meets a standing fighter and clears a ducking one. Only looks at the
## opponent's hurtbox layer (set collision_mask_bits before add_child), so a
## thrower can't bean themselves.

const DAMAGE := 10.0

var velocity := Vector2.ZERO
var collision_mask_bits := 0
var _sprite: Sprite2D
var _life := 4.0  # safety net so a throw that misses everything can't linger


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = 0
	collision_mask = collision_mask_bits
	_sprite = Sprite2D.new()
	var bottle_path := GameState.projectile_path()
	if bottle_path != "" and ResourceLoader.exists(bottle_path):
		_sprite.texture = load(bottle_path)
	_sprite.scale = Vector2(1.5, 1.5)
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(18, 22)
	cs.shape = rs
	add_child(cs)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	position += velocity * delta
	_sprite.rotation += 8.0 * delta
	var w := get_viewport_rect().size.x
	if _life <= 0.0 or position.x < -40.0 or position.x > w + 40.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta("fighter"):
		return
	var f: Fighter = area.get_meta("fighter")
	# Bottles go through a guard: the answer to one is ducking.
	f.take_hit(DAMAGE, global_position.x, 1.0, true)
	GameState.play_sfx("smash")
	if randf() < 0.25:
		GameState.play_crowd("laugh")
		GameState.crowd_reaction.emit("laugh")
	queue_free()
