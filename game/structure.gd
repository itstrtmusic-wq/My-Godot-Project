extends StaticBody3D

const Rules = preload("res://game/rules.gd")
const Geo = preload("res://game/geometry.gd")
const WALL_SIZE := Vector3(2.57, 2.25, 0.24)
const GATE_SIZE := Vector3(2.16, 2.25, 0.24)
const ROOF_SIZE := Vector3(2.57, 0.20, 2.57)
const POST_SIZE := Vector3(0.18, 2.52, 0.18)
const POSTS := [Vector3(-1.18, 1.26, -1.18), Vector3(1.18, 1.26, 1.18)]

var kind := "wall"
var cell := Vector2i.ZERO
var turn := 0
var health := 0.0
var gate_open := false
var is_preview := false
var gate_panel: Node3D
var gate_shape: CollisionShape3D
var models: Array[MeshInstance3D] = []
var wood := Geo.material(Color("#88664a"))
var wood_light := Geo.material(Color("#ad8259"))
var trim := Geo.material(Color("#354a48"), 0.0, 0.26)
var mark := Geo.material(Color("#cd9d55"), 0.08)


func setup(piece: String, plot: Vector2i, facing: int, preview := false) -> void:
	kind = piece
	cell = plot
	turn = facing
	is_preview = preview
	position = Rules.cell_position(cell)
	rotation.y = turn * PI * 0.5
	health = Rules.PIECES[kind].health
	collision_layer = 0 if is_preview else Rules.COVER
	collision_mask = 0


func _ready() -> void:
	match kind:
		"roof":
			part(Vector3.UP * 2.6, ROOF_SIZE, trim)
			for at: Vector3 in POSTS:
				part(at, POST_SIZE, wood)
			for x in [-0.83, 0.0, 0.83]:
				decoration(self, Vector3(x, 2.49, 0), Vector3(0.12, 0.12, 2.56), wood_light)
		"gate":
			for x in [-1.18, 1.18]:
				part(Vector3(x, 1.24, 0.0), Vector3(0.20, 2.48, 0.3), trim)
			part(Vector3.UP * 2.362, Vector3(2.57, 0.23, 0.32), trim)
			gate_panel = Node3D.new()
			add_child(gate_panel)
			if not is_preview:
				gate_shape = Geo.collider(self, Vector3.UP * 1.125, GATE_SIZE)
			decoration(gate_panel, Vector3.UP * 1.125, GATE_SIZE, wood)
			for y in [0.3, 0.73, 1.15, 1.57, 2.0]:
				decoration(gate_panel, Vector3(0.0, y, 0.0), Vector3(2.16, 0.045, 0.26), trim)
			decoration(gate_panel, Vector3(0.71, 1.15, 0.0), Vector3(0.23, 0.12, 0.31), mark)
		_:
			if not is_preview:
				Geo.collider(self, Vector3.UP * 1.125, WALL_SIZE)
			for i in range(9):
				var x := (float(i) - 4.0) * 0.284
				decoration(self, Vector3(x, 1.125, 0), Vector3(0.278, 2.25, 0.24),
						wood_light if i % 3 == 0 else wood)
			for y in [0.27, 1.86]:
				decoration(self, Vector3.UP * y, Vector3(2.57, 0.13, 0.30), trim)


func part(at: Vector3, size: Vector3, material: Material) -> void:
	decoration(self, at, size, material)
	if not is_preview:
		Geo.collider(self, at, size)


func decoration(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	models.append(Geo.box(parent, at, size, material, not is_preview))


func tint_preview(material: Material) -> void:
	for model in models:
		if model.material_override != material:
			model.material_override = material


func set_open(open: bool) -> void:
	if kind != "gate" or gate_shape == null:
		return
	gate_open = open
	gate_panel.position.y = 2.24 if open else 0.0
	gate_panel.scale.y = 0.09 if open else 1.0
	gate_shape.set_deferred("disabled", open)


func may_close(space: PhysicsDirectSpaceState3D) -> bool:
	return not Rules.overlaps(space, GATE_SIZE, global_transform.translated_local(Vector3.UP * 1.125),
			Rules.PLAYER | Rules.DRONE | Rules.COVER, [get_rid()])


static func fits(space: PhysicsDirectSpaceState3D, piece: String, plot: Vector2i, facing: int) -> bool:
	var pose := Transform3D(Basis(Vector3.UP, facing * PI * 0.5), Rules.cell_position(plot))
	# Keep the query just above the terrain, including on coplanar ground.
	var mask := Rules.SHOT_MASK
	if piece == "roof":
		if Rules.overlaps(space, ROOF_SIZE, pose.translated_local(Vector3.UP * 2.6), mask):
			return false
		for at: Vector3 in POSTS:
			if Rules.overlaps(space, POST_SIZE - Vector3.UP * 0.10,
					pose.translated_local(at + Vector3.UP * 0.055), mask):
				return false
		return true
	return not Rules.overlaps(space, WALL_SIZE + Vector3(0.008, -0.10, 0.06),
			pose.translated_local(Vector3.UP * 1.18), mask)
