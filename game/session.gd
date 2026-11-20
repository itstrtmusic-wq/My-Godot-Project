extends Node3D

signal checkpoint_requested()
signal run_failed(reason: String)
signal run_won()

const Rules = preload("res://game/rules.gd")
const Geo = preload("res://game/geometry.gd")
const Audio = preload("res://game/audio.gd")
const Sector = preload("res://game/sector.gd")
const Controller = preload("res://player/first_person_player.gd")
const PLAYER_SCENE = preload("res://player/first_person_player.tscn")
const Carbine = preload("res://game/carbine.gd")
const Structure = preload("res://game/structure.gd")
const Drone = preload("res://game/drone.gd")
const PATROLS := [Vector2(-27, -9), Vector2(24, -21), Vector2(33, 16), Vector2(-33, 19), Vector2(-9, -44)]
const INTERMISSION := 11.0

enum Phase { PREPARING, DEFENSE, ONLINE, DOWN }

var phase := Phase.PREPARING
var player: Controller
var sector: Sector
var carbine: Carbine
var ambience: AudioStreamPlayer
var cue: AudioStreamPlayer
var inventory := {"timber": 0, "alloy": 0, "fiber": 0, "rations": 1, "patches": 1}
var health := 100.0
var hunger := 88.0
var stamina := 100.0
var relay_health := Rules.RELAY_HEALTH
var sprint_locked := false
var elapsed := 0.0
var autosave := 45.0
var kills := 0
var cleared_patrols: Array[int] = []
var armed := false
var drones: Array[Drone] = []
var wave := 0
var wave_timer := 0.0
var assault_alive := 0
var structures := {}
var building := false
var build_piece := 0
var build_turn := 0
var build_cell := Vector2i.ZERO
var build_valid := false
var build_reason := ""
var build_preview: Structure
var focus: CollisionObject3D
var notice := ""
var notice_time := 0.0
var hurt_flash := 0.0
var hit_flash := 0.0
var require_release := false
var shot_glow := Geo.material(Color("#a7ffe6"), 2.4)
var drone_glow := Geo.material(Color("#ff9962"), 2.0)
var impact_glow := Geo.material(Color("#eee4bc"), 1.5)
var good_ghost := ghost_surface(Color(0.30, 0.87, 0.72, 0.40))
var bad_ghost := ghost_surface(Color(0.96, 0.29, 0.24, 0.36))
var progress_sound: AudioStreamWAV
var deny_sound: AudioStreamWAV
var enemy_sound: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	sector = Sector.new()
	add_child(sector)
	player = PLAYER_SCENE.instantiate() as Controller
	player.position = Rules.SPAWN
	player.collision_layer = Rules.PLAYER
	player.collision_mask = Rules.SOLIDS | Rules.DRONE
	add_child(player)
	carbine = Carbine.new()
	player.camera.add_child(carbine)
	ambience = AudioStreamPlayer.new()
	ambience.stream = Audio.breeze()
	ambience.volume_db = -17.0
	add_child(ambience)
	cue = AudioStreamPlayer.new()
	cue.max_polyphony = 3
	add_child(cue)
	progress_sound = Audio.tone(0.24, 590.0, -1.2, 0.13, 3914)
	deny_sound = Audio.tone(0.14, 156.0, 4.0, 0.32, 211)
	enemy_sound = Audio.tone(0.20, 240.0, 7.0, 0.48, 11855)


func deploy(saved: Dictionary) -> void:
	carbine.show()
	if saved.is_empty():
		player.position = Rules.SPAWN
		set_view(0.0, 0.0)
	else:
		restore(saved)
	for index in range(PATROLS.size()):
		if not cleared_patrols.has(index):
			var point: Vector2 = PATROLS[index]
			spawn_drone(sector.at_ground(point.x, point.y) + Vector3.UP * 2.65, false, index % 2, index)
	armed = true
	ambience.play()


func title_view() -> void:
	carbine.hide()
	player.position = Vector3(-8, 3.5, 16.2)
	set_view(-0.16, -0.04)


func set_view(yaw: float, pitch: float) -> void:
	player.rotation.y = yaw
	player.pitch = pitch
	player.view.rotation.x = pitch


func _physics_process(delta: float) -> void:
	if not armed or phase == Phase.DOWN:
		return
	update_survival(delta)
	if phase == Phase.DOWN:
		return
	update_round(delta)
	if get_tree().paused:
		return
	sector.replenish(delta, player.position)

	if not player.has_control():
		carbine.aiming = false
		player.aim_blend = 0.0
		carbine.tick(delta, player.motion_strength, building, false)
		return
	update_actions()


