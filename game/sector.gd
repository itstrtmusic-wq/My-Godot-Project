extends Node3D

const Rules = preload("res://game/rules.gd")
const Geo = preload("res://game/geometry.gd")
const TERRAIN_SHADER = preload("res://game/terrain.gdshader")

const TIMBER_SITES := [
	Vector2(-8, 4), Vector2(-15, -4), Vector2(-23, -6), Vector2(-29, 7),
	Vector2(-35, -18), Vector2(-28, 23), Vector2(27, 17), Vector2(42, -12),
]
const ALLOY_SITES := [
	Vector2(8, 5), Vector2(14, -6), Vector2(21, -17), Vector2(27, -32),
	Vector2(35, -27), Vector2(29, 23), Vector2(-31, -32), Vector2(41, 6),
]
const FIBER_SITES := [
	Vector2(-6, 0), Vector2(-16, -12), Vector2(7, -3), Vector2(-27, 1),
	Vector2(-22, 15), Vector2(16, 19), Vector2(27, -23), Vector2(-37, -26),
]
const RATION_SITES := [Vector2(3, 9), Vector2(-12, 16), Vector2(34, -32), Vector2(-25, -18)]
const BORDER := Rules.MAP_BOUNDARY

var ground: StaticBody3D
var relay: StaticBody3D
var relay_lamp: MeshInstance3D
var sites := {}
var available := {}
var depleted := {}
var rng := RandomNumberGenerator.new()
var bark := Geo.material(Color("#5c4635"))
var pine := Geo.material(Color("#213d37"))
var pine_tip := Geo.material(Color("#3e5541"))
var rock := Geo.material(Color("#515658"))
var concrete := Geo.material(Color("#677071"))
var steel := Geo.material(Color("#274045"), 0.0, 0.16)
var dark := Geo.material(Color("#20292e"))
var orange := Geo.material(Color("#c97d45"), 0.14)
var mint := Geo.material(Color("#6cd5ba"), 0.8)


func _ready() -> void:
	rng.seed = 8316107
	set_atmosphere()
	make_ground()
	make_boundaries()
	make_relay()
	make_depot()
	register_sites("timber", "Windbreak pine", TIMBER_SITES, {"timber": 7})
	register_sites("alloy", "Alloy salvage", ALLOY_SITES, {"alloy": 5})
	register_sites("fiber", "Field fiber", FIBER_SITES, {"fiber": 4})
	register_sites("rations", "Supply cache", RATION_SITES, {"rations": 2})
	scatter_landscape()
	make_skylines()
	make_ground_cover()


func height_at(x: float, z: float) -> float:
	var distance := maxf(absf(x), absf(z))
	var foothills := smoothstep(27.0, 61.0, distance)
	var roll := sin(x * 0.099) * cos(z * 0.128) * 1.9 + cos(z * 0.112 + x * 0.055) * 1.8
	return (roll + 2.6) * foothills


func at_ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


func set_atmosphere() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#263d59")
	sky_material.sky_horizon_color = Color("#a89b84")
	sky_material.ground_horizon_color = Color("#a89b84")
	sky_material.ground_bottom_color = Color("#3a4940")
	sky_material.sun_angle_max = 9.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_SKY
	atmosphere.sky = sky
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("#b3cbd5")
	atmosphere.ambient_light_energy = 0.52
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	atmosphere.fog_enabled = true
	atmosphere.fog_light_color = Color("#879b9b")
	atmosphere.fog_density = 0.0058
	atmosphere.fog_sky_affect = 0.28
	var environment := WorldEnvironment.new()
	environment.environment = atmosphere
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25.0, -60.0, 0.0)
	sun.light_color = Color("#ffc590")
	sun.light_energy = 0.91
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75.0
	add_child(sun)


