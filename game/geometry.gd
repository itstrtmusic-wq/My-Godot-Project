extends RefCounted


static func material(tint: Color, glow := 0.0, metal := 0.0) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = tint
	surface.roughness = 0.76
	surface.metallic = metal
	if glow > 0.0:
		surface.emission_enabled = true
		surface.emission = tint
		surface.emission_energy_multiplier = glow
	return surface


static func mesh(parent: Node3D, shape: Mesh, at: Vector3,
		surface: Material, casts_shadow := true) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.mesh = shape
	model.position = at
	model.material_override = surface
	if not casts_shadow:
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(model)
	return model


static func box(parent: Node3D, at: Vector3, size: Vector3,
		surface: Material, casts_shadow := true) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, at, surface, casts_shadow)


static func tapered(parent: Node3D, at: Vector3, height: float, radius: float,
		tip: float, surface: Material, sides := 7, casts_shadow := true) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.height = height
	shape.bottom_radius = radius
	shape.top_radius = tip
	shape.radial_segments = sides
	shape.rings = 0
	return mesh(parent, shape, at, surface, casts_shadow)


static func sphere(parent: Node3D, at: Vector3, size: Vector3,
		surface: Material, casts_shadow := true) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radial_segments = 10
	shape.rings = 5
	var model := mesh(parent, shape, at, surface, casts_shadow)
	model.scale = size
	return model


static func collider(body: CollisionObject3D, at: Vector3, size: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	return collision


static func beam(parent: Node3D, from: Vector3, to: Vector3, width: float,
		surface: Material, casts_shadow := true) -> MeshInstance3D:
	var direction := to - from
	var model := box(parent, (from + to) * 0.5,
			Vector3(width, width, maxf(direction.length(), 0.001)), surface, casts_shadow)
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
	model.basis = Basis.looking_at(direction if not direction.is_zero_approx() else Vector3.FORWARD, up)
	return model


static func sign(parent: Node3D, text: String, at: Vector3, size: float,
		tint := Color("#e5c99a")) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.font_size = 64
	tag.pixel_size = size / float(tag.font_size)
	tag.modulate = tint
	tag.outline_size = 8
	tag.position = at
	parent.add_child(tag)
	return tag
