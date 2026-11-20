extends RefCounted

const WORLD := 1
const PLAYER := 2
const DRONE := 4
const SUPPLY := 8
const COVER := 16
const RELAY := 32
const SOLIDS := WORLD | SUPPLY | COVER | RELAY
const SHOT_MASK := SOLIDS | PLAYER | DRONE

const SUPPLIES := ["timber", "alloy", "fiber", "rations", "patches"]
const LABELS := {
	"timber": "Timber", "alloy": "Alloy", "fiber": "Fiber",
	"rations": "Rations", "patches": "Trauma patches",
}
const RELAY_COST := {"alloy": 9, "fiber": 5}
const REPAIR_COST := {"alloy": 2}
const RECIPES := {
	"cartridge": {"title": "Cartridge pack", "detail": "18 carbine rounds", "cost": {"alloy": 2}},
	"patches": {"title": "Trauma patch", "detail": "Restores 40 health", "cost": {"fiber": 3}},
}
const PIECES := {
	"wall": {"title": "Timber wall", "health": 72.0, "cost": {"timber": 4}},
	"gate": {"title": "Sliding gate", "health": 94.0, "cost": {"timber": 4, "alloy": 2}},
	"roof": {"title": "Canopy", "health": 65.0, "cost": {"timber": 5}},
}
const BUILD_ORDER := ["wall", "gate", "roof"]
const WAVES := [3, 4, 6]
const MAX_STACK := 999
const RELAY_HEALTH := 150.0
const MAGAZINE := 18
const MAP_BOUNDARY := 68.0
const CELL_SIZE := 2.6
const BUILD_REACH := 8.0
const INTERACT_REACH := 4.4
const MAX_STRUCTURES := 180
const SPAWN := Vector3(0.0, 0.1, 13.0)
const RELAY_POSITION := Vector3(0.0, 0.0, -13.0)
const RELAY_CORE := RELAY_POSITION + Vector3(0.0, 1.15, 0.0)


static func afford(inventory: Dictionary, cost: Dictionary) -> bool:
	for item in cost:
		if inventory.get(item, 0) < cost[item]:
			return false
	return true


static func describe(items: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in items:
		parts.append("%d %s" % [items[item], LABELS[item]])
	return "  /  ".join(parts)


static func cell_allowed(cell: Vector2i) -> bool:
	if absi(cell.x) > 7 or cell.y < -10 or cell.y > 6:
		return false
	# Leave the relay terminal and the spawn lane accessible.
	return not (absi(cell.x) <= 1 and (absi(cell.y + 5) <= 1 or cell.y >= 4))


static func cell_position(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)


static func cell_key(cell: Vector2i, kind: String) -> String:
	return "%d:%d:%s" % [cell.x, cell.y, "upper" if kind == "roof" else "ground"]


static func cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		mask: int, exclude: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	query.hit_from_inside = true
	return space.intersect_ray(query)


static func overlaps(space: PhysicsDirectSpaceState3D, size: Vector3, pose: Transform3D,
		mask: int, exclude: Array[RID] = []) -> bool:
	var shape := BoxShape3D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose
	query.collision_mask = mask
	query.exclude = exclude
	return not space.intersect_shape(query, 1).is_empty()
