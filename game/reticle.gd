extends Control

var hit := false
var aim := false
var build := false


func update_reticle(has_hit: bool, aiming: bool, building: bool) -> void:
	if hit == has_hit and aim == aiming and build == building:
		return
	hit = has_hit
	aim = aiming
	build = building
	queue_redraw()


func _draw() -> void:
	var tint := Color("#f5e9cb")
	if hit:
		var impact := Color("#8ff8dc")
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				draw_line(Vector2(x, y) * 4.4, Vector2(x, y) * 11.0, impact, 2.1, true)
		return
	if aim or build:
		draw_circle(Vector2.ZERO, 2.6 if build else 1.7, tint, true, -1.0, true)
		return
	for axis in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(axis * 5.0, axis * 11.0, Color(0, 0, 0, 0.45), 3.0, true)
		draw_line(axis * 5.0, axis * 11.0, tint, 1.3, true)
	draw_circle(Vector2.ZERO, 1.2, tint, true, -1.0, true)
