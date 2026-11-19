extends Node3D

@export var sky: Sky

const FLOOR := Color("#3e4d55")
const GRID := Color("#51626a")
const WALL := Color("#293840")
const MINT := Color("#7cc5ab")
const GOLD := Color("#eabb6e")

@onready var player: CharacterBody3D = $Player
var spawn: Vector3
var status: Label
var reticle: Control


func _ready() -> void:
	spawn = player.position
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c0d5e1")
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)

	box(Vector3(0, -0.25, 0), Vector3(26, 0.5, 32), FLOOR)
	for x in range(-12, 13, 2):
		box(Vector3(x, 0.002, 0), Vector3(0.018, 0.004, 32), GRID, false)
	for z in range(-16, 17, 2):
		box(Vector3(0, 0.002, z), Vector3(26, 0.004, 0.018), GRID, false)

	box(Vector3(-12.8, 0.8, 0), Vector3(0.4, 1.6, 32), WALL)
	box(Vector3(12.8, 0.8, 0), Vector3(0.4, 1.6, 32), WALL)
	box(Vector3(0, 0.8, -15.8), Vector3(26, 1.6, 0.4), WALL)

	# A low tunnel tests both the crouch collider and overhead clearance.
	for x in [-8.0, -3.8]:
		box(Vector3(x, 0.75, 0), Vector3(0.3, 1.5, 5), WALL)
	box(Vector3(-5.9, 1.39, 0), Vector3(4.5, 0.24, 5), MINT)
	marker("CROUCH", Vector3(-5.9, 1.9, 2.56), MINT)

	# Two ramps share a raised platform with a drop at either side.
	box(Vector3(6, 0.64, -4.3), Vector3(3.8, 1.28, 3.3), WALL)
	box(Vector3(6, 1.29, -4.3), Vector3(3.8, 0.03, 3.3), GOLD, false)
	var ramp := box(Vector3(6, 0.47, -0.2), Vector3(3.8, 0.30, 5.3), GOLD)
	ramp.rotation_degrees.x = 14.0
	var exit_ramp := box(Vector3(6, 0.47, -8.4), Vector3(3.8, 0.30, 5.3), GOLD)
	exit_ramp.rotation_degrees.x = -14.0
	marker("RAMP / DROP", Vector3(6, 2.9, -2.7), GOLD)

	box(Vector3(0, 0.18, -5), Vector3(2.1, 0.36, 0.72), MINT)
	box(Vector3(0, 0.27, -8), Vector3(2.1, 0.54, 0.72), GOLD)
	marker("JUMP", Vector3(0, 1.25, -5), MINT)
	build_hud()


func _process(_delta: float) -> void:
	if player.position.y < -8.0:
		player.position = spawn
		player.velocity = Vector3.ZERO
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	reticle.visible = captured
	status.text = "WASD  Move     Shift  Sprint     Ctrl  Crouch     Space  Jump     Esc  Release mouse" if captured else "Click to capture mouse"


func box(center: Vector3, size: Vector3, color: Color, solid := true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.position = center
	add_child(root)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	root.add_child(visual)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		root.add_child(collision)
	return root


func marker(text: String, center: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = center
	label.modulate = color
	label.font_size = 64
	label.pixel_size = 0.007
	add_child(label)


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -52.0
	status.offset_bottom = -22.0

	reticle = ColorRect.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.color = Color(1, 1, 1, 0.8)
	layer.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -2.0
	reticle.offset_top = -2.0
	reticle.offset_right = 2.0
	reticle.offset_bottom = 2.0
