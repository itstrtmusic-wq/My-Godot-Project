extends CanvasLayer

signal command(action: String, data: Variant)

const Rules = preload("res://game/rules.gd")
const Session = preload("res://game/session.gd")
const Preferences = preload("res://game/preferences.gd")
const Reticle = preload("res://game/reticle.gd")
const shade = preload("res://game/overlay.gdshader")

const INK := Color("#f2ebd7")
const MUTED := Color("#a7b9b5")
const AMBER := Color("#f3c780")
const MINT := Color("#8be6c9")
const ALERT := Color("#ff9e8a")
const PANEL := Color(0.039, 0.074, 0.085, 0.93)
const EDGE := Color("#415450")

var root: Control
var hud: Control
var menu: Control
var reticle: Reticle
var damage_shade: ShaderMaterial
var objective_tag: Label
var objective_title: Label
var objective_detail: Label
var relay_direction: Label
var pack: Label
var vitality := {}
var ammo: Label
var ammo_state: Label
var interact_box: PanelContainer
var interact_label: Label
var build_box: PanelContainer
var build_title: Label
var build_reason: Label
var notice_box: PanelContainer
var notice_label: Label
var menu_message: Label
var craft_inventory: Label
var recipe_buttons := {}


func _ready() -> void:
	root = Control.new()
	root.theme = make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	make_hud()


