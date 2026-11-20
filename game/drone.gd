extends CharacterBody3D

signal fired(drone: CharacterBody3D, origin: Vector3, destination: Vector3, damage: float)
signal downed(drone: CharacterBody3D)

const Rules = preload("res://game/rules.gd")
const Geo = preload("res://game/geometry.gd")
const WATCH_RANGE := 18.0
const ATTACK_RANGE := 17.0
const LOCK_TIME := 0.56

var player: CharacterBody3D
var relay: StaticBody3D
var anchor := Vector3.ZERO
var tier := 0
var assault := false
var patrol_id := -1
var health := 56.0
var speed := 3.6
var cooldown := 1.5
var winding := 0.0
var locked_point := Vector3.ZERO
var age := 0.0
var orbit := 1.0
var shell: Node3D
var core: MeshInstance3D
var rotors: Array[MeshInstance3D] = []
var active_light := Geo.material(Color("#f4a66c"), 1.8)
var danger_light := Geo.material(Color("#ff5345"), 3.0)
var idle_light := Geo.material(Color("#7bdecc"), 0.9)


func setup(at: Vector3, subject: CharacterBody3D, terminal: StaticBody3D,
		attack: bool, rank: int, identity := -1) -> void:
	position = at
	anchor = at
	player = subject
	relay = terminal
	assault = attack
	tier = rank
	patrol_id = identity
	health = 48.0 + 12.0 * tier
	speed = 3.4 + 0.36 * tier
	cooldown = randf_range(1.2, 2.5)
	orbit = -1.0 if randf() > 0.5 else 1.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = Rules.DRONE
	collision_mask = Rules.SOLIDS | Rules.PLAYER | Rules.DRONE
	var hit_volume := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.57
	hit_volume.shape = sphere
	add_child(hit_volume)

	shell = Node3D.new()
	add_child(shell)
	var metal := Geo.material(Color("#556a73") if tier < 2 else Color("#805850"), 0.0, 0.42)
	var black := Geo.material(Color("#222b32"))
	Geo.sphere(shell, Vector3.ZERO, Vector3(1.2, 0.63, 0.88), metal)
	Geo.box(shell, Vector3(0.0, -0.05, -0.34), Vector3(0.69, 0.25, 0.19), black)
	core = Geo.box(shell, Vector3(0.0, -0.035, -0.446), Vector3(0.34, 0.065, 0.023), idle_light)
	for side in [-1.0, 1.0]:
		Geo.box(shell, Vector3(side * 0.53, 0.0, 0), Vector3(0.46, 0.11, 0.24), black)
		Geo.tapered(shell, Vector3(side * 0.66, 0.03, 0), 0.19, 0.28, 0.28, metal, 9)
		var rotor := Geo.box(shell, Vector3(side * 0.66, 0.142, 0), Vector3(0.46, 0.025, 0.075), idle_light)
		rotors.append(rotor)


func _physics_process(delta: float) -> void:
	if health <= 0.0 or not is_instance_valid(player):
		return
	age += delta
	var player_point := player.global_position + Vector3.UP * (1.08 if player.get("crouching") else 1.4)
	var from := global_position
	var has_player := from.distance_squared_to(player_point) <= WATCH_RANGE * WATCH_RANGE and clear_to(player_point, player)
	var target := player_point if has_player else Rules.RELAY_CORE
	var active := has_player or assault
	var desired := patrol_velocity() if not active else pursuit_velocity(target, has_player)
	velocity = velocity.move_toward(desired, delta * 11.0)
	move_and_slide()
	if get_slide_collision_count() > 0 and int(age * 2.0) % 2 == 0:
		orbit = 1.0 if sin(age) > 0.0 else -1.0
	var heading := (target - from) if active else velocity
	if Vector2(heading.x, heading.z).length_squared() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-heading.x, -heading.z), delta * 6.0)
	shell.position.y = sin(age * 4.7) * 0.045
	for rotor in rotors:
		rotor.rotation.y += delta * 34.0
	update_attack(delta, active, target)


func patrol_velocity() -> Vector3:
	var center := anchor + Vector3(cos(age * 0.65) * 2.6, sin(age * 1.1) * 0.28, sin(age * 0.65) * 2.6)
	return (center - global_position).limit_length(speed * 0.55)


func pursuit_velocity(target: Vector3, follows_player: bool) -> Vector3:
	var offset := target - global_position
	var flat := Vector3(offset.x, 0, offset.z)
	var forward := flat.normalized()
	var proximity := 7.0 if follows_player else 6.0
	var radial := clampf((flat.length() - proximity) * 0.57, -0.65, 1.0)
	var preferred_y := target.y + 0.95 + sin(age * 1.6 + tier) * 0.38
	var desired := forward * radial + forward.cross(Vector3.UP) * orbit * (0.40 if radial > 0.55 else 0.88)
	desired.y = clampf((preferred_y - global_position.y) * 1.55, -1.0, 1.0)
	# Slide sideways and rise when flying into terrain or scenery.
	var probe := Rules.cast(get_world_3d().direct_space_state, global_position,
		global_position + desired.normalized() * 1.65, Rules.WORLD, [get_rid()])
	if not probe.is_empty():
		desired = forward.cross(Vector3.UP) * orbit * 0.58 + Vector3.UP
	return desired.limit_length(1.0) * speed


func clear_to(point: Vector3, target: CollisionObject3D) -> bool:
	var hit := Rules.cast(get_world_3d().direct_space_state, global_position, point,
		Rules.SHOT_MASK, [get_rid()])
	return hit.is_empty() or hit.collider == target


func update_attack(delta: float, active: bool, point: Vector3) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if winding > 0.0:
		winding = maxf(0.0, winding - delta)
		if winding <= 0.0:
			fired.emit(self, global_position, locked_point, 7.0 + 1.5 * tier)
			cooldown = maxf(1.25, randf_range(2.1, 2.9) - tier * 0.19)
		core.material_override = danger_light
		return
	core.material_override = active_light if active else idle_light
	if active and cooldown <= 0.0 and global_position.distance_to(point) <= ATTACK_RANGE:
		locked_point = point
		winding = LOCK_TIME


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health == 0.0:
		downed.emit(self)
