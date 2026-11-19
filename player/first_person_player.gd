extends CharacterBody3D

@export_group("Movement")
@export var walk_speed := 4.4
@export var sprint_speed := 7.2
@export var crouch_speed := 2.3
@export var ground_acceleration := 26.0
@export var ground_braking := 32.0
@export var air_acceleration := 6.0
@export var jump_speed := 4.6
@export var jump_grace := 0.10
@export var jump_buffer := 0.12

@export_group("View")
@export var mouse_sensitivity := 0.0022
@export_range(0.0, 1.0) var motion_strength := 0.75
@export var base_fov := 80.0
@export var sprint_fov_boost := 6.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const STAND_EYES := 1.66
const CROUCH_EYES := 1.02

@onready var collider: CollisionShape3D = $Collider
@onready var view: Node3D = $View
@onready var camera: Camera3D = $View/Camera
@onready var foley: AudioStreamPlayer3D = $Foley
@onready var capsule := collider.shape as CapsuleShape3D
@onready var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var crouching := false
var sprinting := false
var pitch := 0.0
var jump_remaining := 0.0
var grace_remaining := 0.0
var eye_height := STAND_EYES
var stride_phase := 0.0
var gait_weight := 0.0
var travel_since_step := 0.0
var landing_offset := 0.0
var landing_velocity := 0.0
var turn_sway := 0.0
var step_sound: AudioStreamWAV
var landing_sound: AudioStreamWAV


func _ready() -> void:
	camera.fov = base_fov
	step_sound = make_foley(0.13, 142.0, 317)
	landing_sound = make_foley(0.24, 79.0, 719)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look := (event as InputEventMouseMotion).screen_relative * mouse_sensitivity
		rotate_y(-look.x)
		pitch = clampf(pitch - look.y, deg_to_rad(-89), deg_to_rad(89))
		view.rotation.x = pitch
		turn_sway = clampf(turn_sway - look.x * 0.45, -0.035, 0.035)


func has_control() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var was_grounded := is_on_floor()
	var captured := has_control()
	var movement := Vector2.ZERO
	if captured:
		movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	update_stance(captured and Input.is_action_pressed("crouch"), delta)
	sprinting = captured and was_grounded and not crouching and movement.y < -0.55 and Input.is_action_pressed("sprint")

	var top_speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	var wish := global_transform.basis * Vector3(movement.x, 0.0, movement.y) * top_speed
	var horizontal := Vector2(velocity.x, velocity.z)
	var acceleration := air_acceleration
	if was_grounded:
		acceleration = ground_braking if movement.is_zero_approx() else ground_acceleration
	if was_grounded or not movement.is_zero_approx():
		horizontal = horizontal.move_toward(Vector2(wish.x, wish.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	grace_remaining = jump_grace if was_grounded else maxf(grace_remaining - delta, 0.0)
	jump_remaining = maxf(jump_remaining - delta, 0.0) if captured else 0.0
	if captured and Input.is_action_just_pressed("jump"):
		jump_remaining = jump_buffer
	if not was_grounded:
		velocity.y -= gravity * delta
	if not crouching and jump_remaining > 0.0 and grace_remaining > 0.0:
		velocity.y = jump_speed
		jump_remaining = 0.0
		grace_remaining = 0.0
		landing_velocity += 0.55

	var fall_speed := -velocity.y
	var before := global_position
	move_and_slide()
	if not was_grounded and is_on_floor() and fall_speed > 2.1:
		landing_velocity -= clampf(fall_speed * 0.32, 0.0, 4.0)
		travel_since_step = 0.0
		play_foley(landing_sound, -17.0 + minf(fall_speed, 10.0), 0.95, 1.05)

	var displacement := global_position - before
	var distance := Vector2(displacement.x, displacement.z).length()
	update_gait(distance, movement, delta)


func update_stance(wants_crouch: bool, delta: float) -> void:
	crouching = wants_crouch or (capsule.height < STAND_HEIGHT and not has_standing_clearance())
	var target_height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	capsule.height = move_toward(capsule.height, target_height, delta * 5.0)
	collider.position.y = capsule.height * 0.5


func has_standing_clearance() -> bool:
	# Sweep the upper cap through the space it needs to occupy when standing.
	var cap := SphereShape3D.new()
	cap.radius = capsule.radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cap
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis.IDENTITY, to_global(Vector3(0, capsule.height - cap.radius, 0)))
	query.motion = Vector3.UP * (STAND_HEIGHT - capsule.height)
	var hit := get_world_3d().direct_space_state.cast_motion(query)
	query.transform.origin = to_global(Vector3(0, STAND_HEIGHT - cap.radius, 0))
	query.motion = Vector3.ZERO
	return hit[0] >= 0.999 and get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func update_gait(distance: float, movement: Vector2, delta: float) -> void:
	var moving_on_floor := is_on_floor() and distance > 0.001 and not movement.is_zero_approx()
	var step_length := 1.02 if sprinting else (0.60 if crouching else 0.83)
	if moving_on_floor:
		stride_phase = fposmod(stride_phase + distance / step_length * PI, TAU)
		travel_since_step += distance
		if travel_since_step >= step_length:
			travel_since_step = fmod(travel_since_step, step_length)
			play_foley(step_sound, -24.0 if crouching else (-12.0 if sprinting else -17.0), 0.87, 1.13)
	else:
		travel_since_step = 0.0

	var blend := 1.0 - exp(-12.0 * delta)
	gait_weight = lerpf(gait_weight, minf(distance / delta / walk_speed, 1.0) if moving_on_floor else 0.0, blend)
	eye_height = lerpf(eye_height, CROUCH_EYES if crouching else STAND_EYES, blend)
	turn_sway = lerpf(turn_sway, 0.0, blend)
	landing_velocity += (-landing_offset * 125.0 - landing_velocity * 17.0) * delta
	landing_offset += landing_velocity * delta
	var bob := gait_weight * (0.042 if sprinting else 0.024)
	camera.position.x = sin(stride_phase) * bob * 0.70 * motion_strength
	camera.position.y = eye_height - STAND_EYES + (cos(stride_phase * 2.0) * bob + landing_offset) * motion_strength
	var strafe := -movement.x * gait_weight * 0.022
	camera.rotation.z = lerpf(camera.rotation.z, (strafe + turn_sway) * motion_strength, blend)
	camera.fov = lerpf(camera.fov, base_fov + (sprint_fov_boost * motion_strength if sprinting else 0.0), blend)


func play_foley(sound: AudioStreamWAV, volume: float, low_pitch: float, high_pitch: float) -> void:
	foley.stream = sound
	foley.volume_db = volume
	foley.pitch_scale = randf_range(low_pitch, high_pitch)
	foley.play()


func make_foley(duration: float, frequency: float, noise_seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var sample_rate := 22050
	var pcm := PackedByteArray()
	var sample_count := int(duration * sample_rate)
	pcm.resize(sample_count * 2)
	var filtered_noise := 0.0
	for index in range(sample_count):
		var time := float(index) / sample_rate
		filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.24)
		var envelope := minf(time * 450.0, 1.0) * pow(1.0 - time / duration, 3.4)
		var thump := sin(TAU * frequency * time / (1.0 + 8.0 * time))
		var sample := (filtered_noise * 0.75 + thump * 0.24) * envelope
		pcm.encode_s16(index * 2, int(sample * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = sample_rate
	sound.data = pcm
	return sound