func make_hud() -> void:
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var damage_overlay := backdrop(hud, 0.0, false, true)
	damage_shade = damage_overlay.material as ShaderMaterial

	var mission := panel_at(hud, Vector2.ZERO, Rect2(24, 24, 355, 112))
	var mission_rows := column(mission, 4)
	objective_tag = label(mission_rows, "", 14, AMBER)
	objective_title = label(mission_rows, "", 22)
	objective_detail = label(mission_rows, "", 16, MUTED)
	objective_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var bearing := panel_at(hud, Vector2(0.5, 0), Rect2(-99, 25, 198, 42))
	relay_direction = label(bearing, "", 16, MINT)
	relay_direction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var field_pack := panel_at(hud, Vector2(1, 0), Rect2(-243, 24, 219, 131))
	var pack_rows := column(field_pack, 6)
	label(pack_rows, "FIELD PACK  /  TAB", 14, AMBER)
	pack = label(pack_rows, "", 16)
	pack.add_theme_constant_override("line_spacing", 5)

	var vitals := panel_at(hud, Vector2(0, 1), Rect2(24, -158, 253, 134))
	var vital_rows := column(vitals, 6)
	for data in [["Health", MINT], ["Food", AMBER], ["Stamina", Color("#9cbfdf")]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		vital_rows.add_child(row)
		var caption := label(row, data[0], 14)
		caption.custom_minimum_size.x = 57
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(94, 6)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", flat(Color("#243a3e"), Color.TRANSPARENT, 2))
		bar.add_theme_stylebox_override("fill", flat(data[1], Color.TRANSPARENT, 2))
		row.add_child(bar)
		var value := label(row, "", 14, data[1])
		value.custom_minimum_size.x = 28
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vitality[data[0]] = [bar, value]
	label(vital_rows, "F Ration   ·   V Trauma patch", 13, MUTED)

	var loadout := panel_at(hud, Vector2.ONE, Rect2(-239, -128, 215, 104))
	var loadout_rows := column(loadout, 2)
	label(loadout_rows, "PULSE CARBINE", 14, AMBER)
	ammo = label(loadout_rows, "", 30)
	ammo_state = label(loadout_rows, "", 13, MUTED)

	reticle = Reticle.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin(hud, reticle, Vector2(0.5, 0.5), Rect2(0, 0, 0, 0))
	interact_box = panel_at(hud, Vector2(0.5, 0.5), Rect2(-251, 43, 502, 34))
	interact_label = label(interact_box, "", 16)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	build_box = panel_at(hud, Vector2(0.5, 1), Rect2(-305, -165, 610, 140))
	var build_rows := column(build_box, 3)
	label(build_rows, "1  Wall     2  Gate     3  Canopy", 14, MUTED)
	build_title = label(build_rows, "", 22, AMBER)
	build_reason = label(build_rows, "", 15, MINT)
	label(build_rows, "LMB Place   ·   R Rotate   ·   X Dismantle   ·   B Exit", 14, MUTED)
	notice_box = panel_at(hud, Vector2(0.5, 0.5), Rect2(-285, 110, 570, 36))
	notice_label = label(notice_box, "", 16, MINT)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.hide()


func sync(session: Session) -> void:
	if not hud.visible:
		return
	var supplies := session.inventory
	match session.phase:
		Session.Phase.PREPARING:
			objective_tag.text = "RELAY OFFLINE"
			objective_title.text = "Restore the uplink" if Rules.afford(supplies, Rules.RELAY_COST) else "Recover relay parts"
			objective_detail.text = ("Install at Relay 04 when ready." if Rules.afford(supplies, Rules.RELAY_COST)
				else "Alloy %d / %d   ·   Fiber %d / %d" % [supplies.alloy, Rules.RELAY_COST.alloy, supplies.fiber, Rules.RELAY_COST.fiber])
		Session.Phase.DEFENSE:
			objective_tag.text = "RELAY INTEGRITY   %d%%" % ceili(100.0 * session.relay_health / Rules.RELAY_HEALTH)
			objective_title.text = "Defend the uplink"
			if session.assault_alive > 0:
				objective_detail.text = "Wave %d / %d   ·   %d remaining" % [session.wave, Rules.WAVES.size(), session.assault_alive]
			elif session.wave == Rules.WAVES.size():
				objective_detail.text = "Drone signal lost. Uplink syncing."
			else:
				objective_detail.text = "Wave %d in %d s   ·   R Reload" % [session.wave + 1, ceili(session.wave_timer)]
		Session.Phase.ONLINE:
			objective_tag.text = "RELAY ONLINE"
			objective_title.text = "Uplink secured"
			objective_detail.text = "Explore the valley or return to title."
	var player := session.player
	var offset := Rules.RELAY_POSITION - player.position
	var relative := player.global_basis.inverse() * offset
	var angle := rad_to_deg(atan2(relative.x, -relative.z))
	var bearing := "↑" if absf(angle) <= 12.0 else ("‹" if angle < 0.0 else "›")
	relay_direction.text = "%s   RELAY   %d m" % [bearing, roundi(Vector2(offset.x, offset.z).length())]

	pack.text = "Timber %d    Alloy %d\nFiber %d    Rations %d\nPatches %d" % [
		supplies.timber, supplies.alloy, supplies.fiber, supplies.rations, supplies.patches,
	]
	set_vital("Health", session.health)
	set_vital("Food", session.hunger)
	set_vital("Stamina", session.stamina)
	ammo.text = "%02d  /  %02d" % [session.carbine.rounds, session.carbine.reserve]
	if session.carbine.reload_remaining > 0.0:
		ammo_state.text = "RELOADING"
	else:
		ammo_state.text = "R Reload   ·   B Build"
	var contextual := session.focus_text()
	interact_label.text = contextual
	interact_box.visible = not contextual.is_empty()
	notice_box.visible = session.notice_time > 0.0
	notice_label.text = session.notice
	build_box.visible = session.building
	if session.building:
		var piece: Dictionary = Rules.PIECES[Rules.BUILD_ORDER[session.build_piece]]
		build_title.text = piece.title + "   /   " + Rules.describe(piece.cost)
		build_reason.text = "Ready to place" if session.build_valid else session.build_reason
		build_reason.modulate = MINT if session.build_valid else ALERT
	reticle.update_reticle(session.hit_flash > 0.0, session.carbine.aiming, session.building)
	damage_shade.set_shader_parameter("strength", minf(0.61, session.hurt_flash * 2.2))


func set_vital(id: String, amount: float) -> void:
	var bar: ProgressBar = vitality[id][0]
	var text: Label = vitality[id][1]
	bar.value = amount
	text.text = "%d" % ceili(amount)


func show_screen(screen: String, data: Dictionary = {}) -> void:
	if is_instance_valid(menu):
		root.remove_child(menu)
		menu.queue_free()
	hud.visible = screen == "play"
	if screen == "play":
		return
	menu = Control.new()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop(menu, 0.67, screen == "title")
	recipe_buttons.clear()
	var stack: VBoxContainer
	if screen == "title":
		stack = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 12)
		pin(menu, stack, Vector2(0, 0.5), Rect2(73, -228, 520, 470))
		var title := label(stack, "CINDERLINE", 70)
		var display_font := FontVariation.new()
		display_font.base_font = ThemeDB.fallback_font
		display_font.variation_embolden = 0.6
		display_font.spacing_glyph = 2
		title.add_theme_font_override("font", display_font)
		var summary := label(stack, "Scavenge the valley. Fortify the relay.\nSurvive the drone assault.", 22, MUTED)
		summary.add_theme_constant_override("line_spacing", 6)
		spacer(stack, 16)
		var buttons := column(stack, 8)
		buttons.custom_minimum_size.x = 293
		buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var continue_button := action_button(buttons, "Continue deployment", "continue", null, true)
		continue_button.disabled = not bool(data.get("has_save", false))
		var start := action_button(buttons, "New deployment", "new", null, continue_button.disabled)
		action_button(buttons, "Settings", "settings")
		action_button(buttons, "Controls", "controls")
		action_button(buttons, "Quit game", "quit")
		menu_message = label(stack, str(data.get("message", "")), 15, AMBER)
		(continue_button if not continue_button.disabled else start).grab_focus()
		return

	var widths := {"pause": 470.0, "craft": 650.0, "settings": 590.0, "controls": 565.0, "lost": 490.0, "won": 490.0, "confirm": 490.0}
	var widths_x := float(widths.get(screen, 490.0))
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = widths_x
	panel.add_theme_stylebox_override("panel", flat(PANEL, EDGE, 8, 26))
	center.add_child(panel)
	stack = column(panel, 12)
	var focus: Button
	match screen:
		"pause":
			label(stack, "Paused", 36)
			focus = action_button(stack, "Resume", "resume", null, true)
			action_button(stack, "Fabricator  [Tab]", "craft")
			action_button(stack, "Settings", "settings")
			action_button(stack, "Controls", "controls")
			if bool(data.get("can_save", false)):
				action_button(stack, "Save checkpoint", "save")
				action_button(stack, "Save and return to title", "save_title")
			else:
				action_button(stack, "Abandon defense", "leave_defense")
				label(stack, "Your checkpoint is from before the defense.", 15, MUTED)
		"craft":
			label(stack, "Fabricator", 36)
			craft_inventory = label(stack, "", 17, MINT)
			spacer(stack, 6)
			for id in Rules.RECIPES:
				var recipe: Dictionary = Rules.RECIPES[id]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 20)
				stack.add_child(row)
				var recipe_text := column(row, 3)
				recipe_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label(recipe_text, recipe.title, 21)
				label(recipe_text, "%s  ·  %s" % [recipe.detail, Rules.describe(recipe.cost)], 15, MUTED)
				recipe_buttons[id] = action_button(row, "Fabricate", "recipe", id)
			spacer(stack, 8)
			focus = action_button(stack, "Back", "back")
		"settings":
			label(stack, "Settings", 36)
			for id in Preferences.SETTINGS:
				var setting: Dictionary = Preferences.SETTINGS[id]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 15)
				stack.add_child(row)
				var caption := label(row, setting.title, 17)
				caption.custom_minimum_size.x = 185
				var slider := HSlider.new()
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				slider.min_value = setting.min
				slider.max_value = setting.max
				slider.step = 1.0
				slider.value = data.values[id]
				row.add_child(slider)
				var value := label(row, "%d" % int(slider.value), 17, MINT)
				value.custom_minimum_size.x = 35
				value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				slider.value_changed.connect(update_preference.bind(id, value))
			label(stack, "Set camera motion to 0 to disable camera effects.", 14, MUTED)
			focus = action_button(stack, "Done", "back", null, true)
		"controls":
			label(stack, "Controls", 36)
			for binding in [
				["Move and look", "WASD  /  Mouse"],
				["Sprint, crouch and jump", "Shift  /  Ctrl  /  Space"],
				["Fire, aim and reload", "Left mouse  /  Right mouse  /  R"],
				["Salvage, use relay or open gate", "E"],
				["Fabricator  /  Ration  /  Trauma patch", "Tab  /  F  /  V"],
				["Enter or exit build mode", "B"],
				["Select wall, gate or canopy", "1  /  2  /  3"],
				["Place, rotate or dismantle", "Left mouse  /  R  /  X"],
			]:
				var row := HBoxContainer.new()
				stack.add_child(row)
				var name := label(row, binding[0], 16)
				name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label(row, binding[1], 16, MINT)
			spacer(stack, 5)
			focus = action_button(stack, "Back", "back", null, true)
		"lost":
			label(stack, "Deployment lost", 36, ALERT)
			label(stack, str(data.get("reason", "")), 18, MUTED)
			var retry := action_button(stack, "Retry from checkpoint", "continue", null, true)
			retry.disabled = not bool(data.get("has_save", false))
			var title := action_button(stack, "Return to title", "title")
			focus = title if retry.disabled else retry
		"won":
			label(stack, "Uplink secured", 36, MINT)
			label(stack, "Relay 04 is transmitting again.", 19)
			label(stack, str(data.get("summary", "")), 16, MUTED)
			focus = action_button(stack, "Keep exploring", "resume", null, true)
			action_button(stack, "Return to title", "save_title")
		"confirm":
			label(stack, str(data.get("title", "")), 31)
			var warning := label(stack, str(data.get("detail", "")), 17, MUTED)
			warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			action_button(stack, str(data.get("confirm", "Confirm")), "confirm")
			focus = action_button(stack, "Cancel", "back", null, true)
	menu_message = label(stack, str(data.get("message", "")), 15, AMBER)
	menu_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if focus != null:
		focus.grab_focus()