func update_survival(delta: float) -> void:
	elapsed += delta
	notice_time = maxf(0.0, notice_time - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	hunger = maxf(0.0, hunger - delta * (0.12 if player.sprinting else 0.078))
	if hunger <= 0.0:
		hurt(delta * 1.4, false)
	var rate := 23.0 if player.sprinting else -21.0
	stamina = clampf(stamina - rate * delta, 0.0, 100.0)
	if stamina <= 0.01:
		sprint_locked = true
	elif stamina >= 28.0 and not Input.is_action_pressed("sprint"):
		sprint_locked = false
	player.sprint_allowed = not sprint_locked and not carbine.aiming and not building
	if player.position.y < -8.0:
		fail("You fell outside the sector.")
	if can_save():
		autosave -= delta
		if autosave <= 0.0:
			autosave = 45.0
			checkpoint_requested.emit()


func update_actions() -> void:
	var delta := get_physics_process_delta_time()
	if Input.is_action_just_pressed("toggle_build"):
		toggle_build()
	var pressed := Input.is_action_pressed("fire")
	if not pressed:
		require_release = false
	if building:
		for index in range(Rules.BUILD_ORDER.size()):
			if Input.is_action_just_pressed("build_%d" % (index + 1)):
				build_piece = index
				refresh_preview()
		if Input.is_action_just_pressed("reload"):
			build_turn = (build_turn + 1) % 4
		update_build_cursor()
	elif Input.is_action_just_pressed("reload"):
		carbine.reload()

	carbine.aiming = not building and Input.is_action_pressed("aim") and carbine.reload_remaining <= 0.0
	player.aim_blend = 1.0 if carbine.aiming else 0.0
	player.speed_scale = 0.68 if carbine.aiming else 1.0
	var from := player.camera.global_position
	var direction := -player.camera.global_basis.z
	var sight := ray(from, from + direction * Rules.INTERACT_REACH, Rules.SHOT_MASK, [player.get_rid()])
	focus = sight.get("collider") as CollisionObject3D
	var near_wall := not sight.is_empty() and not focus is Drone and from.distance_squared_to(sight.position) < 0.90
	carbine.tick(delta, player.motion_strength, building, near_wall)
	if building:
		if Input.is_action_just_pressed("dismantle"):
			dismantle(focus as Structure)
		if not require_release and Input.is_action_just_pressed("fire"):
			if build_valid:
				place_at(Rules.BUILD_ORDER[build_piece], build_cell, build_turn)
			else:
				deny(build_reason)
	elif pressed and not require_release:
		if near_wall and Input.is_action_just_pressed("fire"):
			deny("Step back from the obstruction.")
		elif not near_wall:
			shoot()
	if Input.is_action_just_pressed("interact"):
		interact(focus)
	if Input.is_action_just_pressed("use_patch"):
		consume("patches")
	if Input.is_action_just_pressed("eat"):
		consume("rations")


func ray(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	return Rules.cast(get_world_3d().direct_space_state, from, to, mask, exclude)


func can_save() -> bool:
	return armed and (phase == Phase.PREPARING or phase == Phase.ONLINE) and health > 0.0


func add_supplies(items: Dictionary) -> void:
	for item in items:
		inventory[item] = mini(Rules.MAX_STACK, inventory[item] + items[item])


func pay(cost: Dictionary) -> bool:
	if not Rules.afford(inventory, cost):
		return false
	for item in cost:
		inventory[item] -= cost[item]
	return true


func craft(recipe: String) -> void:
	if not Rules.RECIPES.has(recipe):
		return
	if (recipe == "cartridge" and carbine.reserve > Rules.MAX_STACK - 18) or (recipe == "patches" and inventory.patches >= Rules.MAX_STACK):
		deny("You are carrying the maximum.")
		return
	var entry: Dictionary = Rules.RECIPES[recipe]
	if not pay(entry.cost):
		deny("Requires " + Rules.describe(entry.cost))
		return
	if recipe == "cartridge":
		carbine.reserve += 18
	else:
		add_supplies({"patches": 1})
	report(entry.title + " fabricated.", true)


func consume(item: String) -> void:
	var patch := item == "patches"
	if not patch and item != "rations":
		return
	var current := health if patch else hunger
	if current >= 99.9:
		deny("Health is full." if patch else "You are already fed.")
		return
	if inventory[item] <= 0:
		deny("No " + Rules.LABELS[item].to_lower() + " remaining.")
		return
	inventory[item] -= 1
	if patch:
		health = minf(100.0, health + 40.0)
	else:
		hunger = minf(100.0, hunger + 35.0)
	report("Trauma patch applied." if patch else "Ration eaten.", true)


func interact(target: CollisionObject3D) -> void:
	if not is_instance_valid(target):
		return
	if target.has_meta("supply"):
		var items := sector.harvest(str(target.get_meta("supply")))
		if not items.is_empty():
			report("Recovered " + Rules.describe(items), true)
			add_supplies(items)
		return
	if target == sector.relay:
		if phase == Phase.PREPARING:
			begin_defense()
		elif phase == Phase.DEFENSE and relay_health < Rules.RELAY_HEALTH - 5.0:
			if pay(Rules.REPAIR_COST):
				relay_health = minf(Rules.RELAY_HEALTH, relay_health + 36.0)
				report("Relay integrity restored.", true)
			else:
				deny("Requires " + Rules.describe(Rules.REPAIR_COST))
		return
	var piece := target as Structure
	if piece != null and piece.kind == "gate":
		if piece.gate_open and not piece.may_close(get_world_3d().direct_space_state):
			deny("Gate is obstructed.")
			return
		piece.set_open(not piece.gate_open)
		report("Gate opened." if piece.gate_open else "Gate closed.", true)


func focus_text() -> String:
	if not is_instance_valid(focus):
		return ""
	if focus.has_meta("supply"):
		var id := str(focus.get_meta("supply"))
		var data: Dictionary = sector.sites[id]
		return "E   Salvage %s  ·  %s" % [str(data.title).to_lower(), Rules.describe(data.yields)]
	if focus == sector.relay:
		match phase:
			Phase.PREPARING:
				return "E   Install parts and start defense" if Rules.afford(inventory, Rules.RELAY_COST) else "Relay parts required  ·  " + Rules.describe(Rules.RELAY_COST)
			Phase.DEFENSE:
				return "E   Repair relay  ·  2 Alloy" if relay_health < Rules.RELAY_HEALTH - 5.0 else "Relay integrity stable"
			Phase.ONLINE:
				return "Relay transmitting"
	var piece := focus as Structure
	if piece != null:
		if piece.kind == "gate":
			return "E   Close gate" if piece.gate_open else "E   Open gate"
		if building:
			return "X   Dismantle %s" % str(Rules.PIECES[piece.kind].title).to_lower()
	return ""


func toggle_build() -> void:
	building = not building
	require_release = Input.is_action_pressed("fire")
	if building:
		refresh_preview()
	elif is_instance_valid(build_preview):
		build_preview.hide()


func refresh_preview() -> void:
	if is_instance_valid(build_preview):
		remove_child(build_preview)
		build_preview.queue_free()
	build_preview = Structure.new()
	build_preview.setup(Rules.BUILD_ORDER[build_piece], build_cell, build_turn, true)
	add_child(build_preview)
	build_preview.hide()


func update_build_cursor() -> void:
	var from := player.camera.global_position
	var to := from - player.camera.global_basis.z * Rules.BUILD_REACH
	var surface := ray(from, to, Rules.SOLIDS, [player.get_rid()])
	if surface.is_empty() or surface.collider != sector.ground:
		build_valid = false
		build_reason = "Aim at nearby ground in the relay clearing."
		build_preview.hide()
		return
	var at: Vector3 = surface.position
	build_cell = Vector2i(roundi(at.x / Rules.CELL_SIZE), roundi(at.z / Rules.CELL_SIZE))
	build_reason = check_placement(Rules.BUILD_ORDER[build_piece], build_cell, build_turn)
	build_valid = build_reason.is_empty()
	build_preview.position = Rules.cell_position(build_cell)
	build_preview.rotation.y = build_turn * PI * 0.5
	build_preview.tint_preview(good_ghost if build_valid else bad_ghost)
	build_preview.show()


func check_placement(kind: String, cell: Vector2i, turn: int) -> String:
	var at := Rules.cell_position(cell)
	var delta := Vector2(at.x - player.position.x, at.z - player.position.z)
	if delta.length() > Rules.BUILD_REACH:
		return "Move closer to the placement."
	if not Rules.cell_allowed(cell):
		return "Build in the relay clearing, outside the access lanes."
	if structures.size() >= Rules.MAX_STRUCTURES:
		return "The clearing is at its structure limit."
	if structures.has(Rules.cell_key(cell, kind)) or sector.reserved_supply_space(at, 2.25):
		return "That plot is occupied."
	if not Structure.fits(get_world_3d().direct_space_state, kind, cell, turn):
		return "The piece would overlap something."
	if not Rules.afford(inventory, Rules.PIECES[kind].cost):
		return "Requires " + Rules.describe(Rules.PIECES[kind].cost)
	return ""


func place_at(kind: String, cell: Vector2i, turn: int) -> bool:
	if not Rules.PIECES.has(kind) or turn < 0 or turn > 3:
		return false
	var blocked := check_placement(kind, cell, turn)
	if not blocked.is_empty():
		deny(blocked)
		return false
	if not pay(Rules.PIECES[kind].cost):
		return false
	spawn_structure(kind, cell, turn)
	report(Rules.PIECES[kind].title + " placed.", true)
	return true


func spawn_structure(kind: String, cell: Vector2i, turn: int) -> Structure:
	var piece := Structure.new()
	piece.setup(kind, cell, turn)
	add_child(piece)
	structures[Rules.cell_key(cell, kind)] = piece
	return piece


func dismantle(piece: Structure) -> void:
	if not is_instance_valid(piece) or piece.is_preview:
		return
	var cost: Dictionary = Rules.PIECES[piece.kind].cost
	var refund := {}
	for item in cost:
		refund[item] = floori(float(cost[item]) * 0.5)
	add_supplies(refund)
	destroy_structure(piece)
	report("Dismantled  ·  Recovered " + Rules.describe(refund), true)


func destroy_structure(piece: Structure) -> void:
	structures.erase(Rules.cell_key(piece.cell, piece.kind))
	remove_child(piece)
	piece.queue_free()


func shoot() -> void:
	if not carbine.spend_shot():
		return
	var from := player.camera.global_position
	var basis := player.camera.global_basis
	var cone := 0.005 if carbine.aiming else (0.025 if player.sprinting else 0.013)
	var direction := (-basis.z + basis.x * randf_range(-cone, cone) + basis.y * randf_range(-cone, cone)).normalized()
	var to := from + direction * 95.0
	var impact := ray(from, to, Rules.SHOT_MASK, [player.get_rid()])
	if not impact.is_empty():
		to = impact.position
		var drone := impact.collider as Drone
		if drone != null:
			hit_flash = 0.17
			drone.take_damage(26.0)
		else:
			spark(to)
	trace(carbine.muzzle(), to, shot_glow)


func hurt(amount: float, flash := true) -> void:
	if phase == Phase.DOWN:
		return
	health = maxf(0.0, health - amount)
	if flash:
		hurt_flash = 0.27
	if health <= 0.0:
		fail("You went down." if hunger > 0.0 else "You ran out of food.")


func fail(reason: String) -> void:
	if phase != Phase.DOWN:
		phase = Phase.DOWN
		run_failed.emit(reason)


func begin_defense() -> void:
	if phase != Phase.PREPARING:
		return
	if not Rules.afford(inventory, Rules.RELAY_COST):
		deny("Requires " + Rules.describe(Rules.RELAY_COST))
		return
	checkpoint_requested.emit()
	pay(Rules.RELAY_COST)
	phase = Phase.DEFENSE
	wave = 0
	wave_timer = 12.0
	sector.set_relay_active(true)
	report("Uplink booting. Defend the relay.", true)


func update_round(delta: float) -> void:
	if phase != Phase.DEFENSE or assault_alive > 0:
		return
	wave_timer = maxf(0.0, wave_timer - delta)
	if wave_timer > 0.0:
		return
	if wave >= Rules.WAVES.size():
		phase = Phase.ONLINE
		report("Uplink established.", true)
		checkpoint_requested.emit()
		run_won.emit()
		return
	wave += 1
	var count: int = Rules.WAVES[wave - 1]
	for index in range(count):
		var angle := PI * (0.5 + wave * 0.58) + (float(index) - (count - 1) * 0.5) * 0.49
		var radius := 21.0 + index % 3 * 2.4
		var point := Rules.RELAY_POSITION + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		spawn_drone(sector.at_ground(point.x, point.z) + Vector3.UP * (2.3 + index % 3 * 0.46), true, wave - 1)
		assault_alive += 1
	report("Wave %d incoming." % wave, true)


func spawn_drone(at: Vector3, is_assault: bool, tier: int, id := -1) -> void:
	var drone := Drone.new()
	drone.setup(at, player, sector.relay, is_assault, tier, id)
	drone.fired.connect(on_drone_fire)
	drone.downed.connect(on_drone_down)
	add_child(drone)
	drones.append(drone)


func on_drone_fire(drone: Drone, from: Vector3, locked: Vector3, amount: float) -> void:
	if phase == Phase.DOWN:
		return
	var to := locked + (locked - from).normalized() * 0.65
	var impact := ray(from, to, Rules.SOLIDS | Rules.PLAYER, [drone.get_rid()])
	if not impact.is_empty():
		to = impact.position
		spark(to)
		if impact.collider == player:
			hurt(amount)
		elif impact.collider == sector.relay and phase == Phase.DEFENSE and drone.assault:
			relay_health = maxf(0.0, relay_health - amount)
			if relay_health <= 0.0:
				fail("The relay was destroyed.")
		elif impact.collider is Structure:
			var piece := impact.collider as Structure
			piece.health = maxf(0.0, piece.health - amount)
			if piece.health <= 0.0:
				destroy_structure(piece)
				report("A structure was destroyed.")
	trace(from, to, drone_glow)
	var sound := AudioStreamPlayer3D.new()
	sound.position = from
	sound.stream = enemy_sound
	sound.volume_db = -15.0
	sound.max_distance = 35.0
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func on_drone_down(drone: Drone) -> void:
	kills += 1
	if drone.assault:
		assault_alive -= 1
		if assault_alive == 0:
			wave_timer = 1.5 if wave == Rules.WAVES.size() else INTERMISSION
	elif drone.patrol_id >= 0:
		cleared_patrols.append(drone.patrol_id)
	spark(drone.position, 0.40)
	add_supplies({"alloy": 1})
	carbine.reserve = mini(Rules.MAX_STACK, carbine.reserve + 3)
	report("Drone disabled  ·  +1 Alloy / +3 rounds", true)
	drones.erase(drone)
	drone.collision_layer = 0
	drone.hide()
	drone.queue_free()


func trace(from: Vector3, to: Vector3, material: Material) -> void:
	var effect := Geo.beam(self, from, to, 0.023, material, false)
	var cleanup := create_tween()
	cleanup.tween_interval(0.06)
	cleanup.tween_callback(effect.queue_free)


func spark(at: Vector3, size := 0.14) -> void:
	var effect := Geo.sphere(self, at, Vector3.ONE * size, impact_glow, false)
	var animation := create_tween()
	animation.tween_property(effect, "scale", Vector3.ONE * size * 0.12, 0.16)
	animation.tween_callback(effect.queue_free)


func report(text: String, sound := false) -> void:
	notice = text
	notice_time = 3.1
	if sound:
		play_cue(progress_sound, -21.0)


func deny(text: String) -> void:
	report(text)
	play_cue(deny_sound, -19.0)


func play_cue(sound: AudioStreamWAV, volume: float) -> void:
	cue.stream = sound
	cue.volume_db = volume
	cue.play()


func snapshot() -> Dictionary:
	var pieces := []
	for piece: Structure in structures.values():
		pieces.append({"kind": piece.kind, "cell": [piece.cell.x, piece.cell.y], "turn": piece.turn,
				"health": piece.health, "open": piece.gate_open})
	return {
		"inventory": inventory.duplicate(), "health": health, "hunger": hunger, "stamina": stamina,
		"rounds": carbine.rounds, "reserve": carbine.reserve, "online": phase == Phase.ONLINE,
		"relay_health": relay_health, "position": [player.position.x, player.position.y, player.position.z],
		"yaw": wrapf(player.rotation.y, -PI, PI), "pitch": player.pitch,
		"elapsed": elapsed, "kills": kills, "cleared_patrols": cleared_patrols.duplicate(),
		"depleted": sector.depleted.duplicate(), "structures": pieces,
	}


func restore(data: Dictionary) -> void:
	for item in Rules.SUPPLIES:
		inventory[item] = int(data.inventory[item])
	health = float(data.health)
	hunger = float(data.hunger)
	stamina = float(data.stamina)
	relay_health = float(data.relay_health)
	elapsed = float(data.elapsed)
	kills = int(data.kills)
	carbine.rounds = int(data.rounds)
	carbine.reserve = int(data.reserve)
	player.position = Vector3(float(data.position[0]), float(data.position[1]), float(data.position[2]))
	set_view(float(data.yaw), float(data.pitch))
	for id in data.cleared_patrols:
		cleared_patrols.append(int(id))
	for stored in data.structures:
		var plot := Vector2i(int(stored.cell[0]), int(stored.cell[1]))
		var piece := spawn_structure(stored.kind, plot, int(stored.turn))
		piece.health = float(stored.health)
		piece.set_open(stored.open)
	sector.restore_supplies(data.depleted)
	if data.online:
		phase = Phase.ONLINE
		sector.set_relay_active(true)


static func ghost_surface(color: Color) -> StandardMaterial3D:
	var surface := Geo.material(color)
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return surface
