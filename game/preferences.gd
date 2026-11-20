extends RefCounted

const PATH := "user://cinderline-settings.cfg"
const SETTINGS := {
	"volume": {"title": "Master volume", "min": 0.0, "max": 100.0, "value": 80.0},
	"sensitivity": {"title": "Mouse sensitivity", "min": 20.0, "max": 225.0, "value": 100.0},
	"motion": {"title": "Camera motion", "min": 0.0, "max": 100.0, "value": 75.0},
	"fov": {"title": "Vertical field of view", "min": 60.0, "max": 100.0, "value": 80.0},
}


static func read() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PATH)
	var values := {}
	for id in SETTINGS:
		var setting: Dictionary = SETTINGS[id]
		var candidate: Variant = config.get_value("game", id, setting.value)
		var numeric := candidate is float or candidate is int
		var value := float(candidate) if numeric and is_finite(float(candidate)) else float(setting.value)
		values[id] = clampf(value, setting.min, setting.max)
	return values


static func write(values: Dictionary) -> bool:
	var config := ConfigFile.new()
	for id in SETTINGS:
		config.set_value("game", id, values[id])
	return config.save(PATH) == OK


static func apply(values: Dictionary, player: CharacterBody3D) -> void:
	AudioServer.set_bus_volume_linear(0, float(values.volume) / 100.0)
	player.set("motion_strength", float(values.motion) / 100.0)
	player.set("mouse_sensitivity", float(values.sensitivity) * 0.000022)
	player.set("base_fov", float(values.fov))
	var camera := player.get("camera") as Camera3D
	camera.fov = float(values.fov)