func update_fabricator(session: Session) -> void:
	var supplies := session.inventory
	craft_inventory.text = "Alloy %d   ·   Fiber %d   ·   Rounds %d   ·   Patches %d" % [
		supplies.alloy, supplies.fiber, session.carbine.reserve, supplies.patches,
	]
	for id in recipe_buttons:
		var button: Button = recipe_buttons[id]
		var capacity: bool = session.carbine.reserve <= Rules.MAX_STACK - 18 if id == "cartridge" else supplies.patches < Rules.MAX_STACK
		button.disabled = not capacity or not Rules.afford(supplies, Rules.RECIPES[id].cost)


func message(text: String) -> void:
	if is_instance_valid(menu_message):
		menu_message.text = text


func update_preference(value: float, id: String, caption: Label) -> void:
	caption.text = "%d" % int(value)
	command.emit("preference", [id, value])


func action_button(parent: Control, text: String, action: String, data: Variant = null, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 41
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		button.add_theme_stylebox_override("normal", flat(Color("#25473f"), Color("#4b8f77"), 5, 14))
	button.pressed.connect(command.emit.bind(action, data))
	parent.add_child(button)
	return button


func column(parent: Control, spacing: int) -> VBoxContainer:
	var items := VBoxContainer.new()
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.add_theme_constant_override("separation", spacing)
	parent.add_child(items)
	return items


func label(parent: Control, text: String, size: int, color := INK) -> Label:
	var item := Label.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	parent.add_child(item)
	return item


func panel_at(parent: Control, anchor: Vector2, rect: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin(parent, panel, anchor, rect)
	return panel


func pin(parent: Control, child: Control, anchor: Vector2, rect: Rect2) -> void:
	parent.add_child(child)
	child.anchor_left = anchor.x
	child.anchor_right = anchor.x
	child.anchor_top = anchor.y
	child.anchor_bottom = anchor.y
	child.offset_left = rect.position.x
	child.offset_top = rect.position.y
	child.offset_right = rect.end.x
	child.offset_bottom = rect.end.y


func spacer(parent: Control, height: float) -> void:
	var blank := Control.new()
	blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blank.custom_minimum_size.y = height
	parent.add_child(blank)


func backdrop(parent: Control, strength: float, title := false, damage := false) -> ColorRect:
	var surface := ShaderMaterial.new()
	surface.shader = shade
	surface.set_shader_parameter("strength", strength)
	surface.set_shader_parameter("title_screen", title)
	surface.set_shader_parameter("damage", damage)
	var veil := ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.material = surface
	parent.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return veil


static func flat(color: Color, outline: Color, radius := 5, margin := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = outline
	style.set_border_width_all(1 if outline.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_top = margin * 0.75
	style.content_margin_right = margin
	style.content_margin_bottom = margin * 0.75
	return style


func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_stylebox("panel", "PanelContainer", flat(PANEL, EDGE, 5, 13))
	theme.set_stylebox("normal", "Button", flat(Color("#162a2f"), EDGE, 5, 14))
	theme.set_stylebox("hover", "Button", flat(Color("#2e4f46"), MINT, 5, 14))
	theme.set_stylebox("pressed", "Button", flat(Color("#294239"), MINT, 5, 14))
	theme.set_stylebox("disabled", "Button", flat(Color("#111c21"), Color("#2c3737"), 5, 14))
	theme.set_stylebox("focus", "Button", flat(Color.TRANSPARENT, AMBER, 5))
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("#748580"))
	return theme
