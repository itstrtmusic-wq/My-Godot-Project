extends Node3D

const Rules = preload("res://game/rules.gd")
const Geo = preload("res://game/geometry.gd")
const Audio = preload("res://game/audio.gd")
const SHOT_GAP := 0.17
const RELOAD_TIME := 1.42

var rounds := Rules.MAGAZINE
var reserve := 36
var cooldown := 0.0
var reload_remaining := 0.0
var recoil := 0.0
var flash_time := 0.0
var aiming := false
var first_person: Camera3D
var flash: MeshInstance3D
var emitter: AudioStreamPlayer
var shot_sound: AudioStreamWAV
var reload_sound: AudioStreamWAV
var empty_sound: AudioStreamWAV


func _ready() -> void:
	first_person = get_parent() as Camera3D
	position = Vector3(0.23, -0.26, -0.52)
	scale = Vector3.ONE * 0.82
	make_model()
	emitter = AudioStreamPlayer.new()
	emitter.max_polyphony = 4
	add_child(emitter)
	shot_sound = Audio.tone(0.19, 142.0, 16.0, 0.66, 9331)
	reload_sound = Audio.tone(0.24, 380.0, 9.0, 0.83, 43)
	empty_sound = Audio.tone(0.075, 225.0, 2.0, 0.73, 215)


func make_model() -> void:
	var casing := Geo.material(Color("#3f5759"), 0.0, 0.25)
	var grip := Geo.material(Color("#212b30"))
	var liner := Geo.material(Color("#a77b4e"), 0.0, 0.18)
	var indicator := Geo.material(Color("#7ff7d7"), 1.6)
	var glove := Geo.material(Color("#3a4342"))
	Geo.box(self, Vector3(0, 0, -0.05), Vector3(0.125, 0.17, 0.44), casing, false)
	Geo.box(self, Vector3(0, -0.015, -0.34), Vector3(0.112, 0.117, 0.24), grip, false)
	Geo.box(self, Vector3(0, 0.018, -0.49), Vector3(0.10, 0.082, 0.15), casing, false)
	Geo.box(self, Vector3(0, 0.018, -0.568), Vector3(0.078, 0.065, 0.024), grip, false)
	Geo.box(self, Vector3(0, 0.09, -0.183), Vector3(0.085, 0.038, 0.28), grip, false)
	Geo.box(self, Vector3(0, -0.104, -0.08), Vector3(0.077, 0.114, 0.155), liner, false)
	for z in [-0.15, -0.195, -0.24, -0.285]:
		Geo.box(self, Vector3(0.063, 0.022, z), Vector3(0.007, 0.033, 0.017), grip, false)
	Geo.box(self, Vector3(-0.064, -0.019, -0.038), Vector3(0.010, 0.072, 0.241), grip, false)
	Geo.box(self, Vector3(-0.064, 0.037, -0.105), Vector3(0.009, 0.011, 0.121), indicator, false)
	for z in [-0.26, -0.22, -0.18, -0.14]:
		Geo.box(self, Vector3(0, 0.114, z), Vector3(0.093, 0.017, 0.017), liner, false)
	for z in [-0.05, -0.066, -0.082]:
		Geo.box(self, Vector3(-0.070, -0.019, z), Vector3(0.005, 0.031, 0.003), liner, false)
	for x in [-0.027, 0.027]:
		Geo.box(self, Vector3(x, 0.119, -0.036), Vector3(0.016, 0.055, 0.039), grip, false)
	Geo.box(self, Vector3(0, 0.146, -0.42), Vector3(0.015, 0.032, 0.025), indicator, false)
	var right_hand := Geo.box(self, Vector3(0.039, -0.116, 0.12), Vector3(0.10, 0.10, 0.23), glove, false)
	right_hand.rotation.x = -0.31
	var sleeve := Geo.box(self, Vector3(-0.10, -0.14, -0.087), Vector3(0.103, 0.10, 0.36), glove, false)
	sleeve.rotation = Vector3(-0.32, -0.33, 0.02)
	flash = Geo.sphere(self, Vector3(0, 0.018, -0.66), Vector3(0.24, 0.22, 0.36), indicator, false)
	flash.hide()


func tick(delta: float, motion: float, build_mode: bool, near_wall: bool) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	flash_time = maxf(0.0, flash_time - delta)
	flash.visible = flash_time > 0.0
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining == 0.0:
			var added := mini(Rules.MAGAZINE - rounds, reserve)
			rounds += added
			reserve -= added
			play(reload_sound, -21.0)
	var blend := 1.0 - exp(-14.0 * delta)
	recoil = lerpf(recoil, 0.0, 1.0 - exp(-16.0 * delta))
	var target := Vector3(0, -0.119, -0.47) if aiming else Vector3(0.23, -0.26, -0.52)
	if build_mode or near_wall:
		target = Vector3(0.26, -0.65 if build_mode else -0.41, -0.31)
	var dip := sin(reload_remaining / RELOAD_TIME * PI) * 0.21
	target.y -= dip
	target.z += recoil * 0.045
	position = position.lerp(target, blend)
	rotation.x = lerpf(rotation.x, -dip * 1.8 + recoil * 0.12, blend)
	first_person.rotation.x = recoil * motion * 0.018


func muzzle() -> Vector3:
	return to_global(Vector3(0.0, 0.018, -0.61))


func spend_shot() -> bool:
	if reload_remaining > 0.0 or cooldown > 0.0:
		return false
	if rounds <= 0:
		if not reload():
			play(empty_sound, -18.0)
			cooldown = 0.3
		return false
	rounds -= 1
	cooldown = SHOT_GAP
	recoil = minf(recoil + (0.72 if aiming else 0.98), 1.8)
	flash_time = 0.04
	play(shot_sound, -11.0)
	return true


func reload() -> bool:
	if rounds == Rules.MAGAZINE or reserve <= 0 or reload_remaining > 0.0:
		return false
	reload_remaining = RELOAD_TIME
	play(reload_sound, -18.0)
	return true


func play(clip: AudioStreamWAV, volume: float) -> void:
	emitter.stream = clip
	emitter.volume_db = volume
	emitter.pitch_scale = randf_range(0.96, 1.04)
	emitter.play()
