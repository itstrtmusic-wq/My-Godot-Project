extends RefCounted

const Rules = preload("res://game/rules.gd")
const VERSION := 1
const SAVE_PATH := "user://cinderline-run.json"
const MAX_FILE_SIZE := 131072


static func read(path := SAVE_PATH) -> Dictionary:
	var primary := read_file(path)
	if not primary.is_empty():
		return {"snapshot": primary, "recovered": false, "unreadable": false}
	var backup := read_file(path + ".bak")
	return {
		"snapshot": backup,
		"recovered": not backup.is_empty(),
		"unreadable": backup.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")),
	}


static func write(snapshot: Dictionary, path := SAVE_PATH) -> bool:
	var data := snapshot.duplicate(true)
	data["version"] = VERSION
	if not valid(data):
		return false
	var temporary := path + ".tmp"
	if not write_file(temporary, data):
		return false
	var previous := read_file(path)
	if not previous.is_empty():
		var backup := path + ".bak"
		if not write_file(backup + ".tmp", previous) or replace(backup + ".tmp", backup) != OK:
			return false
	return replace(temporary, path) == OK


static func replace(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


static func write_file(path: String, data: Dictionary) -> bool:
	var contents := FileAccess.open(path, FileAccess.WRITE)
	if contents == null:
		return false
	contents.store_string(JSON.stringify(data))
	contents.flush()
	var success := contents.get_error() == OK
	contents.close()
	return success


static func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_FILE_SIZE:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not valid(json.data):
		return {}
	return json.data


static func amount(value: Variant, lower: float, upper: float, whole := false) -> bool:
	if not (value is float or value is int):
		return false
	var number := float(value)
	return is_finite(number) and number >= lower and number <= upper and (not whole or floorf(number) == number)


static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION or not data.get("online") is bool:
		return false
	for key in ["health", "hunger", "stamina"]:
		if not amount(data.get(key), 0.0, 100.0):
			return false
	if data.health <= 0.0 or not amount(data.get("relay_health"), 0.0, Rules.RELAY_HEALTH):
		return false
	if not amount(data.get("elapsed"), 0.0, 31536000.0) or not amount(data.get("kills"), 0.0, 10000000.0, true):
		return false
	if not amount(data.get("rounds"), 0.0, Rules.MAGAZINE, true) or not amount(data.get("reserve"), 0.0, Rules.MAX_STACK, true):
		return false
	var position: Variant = data.get("position")
	if not position is Array or position.size() != 3:
		return false
	var limit := Rules.MAP_BOUNDARY
	if not amount(position[0], -limit, limit) or not amount(position[1], -2.0, 30.0) or not amount(position[2], -limit, limit):
		return false
	if not amount(data.get("yaw"), -TAU, TAU) or not amount(data.get("pitch"), -PI * 0.5, PI * 0.5):
		return false
	var inventory: Variant = data.get("inventory")
	if not inventory is Dictionary or inventory.size() != Rules.SUPPLIES.size():
		return false
	for item in Rules.SUPPLIES:
		if not amount(inventory.get(item), 0.0, Rules.MAX_STACK, true):
			return false
	return valid_world(data)


static func valid_world(data: Dictionary) -> bool:
	var depleted: Variant = data.get("depleted")
	if not depleted is Dictionary or depleted.size() > 28:
		return false
	for id in depleted:
		if not id is String or id.length() > 20 or not amount(depleted[id], 0.0, 150.0):
			return false
	var patrols: Variant = data.get("cleared_patrols")
	if not patrols is Array or patrols.size() > 5:
		return false
	var seen := {}
	for id in patrols:
		if not amount(id, 0.0, 4.0, true) or seen.has(int(id)):
			return false
		seen[int(id)] = true
	var structures: Variant = data.get("structures")
	if not structures is Array or structures.size() > Rules.MAX_STRUCTURES:
		return false
	seen.clear()
	for piece in structures:
		if not piece is Dictionary or not piece.get("kind") is String or not Rules.PIECES.has(piece.kind):
			return false
		var cell: Variant = piece.get("cell")
		if not cell is Array or cell.size() != 2 or not amount(cell[0], -7, 7, true) or not amount(cell[1], -10, 6, true):
			return false
		var plot := Vector2i(int(cell[0]), int(cell[1]))
		var key := Rules.cell_key(plot, piece.kind)
		if not Rules.cell_allowed(plot) or seen.has(key):
			return false
		if not amount(piece.get("turn"), 0, 3, true) or not amount(piece.get("health"), 0.01, Rules.PIECES[piece.kind].health):
			return false
		if not piece.get("open") is bool or (piece.open and piece.kind != "gate"):
			return false
		seen[key] = true
	return true
