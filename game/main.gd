extends Node

const Session = preload("res://game/session.gd")
const Interface = preload("res://game/interface.gd")
const Checkpoint = preload("res://game/checkpoint.gd")
const Preferences = preload("res://game/preferences.gd")

var session: Session
var ui: Interface
var screen := "title"
var previous := "title"
var confirmation := ""
var preferences := {}
var checkpoint := {}
var save_message := ""
var refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().min_size = Vector2i(820, 480)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(quit_game)
	preferences = Preferences.read()
	ui = Interface.new()
	add_child(ui)
	ui.command.connect(handle_command)
	get_window().focus_exited.connect(pause_on_focus_loss)
	load_checkpoint()
	return_to_title()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match screen:
			"play":
				open("pause")
			"pause":
				resume()
			"craft", "settings", "controls", "confirm":
				back()
			_:
				return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fabricator") and (screen == "play" or screen == "craft"):
		if screen == "play":
			previous = "play"
			open("craft")
		else:
			back()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if screen != "play":
		return
	refresh -= delta
	if refresh <= 0.0:
		refresh = 0.035
		ui.sync(session)


func pause_on_focus_loss() -> void:
	if screen == "play":
		open("pause")


func create_session() -> void:
	if is_instance_valid(session):
		remove_child(session)
		session.queue_free()
	session = Session.new()
	add_child(session)
	session.checkpoint_requested.connect(write_checkpoint)
	session.run_failed.connect(on_failure)
	session.run_won.connect(on_victory)
	Preferences.apply(preferences, session.player)


func deploy(snapshot: Dictionary = {}) -> void:
	if session.armed:
		create_session()
	session.deploy(snapshot)
	if snapshot.is_empty() and write_checkpoint():
		session.report("Tab Fabricator   ·   B Build   ·   E Salvage")
	resume()


func return_to_title() -> void:
	create_session()
	session.title_view()
	open("title")


func load_checkpoint() -> void:
	checkpoint = Checkpoint.read()
	if checkpoint.recovered:
		save_message = "Recovered the previous checkpoint."
	elif checkpoint.unreadable:
		save_message = "The existing checkpoint could not be read."


func write_checkpoint() -> bool:
	if not session.can_save():
		save_message = "This run cannot be saved right now."
		return false
	if not Checkpoint.write(session.snapshot()):
		save_message = "Checkpoint could not be written."
		session.deny(save_message)
		return false
	checkpoint = Checkpoint.read()
	save_message = ""
	return true


func open(next: String, extra: Dictionary = {}) -> void:
	screen = next
	var can_continue: bool = not checkpoint.snapshot.is_empty()
	var data := {"values": preferences, "can_save": session.can_save(), "has_save": can_continue}
	data.merge(extra, true)
	if screen == "title" and not save_message.is_empty():
		data["message"] = save_message
	get_tree().paused = screen != "play"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
	ui.show_screen(screen, data)
	if screen == "craft":
		ui.update_fabricator(session)


func resume() -> void:
	session.require_release = Input.is_action_pressed("fire")
	open("play")
	ui.sync(session)


func back() -> void:
	var settings_failed := screen == "settings" and not Preferences.write(preferences)
	if previous == "play":
		resume()
		if settings_failed:
			session.deny("Settings could not be saved.")
	else:
		open(previous)
		if settings_failed:
			ui.message("Settings could not be saved.")


func handle_command(action: String, data: Variant) -> void:
	match action:
		"new":
			if checkpoint.snapshot.is_empty():
				deploy()
			else:
				previous = "title"
				confirmation = "new"
				open("confirm", {"title": "Start a new deployment?",
					"detail": "This replaces the current checkpoint.", "confirm": "Start new deployment"})
		"continue":
			if not checkpoint.snapshot.is_empty():
				deploy(checkpoint.snapshot)
		"resume":
			resume()
		"title":
			return_to_title()
		"quit":
			quit_game()
		"back":
			back()
		"craft", "settings", "controls":
			previous = screen
			open(action)
		"recipe":
			session.craft(str(data))
			ui.update_fabricator(session)
			ui.message(session.notice)
		"preference":
			preferences[data[0]] = float(data[1])
			Preferences.apply(preferences, session.player)
		"save":
			ui.message("Checkpoint saved." if write_checkpoint() else save_message)
		"save_title":
			if write_checkpoint():
				return_to_title()
			else:
				ui.message(save_message)
		"leave_defense":
			previous = "pause"
			confirmation = "title"
			open("confirm", {"title": "Abandon the defense?",
				"detail": "You can retry from the checkpoint before the assault.", "confirm": "Return to title"})
		"confirm":
			if confirmation == "new":
				deploy()
			elif confirmation == "title":
				return_to_title()
			elif confirmation == "quit":
				get_tree().quit()


func quit_game() -> void:
	if session.can_save() and not write_checkpoint():
		if screen != "confirm":
			previous = screen
		confirmation = "quit"
		open("confirm", {"title": "Quit without saving?",
			"detail": save_message, "confirm": "Quit game"})
		return
	get_tree().quit()


func on_failure(reason: String) -> void:
	open("lost", {"reason": reason})


func on_victory() -> void:
	var minutes := floori(session.elapsed / 60.0)
	var seconds := int(session.elapsed) % 60
	var summary := "%d drones disabled   ·   %d:%02d in sector" % [session.kills, minutes, seconds]
	open("won", {"summary": summary, "message": "Checkpoint saved." if save_message.is_empty() else save_message})
