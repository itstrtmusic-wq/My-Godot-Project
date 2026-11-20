extends SceneTree

const MAIN = preload("res://game/main.tscn")
const Game = preload("res://game/main.gd")
const Rules = preload("res://game/rules.gd")
const Session = preload("res://game/session.gd")
const Checkpoint = preload("res://game/checkpoint.gd")
const Drone = preload("res://game/drone.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func expect(condition: bool, statement: String) -> void:
	checks += 1
	if not condition:
		failures.append(statement)
		printerr("FAIL: " + statement)


func frames(count: int) -> void:
	for index in range(count):
		await physics_frame


func set_pose(session: Session, at: Vector3, toward: Vector3) -> void:
	session.player.position = at
	session.player.velocity = Vector3.ZERO
	var direction := (toward - (at + Vector3.UP * 1.66)).normalized()
	session.set_view(atan2(-direction.x, -direction.z), asin(direction.y))


func look_at(session: Session, toward: Vector3, distance: float) -> CollisionObject3D:
	var eye := session.player.camera.global_position
	return session.ray(eye, eye + (toward - eye).normalized() * distance,
		Rules.SHOT_MASK, [session.player.get_rid()]).get("collider") as CollisionObject3D


func collect(session: Session, ids: Array[String]) -> void:
	for id in ids:
		var at: Vector3 = session.sector.sites[id].at
		var aim := at + Vector3.UP * 0.26
		set_pose(session, at + Vector3(0, 0.045, 1.7), aim)
		await frames(4)
		var target := look_at(session, aim, Rules.INTERACT_REACH)
		expect(target == session.sector.available[id], "Aimed interaction ray reaches " + id)
		session.interact(target)
		expect(not session.sector.available.has(id), "Salvaging depletes " + id)


func run() -> void:
	var game := MAIN.instantiate() as Game
	root.add_child(game)
	await process_frame
	expect(game.screen == "title" and paused, "The game starts at a paused title screen")
	expect(game.checkpoint.snapshot.is_empty(), "The isolated test profile starts with no checkpoint")
	game.handle_command("new", null)
	await frames(20)
	var session := game.session
	expect(game.screen == "play" and not paused and session.player.is_on_floor(), "New deployment is playable on solid terrain")
	expect(Checkpoint.read().snapshot.health == 100, "Starting a run writes a valid checkpoint")

	await collect(session, ["timber/0", "timber/1", "alloy/0", "alloy/1", "alloy/2", "fiber/0", "fiber/1", "rations/0"])
	expect(session.inventory.timber == 14 and session.inventory.alloy == 15 and session.inventory.fiber == 8,
		"Salvage yields reach the field pack")
	game.handle_command("craft", null)
	expect(game.screen == "craft" and paused, "Fabricator pauses live gameplay")
	var reserves := session.carbine.reserve
	game.handle_command("recipe", "cartridge")
	game.handle_command("recipe", "patches")
	expect(session.carbine.reserve == reserves + 18 and session.inventory.alloy == 13,
		"Fabrication produces rounds and charges alloy")
	expect(session.inventory.patches == 2 and session.inventory.fiber == 5,
		"Fabrication produces a trauma patch and charges fiber")
	game.handle_command("back", null)

	session.hurt(44.0)
	session.consume("patches")
	expect(is_equal_approx(session.health, 96.0) and session.inventory.patches == 1,
		"Trauma patches heal without exceeding maximum health")
	session.hunger = 60.0
	var rations: int = session.inventory.rations
	session.consume("rations")
	expect(is_equal_approx(session.hunger, 95.0) and session.inventory.rations == rations - 1,
		"Rations consume inventory and restore food")

	var plot := Vector2i(2, 0)
	var gate_plot := Vector2i(3, 0)
	set_pose(session, Vector3(5.2, 0.05, 3.8), Vector3(5.2, 0.0, 0.0))
	await frames(8)
	expect(not session.place_at("wall", Vector2i(0, -5), 0), "Unsafe or unreachable placement is rejected")
	expect(session.place_at("wall", plot, 0), "A valid wall can be placed")
	expect(not session.place_at("wall", plot, 0), "Occupied plots reject duplicate builds")
	expect(session.place_at("roof", plot, 0), "A canopy can overlap a wall's plot at a different height")
	expect(session.place_at("gate", gate_plot, 0), "An adjacent gate can be placed")
	expect(session.inventory.timber == 1 and session.inventory.alloy == 11,
		"Only successful placements spend materials")
	await frames(4)
	var gate = session.structures[Rules.cell_key(gate_plot, "gate")]
	var wall = session.structures[Rules.cell_key(plot, "wall")]
	session.interact(gate)
	await frames(4)
	expect(gate.gate_open and gate.gate_shape.disabled, "An opened gate has a passable doorway")
	set_pose(session, Rules.cell_position(gate_plot) + Vector3.UP * 0.03, Vector3.ZERO)
	await frames(5)
	session.interact(gate)
	expect(gate.gate_open, "A gate cannot close on the player")
	set_pose(session, Vector3(5.2, 0.05, 3.8), Vector3(5.2, 1.5, 0.0))
	await frames(5)

	var drone: Drone = session.drones.front()
	drone.set_physics_process(false)
	drone.position = Vector3(5.2, 1.5, -4.0)
	var before := session.health
	await frames(3)
	session.on_drone_fire(drone, drone.position, session.player.position + Vector3.UP * 1.4, 11.0)
	expect(is_equal_approx(session.health, before) and is_equal_approx(wall.health, 61.0),
		"Cover shields the player and takes damage")
	session.dismantle(wall)
	await frames(3)
	expect(session.inventory.timber == 3, "Dismantling refunds part of a structure's cost")
	var muzzle_health := drone.health
	var round_count := session.carbine.rounds
	session.shoot()
	expect(session.carbine.rounds == round_count - 1 and drone.health < muzzle_health and session.hit_flash > 0.0,
		"The carbine spends ammunition and damages an exposed target")
	session.shoot()
	expect(session.carbine.rounds == round_count - 1, "The carbine enforces a fire interval")
	await frames(15)
	session.shoot()
	expect(session.kills == 1 and session.cleared_patrols.has(0), "A destroyed scout grants salvage and does not respawn on reload")
	var before_reload := session.carbine.rounds + session.carbine.reserve
	expect(session.carbine.reload(), "The carbine can start a reload with reserve ammunition")
	await frames(95)
	expect(session.carbine.rounds == Rules.MAGAZINE and session.carbine.rounds + session.carbine.reserve == before_reload,
		"Reloading transfers ammunition without duplication")

	expect(game.write_checkpoint(), "Manual checkpoint write succeeds")
	var data := Checkpoint.read().snapshot as Dictionary
	expect(data.inventory.timber == 3 and data.structures.size() == 2 and data.depleted.size() == 8,
		"A checkpoint includes the pack, builds and depleted salvage")
	game.handle_command("continue", null)
	await frames(8)
	session = game.session
	expect(session.structures.size() == 2 and session.cleared_patrols.has(0) and session.inventory.timber == 3,
		"Continuing restores the saved outpost and scout state")
	gate = session.structures[Rules.cell_key(gate_plot, "gate")]
	expect(gate.gate_open and gate.gate_shape.disabled, "An open gate stays open after continuing")

	set_pose(session, Rules.RELAY_POSITION + Vector3(0, 0.04, 3.8), Rules.RELAY_CORE)
	await frames(5)
	var terminal := look_at(session, Rules.RELAY_CORE, Rules.INTERACT_REACH)
	expect(terminal == session.sector.relay, "The relay can be reached from its front access lane")
	session.interact(terminal)
	expect(session.phase == Session.Phase.DEFENSE and session.inventory.fiber == 0, "Installing parts starts the defense")
	expect(not session.can_save() and Checkpoint.read().snapshot.inventory.fiber == 5,
		"Defense keeps an unspent retry checkpoint")
	session.hurt(1000.0)
	expect(game.screen == "lost" and paused, "Fatal damage opens checkpoint recovery")
	game.handle_command("continue", null)
	await frames(5)
	session = game.session
	expect(session.phase == Session.Phase.PREPARING and session.inventory.fiber == 5, "Retry restores the pre-defense checkpoint")

	# Advance intermissions directly, while exercising real spawns, damage signals and transitions.
	var assault_kills := 0
	session.begin_defense()
	for count in Rules.WAVES:
		session.update_round(30.0)
		expect(session.assault_alive == count, "Assault spawns the expected force")
		var hostile := session.drones.back() as Drone
		var integrity := session.relay_health
		session.on_drone_fire(hostile, Rules.RELAY_CORE + Vector3(0, 0.7, -4), Rules.RELAY_CORE, 12.0)
		expect(session.relay_health < integrity, "Exposed relay takes assault damage")
		for attacker: Drone in session.drones.duplicate():
			if attacker.assault:
				attacker.take_damage(500.0)
				assault_kills += 1
		await frames(2)
		expect(session.assault_alive == 0, "Clearing the wave starts the next intermission")
	session.update_round(30.0)
	expect(game.screen == "won" and session.phase == Session.Phase.ONLINE and assault_kills == 13,
		"Clearing three waves secures the relay")
	expect(Checkpoint.read().snapshot.online, "Victory is written to the checkpoint")
	game.handle_command("resume", null)
	expect(game.screen == "play" and not paused, "The sector remains explorable after victory")

	var test_file := "user://smoke-backup.json"
	expect(Checkpoint.write(session.snapshot(), test_file), "The first backup test checkpoint is valid")
	expect(Checkpoint.write(session.snapshot(), test_file), "A second write preserves a recovery copy")
	var corrupted := FileAccess.open(test_file, FileAccess.WRITE)
	corrupted.store_string("{broken")
	corrupted.close()
	var backup := Checkpoint.read(test_file)
	expect(backup.recovered and backup.snapshot.online, "A damaged primary falls back to the last valid backup")
	var bad := session.snapshot()
	bad.inventory.timber = -1
	expect(not Checkpoint.write(bad, test_file), "Invalid save data cannot replace a valid checkpoint")

	var open_ground := Vector3(0, 0.1, 6.0)
	set_pose(session, open_ground, Vector3(0, 2.4, -2.0))
	for scout: Drone in session.drones:
		scout.set_physics_process(false)
	session.spawn_drone(Vector3(0, 2.4, -2.0), false, 1)
	var attacker := session.drones.back() as Drone
	var patrol_start := attacker.position
	var health_at_contact := session.health
	await frames(246)
	expect(attacker.position.distance_to(patrol_start) > 1.0, "A drone actively pursues a visible target")
	expect(session.health < health_at_contact, "Drone windup leads to a live attack against the player")

	# Let the audio mixer release playbacks after the world is freed.
	game.queue_free()
	await process_frame
	await create_timer(0.30).timeout
	print("Survival smoke: %d passed, %d failed." % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
