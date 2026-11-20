extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Pass the output filename after --")
		quit(1)
		return
	var output := FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		printerr("Could not write engine notices.")
		quit(1)
		return

	output.store_line("Godot Engine\n")
	output.store_line(Engine.get_license_text())
	output.store_line("\nBundled third-party components\n")
	for component in Engine.get_copyright_info():
		output.store_line(component.name)
		for part in component.parts:
			for copyright in part.copyright:
				output.store_line("  " + copyright)
			output.store_line("  License: " + part.license)
		output.store_line("")

	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name in names:
		output.store_line("\n" + str(name) + "\n")
		output.store_line(licenses[name])
	output.close()
	quit()