func make_ground() -> void:
	const SEGMENTS := 76
	const EXTENT := 95.0
	var step := EXTENT * 2.0 / SEGMENTS
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(SEGMENTS + 1):
		for x in range(SEGMENTS + 1):
			var point := at_ground(-EXTENT + x * step, -EXTENT + z * step)
			vertices.append(point)
			normals.append(Vector3(
				height_at(point.x - 0.25, point.z) - height_at(point.x + 0.25, point.z),
				0.5, height_at(point.x, point.z - 0.25) - height_at(point.x, point.z + 0.25)
			).normalized())
	for z in range(SEGMENTS):
		for x in range(SEGMENTS):
			var i := z * (SEGMENTS + 1) + x
			indices.append_array([i, i + 1, i + SEGMENTS + 1,
				i + 1, i + SEGMENTS + 2, i + SEGMENTS + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain := ArrayMesh.new()
	terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := ShaderMaterial.new()
	surface.shader = TERRAIN_SHADER
	ground = body_at(Vector3.ZERO, Rules.WORLD)
	Geo.mesh(ground, terrain, Vector3.ZERO, surface)
	var collision := CollisionShape3D.new()
	collision.shape = terrain.create_trimesh_shape()
	ground.add_child(collision)


func make_boundaries() -> void:
	var rail := Geo.material(Color("#6c725c"))
	for side in [-1.0, 1.0]:
		var z_wall := body_at(Vector3(0.0, 0.0, side * BORDER), Rules.WORLD)
		Geo.collider(z_wall, Vector3(0.0, 6.0, 0.0), Vector3(BORDER * 2.0, 20.0, 0.5))
		var x_wall := body_at(Vector3(side * BORDER, 0.0, 0.0), Rules.WORLD)
		Geo.collider(x_wall, Vector3(0.0, 6.0, 0.0), Vector3(0.5, 20.0, BORDER * 2.0))
		for i in range(-64, 65, 4):
			var across := at_ground(float(i), side * BORDER)
			var along := at_ground(side * BORDER, float(i))
			Geo.box(self, across + Vector3.UP * 0.65, Vector3(0.13, 1.4, 0.15), rail)
			if i < 64:
				Geo.beam(self, across + Vector3.UP, at_ground(i + 4.0, side * BORDER) + Vector3.UP, 0.08, rail)
			Geo.box(self, along + Vector3.UP * 0.65, Vector3(0.15, 1.4, 0.13), rail)
			if i < 64:
				Geo.beam(self, along + Vector3.UP, at_ground(side * BORDER, i + 4.0) + Vector3.UP, 0.08, rail)


func make_relay() -> void:
	relay = body_at(Rules.RELAY_POSITION, Rules.RELAY)
	Geo.collider(relay, Vector3(0, 0.75, 0), Vector3(2.26, 1.5, 1.72))
	Geo.box(relay, Vector3(0, 0.08, 0), Vector3(2.48, 0.16, 1.92), concrete)
	Geo.box(relay, Vector3(0, 0.85, 0), Vector3(2.05, 1.4, 1.54), steel)
	Geo.box(relay, Vector3(0, 0.91, 0.79), Vector3(1.34, 0.55, 0.1), dark)
	relay_lamp = Geo.box(relay, Vector3(0, 0.99, 0.856), Vector3(0.8, 0.045, 0.022), orange)
	Geo.sign(relay, "RELAY 04", Vector3(0, 1.31, 0.842), 0.20)
	for offset in [-0.72, 0.72]:
		Geo.box(relay, Vector3(offset, 3.6, -0.4), Vector3(0.115, 6.8, 0.13), steel)
		Geo.box(relay, Vector3(offset, 3.6, 0.36), Vector3(0.115, 6.8, 0.13), steel)
	for level in range(2, 8):
		var y := float(level)
		Geo.beam(relay, Vector3(-0.72, y, 0.36), Vector3(0.72, y, 0.36), 0.07, concrete)
		Geo.beam(relay, Vector3(-0.72, y, 0.36), Vector3(0.72, y - 1.0, 0.36), 0.06, steel)
		Geo.beam(relay, Vector3(-0.72, y, -0.4), Vector3(0.72, y - 1.0, -0.4), 0.06, steel)
	Geo.box(relay, Vector3(0.0, 7.15, 0.0), Vector3(2.34, 0.21, 1.35), dark)
	var antenna := Geo.tapered(relay, Vector3(0.35, 7.51, 0.13), 0.18, 0.69, 0.29, concrete, 14)
	antenna.rotate_z(-0.40)
	Geo.tapered(relay, Vector3(-0.42, 7.85, 0.0), 1.38, 0.036, 0.025, steel)
	Geo.sphere(relay, Vector3(-0.42, 8.58, 0.0), Vector3.ONE * 0.19, orange)
	for x in [-3.5, 3.5]:
		var plinth := body_at(Vector3(x, 0.0, -13.0), Rules.WORLD)
		Geo.collider(plinth, Vector3.UP * 0.32, Vector3(0.72, 0.64, 0.72))
		Geo.box(plinth, Vector3.UP * 0.32, Vector3(0.72, 0.64, 0.72), concrete)
		Geo.box(plinth, Vector3.UP * 0.67, Vector3(0.48, 0.057, 0.48), orange)


func set_relay_active(active: bool) -> void:
	relay_lamp.material_override = mint if active else orange


func make_depot() -> void:
	for index in range(3):
		var at := at_ground(20.5 + index * 4.2, -24.5 - index * 3.6)
		var container := body_at(at + Vector3.UP * 0.1, Rules.WORLD)
		var wall := steel if index != 1 else Geo.material(Color("#785144"))
		Geo.collider(container, Vector3.UP * 1.3, Vector3(3.3, 2.84, 6.03))
		Geo.box(container, Vector3.UP * 1.26, Vector3(3.2, 2.74, 6.0), wall)
		for rib in range(9):
			for side in [-1.0, 1.0]:
				Geo.box(container, Vector3(side * 1.62, 1.27, rib * 0.62 - 2.48),
					Vector3(0.10, 2.43, 0.095), dark)
		Geo.box(container, Vector3(0, 1.28, 3.02), Vector3(3.16, 0.14, 0.073), dark)
		if index == 0:
			Geo.sign(container, "SALVAGE DEPOT", Vector3(0, 1.96, 3.05), 0.26)


func register_sites(prefix: String, title: String, positions: Array, yields: Dictionary) -> void:
	for index in range(positions.size()):
		var point: Vector2 = positions[index]
		var id := "%s/%d" % [prefix, index]
		sites[id] = {"at": at_ground(point.x, point.y), "title": title, "yields": yields, "kind": prefix}
		spawn_supply(id)


func spawn_supply(id: String) -> void:
	var data: Dictionary = sites[id]
	var supply := body_at(data.at, Rules.SUPPLY)
	supply.set_meta("supply", id)
	match data.kind:
		"timber":
			pine_at(supply, Vector3.ZERO, 3.5, true)
			Geo.box(supply, Vector3(0, 0.93, 0.03), Vector3(0.58, 0.095, 0.58), orange)
		"alloy":
			crate(supply, 0.9, steel, mint)
		"fiber":
			Geo.collider(supply, Vector3(0, 0.32, 0), Vector3(0.83, 0.66, 0.83))
			for i in range(5):
				var angle := i * TAU / 5.0
				var leaf := Geo.tapered(supply, Vector3(cos(angle) * 0.22, 0.3, sin(angle) * 0.22),
					0.68, 0.16, 0.025, pine_tip, 4)
				leaf.rotation = Vector3(sin(angle) * 0.6, 0, cos(angle) * 0.6)
			Geo.sphere(supply, Vector3.UP * 0.36, Vector3(0.35, 0.32, 0.35), mint)
		"rations":
			crate(supply, 0.67, dark, orange)
	available[id] = supply


func crate(supply: StaticBody3D, scale_factor: float, body_material: Material, trim: Material) -> void:
	var size := Vector3(1.15, 0.78, 0.86) * scale_factor
	Geo.collider(supply, Vector3.UP * size.y * 0.5, size)
	Geo.box(supply, Vector3.UP * size.y * 0.5, size, body_material)
	for inset in [-0.33, 0.33]:
		Geo.box(supply, Vector3(inset * size.x, size.y * 0.5, 0),
			Vector3(0.10, size.y + 0.02, size.z + 0.02), dark)
	Geo.box(supply, Vector3(0, size.y * 0.62, size.z * 0.502),
		Vector3(size.x * 0.42, 0.12, 0.02), trim)
	Geo.box(supply, Vector3(0, size.y * 1.02, 0), Vector3(size.x * 0.42, 0.025, 0.12), trim)


func harvest(id: String) -> Dictionary:
	if not available.has(id):
		return {}
	remove_supply(id)
	depleted[id] = 150.0
	return sites[id].yields


func remove_supply(id: String) -> void:
	var supply: StaticBody3D = available[id]
	remove_child(supply)
	supply.queue_free()
	available.erase(id)


func restore_supplies(saved: Dictionary) -> void:
	for id in saved:
		if available.has(id):
			remove_supply(id)
			depleted[id] = float(saved[id])


func replenish(delta: float, player_position: Vector3) -> void:
	for id in depleted.keys():
		depleted[id] = maxf(0.0, depleted[id] - delta)
		var at: Vector3 = sites[id].at
		if depleted[id] <= 0.0 and at.distance_squared_to(player_position) > 20.0:
			depleted.erase(id)
			spawn_supply(id)


func reserved_supply_space(at: Vector3, radius := 1.4) -> bool:
	for site: Dictionary in sites.values():
		var anchor: Vector3 = site.at
		if Vector2(anchor.x - at.x, anchor.z - at.z).length_squared() < radius * radius:
			return true
	return false


func body_at(at: Vector3, layer: int) -> StaticBody3D:
	var object := StaticBody3D.new()
	object.position = at
	object.collision_layer = layer
	object.collision_mask = 0
	add_child(object)
	return object


func pine_at(root: Node3D, at: Vector3, height: float, solid: bool) -> void:
	Geo.tapered(root, at + Vector3.UP * height * 0.34, height * 0.68, height * 0.085,
			height * 0.025, bark, 6)
	for i in range(3):
		var tier := float(i)
		var model := Geo.tapered(root, at + Vector3.UP * height * (0.50 + tier * 0.18),
			height * (0.52 - tier * 0.055), height * (0.27 - tier * 0.054), 0.02,
			pine if i < 2 else pine_tip, 7)
		model.rotation.y = tier * 0.34
	if solid:
		Geo.collider(root, at + Vector3.UP * 0.89, Vector3(0.48, 1.78, 0.48))


func scatter_landscape() -> void:
	for i in range(105):
		var point := Vector2(rng.randf_range(-76, 76), rng.randf_range(-74, 76))
		if maxf(absf(point.x), absf(point.y)) < 30.0:
			continue
		var at := at_ground(point.x, point.y)
		if reserved_supply_space(at) or (point.x > 18 and point.x < 34 and point.y < -20 and point.y > -38):
			continue
		var height := rng.randf_range(2.7, 7.8)
		var trunk := body_at(at, Rules.WORLD)
		pine_at(trunk, Vector3.ZERO, height, true)
	for i in range(92):
		var point := Vector2(rng.randf_range(-83, 83), rng.randf_range(-83, 83))
		if maxf(absf(point.x), absf(point.y)) < 28.0:
			continue
		var at := at_ground(point.x, point.y)
		var dimensions := Vector3(rng.randf_range(0.65, 3.8), rng.randf_range(0.48, 2.2), rng.randf_range(0.8, 3.7))
		if reserved_supply_space(at):
			continue
		var stone := body_at(at, Rules.WORLD)
		var model := Geo.sphere(stone, Vector3.UP * dimensions.y * 0.22, dimensions, rock)
		model.rotation.y = rng.randf_range(0, TAU)
		if dimensions.x > 1.8 and dimensions.y > 1.1:
			Geo.collider(stone, Vector3.UP * dimensions.y * 0.20, dimensions * 0.66)



func make_skylines() -> void:
	ridge(123.0, 36.0, 20.0, 0.2, Color("#526879"))
	ridge(214.0, 68.0, 47.0, 1.8, Color("#627a8b"))


func ridge(radius: float, height: float, span: float, phase: float, color: Color) -> void:
	const POINTS := 120
	const ROWS := [-1.0, -0.57, -0.20, 0.0, 0.40, 1.0]
	var grid := PackedVector3Array()
	for row in ROWS:
		for index in range(POINTS + 1):
			var angle := (index % POINTS) / float(POINTS) * TAU
			var serration := sin(angle * 21.0 + phase) * 0.085 + sin(angle * 37.0) * 0.07
			var crest := 0.56 + sin(angle * 5.0 + phase) * 0.19 + cos(angle * 11.0 - phase) * 0.14 + serration
			var radial := radius + span * float(row) + sin(angle * 13.0 + phase) * 4.5
			var y := -7.5 + height * crest * pow(1.0 - absf(float(row)), 1.27)
			grid.append(Vector3(cos(angle) * radial, y, sin(angle) * radial))

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(ROWS.size() - 1):
		for index in range(POINTS):
			var first := row * (POINTS + 1) + index
			var next := first + POINTS + 1
			for vertex_index in [first, next, first + 1, first + 1, next, next + 1]:
				var point := grid[vertex_index]
				var tint := smoothstep(height * 0.42, height * 0.73, point.y) * 0.65
				var base := color.lerp(Color("#b9c2c4"), tint)
				tool.set_color(base.darkened(float((index * 79 + row * 23) % 7) * 0.014))
				tool.set_smooth_group(-1)
				tool.add_vertex(point)
	tool.generate_normals()
	var material := Geo.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	Geo.mesh(self, tool.commit(), Vector3.ZERO, material, false)


func make_ground_cover() -> void:
	var grass := SurfaceTool.new()
	grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(5):
		var x := cos(blade * TAU / 5.0) * 0.13
		var z := sin(blade * TAU / 5.0) * 0.13
		var tip := Vector3(x * 2.1, 0.15 + (blade % 3) * 0.075, z * 2.1)
		for point in [Vector3(x - 0.037, 0, z), Vector3(x + 0.037, 0, z), tip]:
			grass.set_color(Color("#536458") if point.y == 0.0 else Color("#778267"))
			grass.add_vertex(point)
	grass.generate_normals()
	var material := Geo.material(Color.WHITE)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	var tuft := grass.commit()
	tuft.surface_set_material(0, material)
	var poses: Array[Transform3D] = []
	for index in range(5300):
		var point := Vector2(rng.randf_range(-67, 67), rng.randf_range(-67, 67))
		if absf(point.x) < 3.0 or point.distance_squared_to(Vector2(0, -13)) < 51.0:
			continue
		if sin(point.x * 0.83) + cos(point.y * 1.03) < -0.5:
			continue
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.65, 1.65))
		poses.append(Transform3D(basis, at_ground(point.x, point.y) + Vector3.DOWN * 0.02))
	var mulch := MultiMesh.new()
	mulch.transform_format = MultiMesh.TRANSFORM_3D
	mulch.mesh = tuft
	mulch.instance_count = poses.size()
	for index in range(poses.size()):
		mulch.set_instance_transform(index, poses[index])
	var foliage := MultiMeshInstance3D.new()
	foliage.multimesh = mulch
	foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foliage)
