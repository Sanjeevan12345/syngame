extends Node2D

const PAWN_SCENE = preload("res://scenes/Pawn.tscn")

enum TurnState { WAIT_THROW, ROLLING, CHOOSE_PAWN, MOVING, GAME_OVER }

@export_range(2, 4) var player_count: int = 2

@onready var ui_root: Control = %UIRoot
@onready var turn_label: Label = %TurnLabel
@onready var turn_banner: Control = %TurnLabel.get_parent().get_parent()
@onready var message_label: Label = %MessageLabel
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var players_panel: VBoxContainer = %PlayersPanel
@onready var buy_prompt: Control = %BuyPrompt
@onready var buy_label: Label = %BuyLabel
@onready var buy_button: Button = %BuyButton
@onready var pass_button: Button = %PassButton
@onready var gate_prompt: Control = %GatePrompt
@onready var gate_label: Label = %GateLabel
@onready var enter_button: Button = %EnterButton
@onready var stay_button: Button = %StayButton
@onready var lap_prompt: Control = %LapPrompt
@onready var lap_label: Label = %LapLabel
@onready var loop_button: Button = %LoopButton
@onready var exit_button: Button = %ExitButton
@onready var shakuni_prompt: Control = %ShakuniPrompt
@onready var dice_container: SubViewportContainer = $SubViewportContainer
@onready var dice_viewport: SubViewport = $SubViewportContainer/SubViewport
# Reference to your 3D Dice Scene
@onready var dice = $SubViewportContainer/SubViewport/dice_main
@onready var start_node: BoardNode = $BoardNodes/MonopolyNodes/Node_0
@onready var dev_mode = $DevMode

signal purchase_decided(buy: bool)
signal gate_decided(enter: bool)
signal lap_decided(route: int)

# players_pawns[player_id] holds that player's 3 Pawn nodes
var players_pawns: Array = []
var player_labels: Array = []
var sell_buttons: Array = []
var pending_roll: int = 0
var state: TurnState = TurnState.WAIT_THROW:
	set(value):
		state = value
		if state == TurnState.ROLLING:
			unsaved_changes = true
		# Building is only allowed while waiting to throw
		if state != TurnState.WAIT_THROW and build_panel != null:
			build_panel.visible = false
		if not player_labels.is_empty():
			refresh_players_panel()

# Unowned Kingdom currently offered in the buy prompt
var buy_candidate: BoardNode = null
var buy_candidate_player: int = -1

# Sell panel, built in code. While debt_player is set, that player must sell
# Kingdoms until they can pay debt_amount, and the panel can't be closed.
var sell_panel: PanelContainer
var sell_title: Label
var sell_list: VBoxContainer
var sell_close_button: Button
var sell_player: int = -1
var build_buttons: Array = []

# Build panel, built in code: the active player raises Forts / Palaces before throwing
var build_panel: PanelContainer
var build_title: Label
var build_list: VBoxContainer
var debt_player: int = -1
var debt_amount: int = 0
var debt_reason: String = ""

# Set by an extra_turn card: the same player throws again after this move
var extra_turn_pending: bool = false

# Save / Load buttons on the top bar and the slot picker they open
var save_button: Button
var load_button: Button
var slot_picker: SlotPicker
var settings_panel: PanelContainer

# Return and Load leave the current saga, so both offer to save it first
const OPENING_PAGE_SCENE = "res://scenes/opening_page.tscn"
var return_prompt: PanelContainer
var return_save_button: Button
var unsaved_changes: bool = false # Anything happened since the last save or load
var after_save: Callable # Runs once a save made from the "save first?" prompt succeeds
var return_prompt_action: Callable # Leaving the board or loading another saga

# Lens for reading the board's small writing, toggled from the top bar
var magnifier: Magnifier
var magnifier_button: Button

# Shakuni and Narada's pop-up commentary
var commentary: Commentary

# True while the Chronicle is scrolled to its newest line, so new lines stay in view
var chronicle_follow: bool = true

# Shakuni card picker: one button per possible Pasa score, added in code
signal shakuni_chosen(value: int)

func _ready():
	# A saved game being loaded sets the player count; otherwise the opening
	# page's choice wins over the Inspector value
	var load_data: Dictionary = GameManager.instance.pending_load
	GameManager.instance.pending_load = {}
	if not load_data.is_empty():
		player_count = int(load_data.player_count)
	elif GameManager.instance.selected_player_count > 0:
		player_count = GameManager.instance.selected_player_count
	GameManager.instance.setup_players(player_count)
	spawn_pawns()
	build_save_controls()
	build_sell_panel()
	build_build_panel()
	build_shakuni_prompt()
	build_players_panel()
	GameManager.instance.gold_changed.connect(func(_id, _gold):
		unsaved_changes = true # Builds and sales happen between throws
		refresh_players_panel())
	GameManager.instance.kills_changed.connect(func(_id, _kills): refresh_players_panel())

	buy_button.pressed.connect(func(): purchase_decided.emit(true))
	pass_button.pressed.connect(func(): purchase_decided.emit(false))
	enter_button.pressed.connect(func(): gate_decided.emit(true))
	stay_button.pressed.connect(func(): gate_decided.emit(false))
	loop_button.pressed.connect(func(): lap_decided.emit(Pawn.LapRoute.LOOP_AGAIN))
	exit_button.pressed.connect(func(): lap_decided.emit(Pawn.LapRoute.EXIT))

	print("Checking Dice Node: ", dice)

	if dice != null:
		print("Dice node found! Connecting signal...")
		dice.dice_roll_finished.connect(_on_dice_rolled)
		dice_container.gui_input.connect(_on_dice_area_input)
	else:
		print("ERROR: Dice node is NULL! Check your SubViewport scene path.")

	dev_mode.forced_roll_requested.connect(_on_forced_roll)

	# A Buy / Gate / Lap / Shakuni prompt takes the turn banner's place while shown
	for prompt in [buy_prompt, gate_prompt, lap_prompt, shakuni_prompt]:
		prompt.visibility_changed.connect(update_turn_banner)

	# The Chronicle's scroll range only grows once the new text is laid out
	message_scroll.get_v_scroll_bar().changed.connect(func():
		if chronicle_follow:
			message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value))

	build_commentary()
	if load_data.is_empty():
		commentary.trigger(Commentary.GAME_STARTS, true)
		begin_turn()
	else:
		apply_save(load_data)
	unsaved_changes = false # Setting up the board isn't progress worth saving

# Shakuni and Narada speak from the bottom-left corner, above the board and UI
# but below the top bar
func build_commentary():
	var layer = CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var popup = CharacterPopup.new()
	layer.add_child(popup)
	commentary = Commentary.new()
	add_child(commentary)
	commentary.setup(popup)

# Save, Load and Settings sit at the right end of the ornate bar along the board's top edge.
# That bar's art is drawn by DevMode on layer 10, so the buttons get a layer above it.
func build_save_controls():
	var layer = CanvasLayer.new()
	layer.layer = 11
	add_child(layer)

	var bar = HBoxContainer.new()
	bar.theme = ui_root.theme
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 8)
	bar.position = Vector2(555, 13)
	bar.size = Vector2(450, 32)
	layer.add_child(bar)

	var return_button = Button.new()
	return_button.custom_minimum_size = Vector2(36, 32)
	return_button.tooltip_text = "Return to the opening page"
	return_button.draw.connect(draw_return_icon.bind(return_button))
	return_button.pressed.connect(_on_return_pressed)
	bar.add_child(return_button)

	magnifier_button = Button.new()
	magnifier_button.custom_minimum_size = Vector2(36, 32)
	magnifier_button.toggle_mode = true
	magnifier_button.tooltip_text = "Magnifier: zoom in on the board (mouse wheel changes the zoom, Esc closes)"
	magnifier_button.draw.connect(draw_magnifier_icon.bind(magnifier_button))
	magnifier_button.toggled.connect(func(on): magnifier.set_active(on))
	bar.add_child(magnifier_button)
	build_magnifier()

	save_button = Button.new()
	save_button.text = "SAVE"
	save_button.tooltip_text = "Saving is possible before a throw"
	save_button.pressed.connect(func(): slot_picker.open(SlotPicker.Mode.SAVE))
	bar.add_child(save_button)

	load_button = Button.new()
	load_button.text = "LOAD"
	load_button.pressed.connect(func(): ask_save_before(open_load_picker))
	bar.add_child(load_button)

	var settings_button = Button.new()
	settings_button.text = "SETTINGS"
	settings_button.pressed.connect(func(): settings_panel.visible = not settings_panel.visible)
	bar.add_child(settings_button)
	build_settings_panel()

	slot_picker = SlotPicker.new()
	slot_picker.position = Vector2(180, 330)
	# Closing the picker without saving cancels a pending return
	slot_picker.visibility_changed.connect(func():
		if not slot_picker.visible:
			after_save = Callable())
	slot_picker.slot_chosen.connect(func(slot):
		if slot_picker.mode == SlotPicker.Mode.SAVE:
			save_game(slot)
		else:
			load_game(slot))
	ui_root.add_child(slot_picker)
	build_return_prompt()

# A curved arrow pointing back, drawn in the button's text color
func draw_return_icon(button: Button):
	var color = button.get_theme_color("font_color")
	var center = button.size / 2 + Vector2(2, 2)
	button.draw_arc(center, 8, -PI / 2, PI * 0.75, 16, color, 3, true)
	var tip = center + Vector2(-9, -8)
	button.draw_colored_polygon(PackedVector2Array([
		tip + Vector2(-5, 0), tip + Vector2(5, -6), tip + Vector2(5, 6)]), color)

# A lens with a handle, drawn in the button's text color
func draw_magnifier_icon(button: Button):
	var color = button.get_theme_color("font_color")
	var center = button.size / 2 + Vector2(-2, -2)
	button.draw_arc(center, 7, 0, TAU, 20, color, 2.5, true)
	button.draw_line(center + Vector2(5, 5), center + Vector2(11, 11), color, 3.5, true)

# The lens sits above every panel and the top bar, but only over the board
func build_magnifier():
	var layer = CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	magnifier = Magnifier.new()
	layer.add_child(magnifier)
	var board: Sprite2D = $BoardBgUltraFinal
	var art = board.get_rect()
	magnifier.setup(get_world_2d(), Rect2(board.position + art.position * board.scale, art.size * board.scale))

func build_return_prompt():
	return_prompt = PanelContainer.new()
	return_prompt.visible = false
	return_prompt.position = Vector2(330, 360)
	return_prompt.custom_minimum_size = Vector2(460, 0)
	ui_root.add_child(return_prompt)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	return_prompt.add_child(box)

	var label = Label.new()
	label.theme_type_variation = &"ParchmentLabel"
	label.add_theme_font_size_override("font_size", 22)
	label.text = "This saga is not saved.
Save it first?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	return_save_button = Button.new()
	return_save_button.text = "Save"
	return_save_button.pressed.connect(func():
		return_prompt.hide()
		slot_picker.open(SlotPicker.Mode.SAVE)
		after_save = return_prompt_action)
	row.add_child(return_save_button)

	var leave_button = Button.new()
	leave_button.text = "Don't save"
	leave_button.pressed.connect(func():
		return_prompt.hide()
		return_prompt_action.call())
	row.add_child(leave_button)

	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(return_prompt.hide)
	row.add_child(cancel_button)

func _on_return_pressed():
	ask_save_before(return_to_opening_page)

# Runs action straight away if nothing is unsaved; otherwise asks to save first
func ask_save_before(action: Callable):
	if not unsaved_changes:
		action.call()
		return
	return_prompt_action = action
	# Saving is only possible between moves
	return_save_button.disabled = not can_save()
	return_save_button.tooltip_text = "" if can_save() else "Saving is possible before a throw"
	return_prompt.show()

func open_load_picker():
	slot_picker.open(SlotPicker.Mode.LOAD)

func return_to_opening_page():
	get_tree().change_scene_to_file(OPENING_PAGE_SCENE)

# Music settings, like the opening page's: they update (and are saved by) the Music autoload
func build_settings_panel():
	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	settings_panel.position = Vector2(330, 300)
	settings_panel.custom_minimum_size = Vector2(460, 0)
	ui_root.add_child(settings_panel)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	settings_panel.add_child(box)

	var title = Label.new()
	title.theme_type_variation = &"ParchmentLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var mute_toggle = CheckButton.new()
	mute_toggle.text = "Mute music"
	mute_toggle.button_pressed = Music.muted
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		mute_toggle.add_theme_color_override(color, Color(0.2, 0.11, 0.04))
	mute_toggle.add_theme_font_size_override("font_size", 20)
	mute_toggle.toggled.connect(Music.set_muted)
	box.add_child(mute_toggle)

	var volume_row = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	box.add_child(volume_row)

	var volume_label = Label.new()
	volume_label.theme_type_variation = &"ParchmentLabel"
	volume_label.add_theme_font_size_override("font_size", 20)
	volume_label.text = "Volume"
	volume_row.add_child(volume_label)

	var volume_slider = HSlider.new()
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = Music.volume
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.value_changed.connect(Music.set_volume)
	volume_row.add_child(volume_slider)

	var close = Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(settings_panel.hide)
	box.add_child(close)

# Only between moves: while waiting for a throw nothing is mid-move or awaiting
# a choice, so the whole game is plain data
func can_save() -> bool:
	return state == TurnState.WAIT_THROW and debt_player < 0 and not dice.is_holding

func save_game(slot: int):
	if not can_save():
		return
	var gm = GameManager.instance
	var kingdoms: Array = []
	for node in get_tree().get_nodes_in_group("kingdoms"):
		if node.owner_id >= 0 or node.building_level > 0:
			kingdoms.append({"path": str(get_path_to(node)), "owner_id": node.owner_id,
				"building_level": node.building_level})
	var pawns: Array = []
	for squad in players_pawns:
		for pawn in squad:
			pawns.append(pawn.export_state(self))
	var data = {
		"player_count": player_count,
		"active_player": gm.active_player_index,
		"gm": gm.export_state(),
		"kingdoms": kingdoms,
		"pawns": pawns,
		"chronicle": message_label.text,
	}
	var then = after_save # Hiding the picker clears it
	slot_picker.hide()
	if SaveSystem.write(slot, data):
		unsaved_changes = false
		show_message("The saga is recorded in slot %d" % slot)
		if then.is_valid():
			then.call()

# Reloads the board scene, which restores the save in _ready()
func load_game(slot: int):
	var data = SaveSystem.read(slot)
	if data.is_empty():
		return
	GameManager.instance.pending_load = data
	get_tree().reload_current_scene()

# Puts a freshly set-up board into a saved game's state, ready for the next throw
func apply_save(data: Dictionary):
	var gm = GameManager.instance
	gm.import_state(data.gm)

	for entry in data.kingdoms:
		var node: BoardNode = get_node_or_null(entry.path)
		if node == null:
			continue
		var owner_player = int(entry.owner_id)
		node.set_kingdom_owner(owner_player)
		node.set_building_level(int(entry.building_level))
		if owner_player >= 0:
			gm.player_kingdoms[owner_player].append(node)

	for entry in data.pawns:
		players_pawns[int(entry.owner_id)][int(entry.pawn_index)].import_state(entry, self)
	# Bankrupt players' pawns had already left the board
	for player_id in player_count:
		if gm.player_eliminated[player_id]:
			for pawn in players_pawns[player_id]:
				pawn.queue_free()
			players_pawns[player_id] = []

	message_label.text = data.chronicle
	show_message("The saga resumes from %s" % str(data.saved_at).left(16))
	state = TurnState.WAIT_THROW
	update_turn_label()
	refresh_players_panel()

# Places every player's 3 pawns on Start (Node_0), tinted by player
func spawn_pawns():
	for player_id in player_count:
		var squad: Array = []
		for pawn_index in GameManager.PAWNS_PER_PLAYER:
			var pawn = PAWN_SCENE.instantiate() as Pawn
			pawn.owner_id = player_id
			pawn.pawn_index = pawn_index
			pawn.name = "Pawn_P%d_%d" % [player_id + 1, pawn_index + 1]
			# Each player has their own character design, which tells players apart
			pawn.character = player_id % Pawn.CHARACTERS.size()
			pawn.visual_offset = Vector2((pawn_index - 1) * 14, (player_id - 1.5) * 10)
			$Pawns.add_child(pawn)
			pawn.set_initial_node(start_node)
			pawn.step_finished.connect(_on_pawn_step)
			squad.append(pawn)
		players_pawns.append(squad)

# One orange scroll listing every player: a line each with their gold, Kingdoms,
# color sets and kills, plus Build and Sell buttons (Sell works at any time).
# The scroll grows with the player count; long lines scroll sideways.
func build_players_panel():
	var scroll_art = ScaledPanel.new()
	scroll_art.art = ScaledPanel.Art.SCROLL_ORANGE
	players_panel.add_child(scroll_art)

	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	scroll_art.add_child(rows)
	# Padding keeps the first line below the gem and the last clear of the edge
	var top_pad = Control.new()
	top_pad.custom_minimum_size = Vector2(0, 16)
	rows.add_child(top_pad)

	for player_id in player_count:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		rows.add_child(row)

		var text_scroll = ScrollContainer.new()
		text_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		text_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text_scroll)

		var label = RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.scroll_active = false
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_scroll.add_child(label)
		player_labels.append(label)

		var build = Button.new()
		build.text = "BUILD"
		build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		build.pressed.connect(open_build_panel.bind(player_id))
		row.add_child(build)
		build_buttons.append(build)

		var sell = Button.new()
		sell.text = "SELL"
		sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sell.pressed.connect(open_sell_panel.bind(player_id))
		row.add_child(sell)
		sell_buttons.append(sell)
	var bottom_pad = Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 12)
	rows.add_child(bottom_pad)
	refresh_players_panel()

func refresh_players_panel():
	var gm = GameManager.instance
	for player_id in player_count:
		# Player colours are darkened so they stay readable on the parchment
		var tag = "[color=#%s]P%d:[/color] " % [
			GameManager.PLAYER_COLORS[player_id].darkened(0.45).to_html(false), player_id + 1]
		if gm.player_eliminated[player_id]:
			player_labels[player_id].text = tag + "BANKRUPT"
		else:
			player_labels[player_id].text = tag + "%d Gold | %d Kingdoms | %d/%d Sets | %d/%d Kills | %d/%d Vaikuntha" % [
				gm.player_suvarnas[player_id], gm.player_kingdoms[player_id].size(),
				gm.count_color_sets(player_id), GameManager.HOME_STRETCH_SETS_REQUIRED,
				gm.player_kills[player_id], GameManager.HOME_STRETCH_KILLS_REQUIRED,
				count_pawns_in_vaikuntha(player_id), GameManager.PAWNS_PER_PLAYER]
			if gm.player_shakuni[player_id]:
				player_labels[player_id].text += " | ★ Shakuni"
			if gm.player_skip_turns[player_id] > 0:
				player_labels[player_id].text += " | Skips %d" % gm.player_skip_turns[player_id]
		sell_buttons[player_id].disabled = not can_sell(player_id)
		build_buttons[player_id].disabled = not can_open_build(player_id)
	save_button.disabled = not can_save()

	# Selling during the buy prompt can make a Kingdom affordable
	if buy_prompt.visible and buy_candidate != null:
		update_buy_prompt()
	refresh_sell_panel()
	refresh_build_panel()

# Only the active player may build, before throwing, and only on a full colour set
func can_open_build(player_id: int) -> bool:
	var gm = GameManager.instance
	if state != TurnState.WAIT_THROW or player_id != gm.active_player_index or gm.player_eliminated[player_id]:
		return false
	return gm.player_kingdoms[player_id].any(func(n): return gm.owns_full_set(player_id, n.color_set))

func build_build_panel():
	build_panel = PanelContainer.new()
	build_panel.visible = false
	build_panel.position = Vector2(300, 240)
	build_panel.custom_minimum_size = Vector2(520, 0)
	ui_root.add_child(build_panel)

	var box = VBoxContainer.new()
	build_panel.add_child(box)

	build_title = Label.new()
	build_title.theme_type_variation = &"ParchmentLabel"
	build_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_title.custom_minimum_size = Vector2(440, 0)
	box.add_child(build_title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 300)
	box.add_child(scroll)

	build_list = VBoxContainer.new()
	build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(build_list)

	var close = Button.new()
	close.text = "Close"
	close.pressed.connect(func(): build_panel.visible = false)
	box.add_child(close)

func open_build_panel(player_id: int):
	if not can_open_build(player_id) or debt_player >= 0:
		return
	sell_panel.visible = false
	build_panel.visible = true
	refresh_build_panel()

func describe_buildings(node: BoardNode) -> String:
	if node.building_level == GameManager.PALACE_LEVEL:
		return "Palace"
	return "%d Fort%s" % [node.building_level, "" if node.building_level == 1 else "s"]

# Lists every Kingdom in the active player's full colour sets with its next build step
func refresh_build_panel():
	if build_panel == null or not build_panel.visible:
		return
	var gm = GameManager.instance
	var player_id = gm.active_player_index
	if not can_open_build(player_id):
		build_panel.visible = false
		return

	build_title.text = "Player %d: build Forts (up to 4), then a Palace. Build evenly across each set.\nBank: %d Forts, %d Palaces left" % [
		player_id + 1, gm.forts_available, gm.palaces_available]
	build_title.modulate = GameManager.PLAYER_COLORS[player_id]

	for child in build_list.get_children():
		child.queue_free()
	for node in gm.player_kingdoms[player_id]:
		if not gm.owns_full_set(player_id, node.color_set):
			continue
		var button = Button.new()
		var reason = gm.build_block_reason(player_id, node)
		var step = "Upgrade to Palace" if node.building_level == GameManager.MAX_FORTS else "Build Fort"
		button.text = "%s (%s): %s - %s for %d Gold, rent %d" % [
			node.property_name, node.color_set, describe_buildings(node), step, gm.fort_cost(node), gm.calc_rent(node)]
		if node.building_level == GameManager.PALACE_LEVEL:
			button.text = "%s (%s): Palace - rent %d" % [node.property_name, node.color_set, gm.calc_rent(node)]
		if reason != "" and node.building_level != GameManager.PALACE_LEVEL:
			button.text += "  [%s]" % reason
		button.disabled = reason != ""
		button.pressed.connect(_on_build_pressed.bind(player_id, node))
		build_list.add_child(button)

func _on_build_pressed(player_id: int, node: BoardNode):
	if GameManager.instance.build_on(player_id, node):
		show_message("Player %d built on %s: now %s (rent %d)" % [
			player_id + 1, node.property_name, describe_buildings(node), GameManager.instance.calc_rent(node)])
		commentary.trigger(Commentary.BUILDS_FORT)
	refresh_players_panel()

func can_sell(player_id: int) -> bool:
	var gm = GameManager.instance
	return state != TurnState.GAME_OVER and not gm.player_eliminated[player_id] \
		and not gm.player_kingdoms[player_id].is_empty()

func build_sell_panel():
	sell_panel = PanelContainer.new()
	sell_panel.visible = false
	sell_panel.position = Vector2(300, 240)
	sell_panel.custom_minimum_size = Vector2(520, 0)
	ui_root.add_child(sell_panel)

	var box = VBoxContainer.new()
	sell_panel.add_child(box)

	sell_title = Label.new()
	sell_title.theme_type_variation = &"ParchmentLabel"
	sell_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sell_title.custom_minimum_size = Vector2(440, 0)
	box.add_child(sell_title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 300)
	box.add_child(scroll)

	sell_list = VBoxContainer.new()
	sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sell_list)

	sell_close_button = Button.new()
	sell_close_button.text = "Close"
	sell_close_button.pressed.connect(func(): sell_panel.visible = false)
	box.add_child(sell_close_button)

func open_sell_panel(player_id: int):
	# A player who owes money keeps the panel until the debt is covered
	if debt_player >= 0 and player_id != debt_player:
		return
	sell_player = player_id
	build_panel.visible = false
	sell_panel.visible = true
	refresh_sell_panel()

# Rebuilds the list of the selling player's Kingdoms and their resale prices
func refresh_sell_panel():
	if not sell_panel.visible:
		return
	var gm = GameManager.instance

	if sell_player == debt_player:
		sell_title.text = "Player %d owes %d Gold (%s) but has %d. Sell Kingdoms to cover it." % [
			sell_player + 1, debt_amount, debt_reason, gm.player_suvarnas[sell_player]]
	else:
		sell_title.text = "Player %d: sell Kingdoms to the Bank for %d%% of their price" % [
			sell_player + 1, int(GameManager.RESALE_RATE * 100)]
	sell_title.modulate = GameManager.PLAYER_COLORS[sell_player]
	sell_close_button.disabled = sell_player == debt_player

	for child in sell_list.get_children():
		child.queue_free()
	for node in gm.player_kingdoms[sell_player]:
		# Buildings come down first, evenly across the set, at half their price
		if node.building_level > 0:
			var piece = "Palace" if node.building_level == GameManager.PALACE_LEVEL else "Fort"
			var building_button = Button.new()
			building_button.text = "Sell a %s on %s (%s)" % [piece, node.property_name, describe_buildings(node)]
			building_button.disabled = not can_sell(sell_player) or not gm.can_sell_building(sell_player, node)
			if not gm.can_sell_building(sell_player, node):
				building_button.text += "  [sell evenly]"
			building_button.pressed.connect(_on_sell_building_pressed.bind(sell_player, node))
			sell_list.add_child(building_button)

		var button = Button.new()
		button.text = "Sell %s (%s) for %d Gold" % [node.property_name, node.color_set, gm.resale_value(node)]
		var set_built = gm.set_has_buildings(node.color_set)
		if set_built:
			button.text += "  [sell the set's buildings first]"
		button.disabled = not can_sell(sell_player) or set_built
		button.pressed.connect(_on_sell_pressed.bind(sell_player, node))
		sell_list.add_child(button)

func _on_sell_pressed(player_id: int, node: BoardNode):
	var value = GameManager.instance.sell_kingdom(player_id, node)
	show_message("Player %d sold %s to the Bank for %d Gold" % [player_id + 1, node.property_name, value])
	refresh_players_panel()

func _on_sell_building_pressed(player_id: int, node: BoardNode):
	var value = GameManager.instance.sell_building(player_id, node)
	show_message("Player %d sold a building on %s for %d Gold (now %s)" % [
		player_id + 1, node.property_name, value, describe_buildings(node)])
	refresh_players_panel()

# Adds a line to the Chronicle of War, which keeps the whole game's history
func show_message(text: String):
	print(text)
	# Only follow new lines if the reader hasn't scrolled up into the history
	var bar = message_scroll.get_v_scroll_bar()
	chronicle_follow = message_scroll.scroll_vertical >= bar.max_value - bar.page - 4
	if message_label.text != "":
		message_label.text += "\n"
	message_label.text += text

# Drag inside the dice view to pick up the sticks, release to throw them
func _on_dice_area_input(event: InputEvent):
	if state != TurnState.WAIT_THROW and not dice.is_holding:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dice.begin_hold(to_dice_viewport(event.position))
		elif dice.is_holding:
			dice.release_hold()
			state = TurnState.ROLLING
			turn_label.text = "Rolling..."
	elif event is InputEventMouseMotion and dice.is_holding:
		dice.hold_to(to_dice_viewport(event.position))

# Converts a position inside the container into the SubViewport's own pixels
func to_dice_viewport(container_pos: Vector2) -> Vector2:
	if dice_container.stretch:
		return container_pos * Vector2(dice_viewport.size) / dice_container.size
	return container_pos

# Developer mode: skip the throw and use a chosen roll
func _on_forced_roll(value: int):
	if state != TurnState.WAIT_THROW or dice.is_holding:
		return
	show_message("[DEV] Forced roll: %d" % value)
	_on_dice_rolled(value)

func _on_dice_rolled(rolled_number: int):
	print("Dice result: ", rolled_number, " | Waiting for pawn choice...")
	pending_roll = rolled_number
	state = TurnState.CHOOSE_PAWN

	var player_id = GameManager.instance.active_player_index
	var movable = get_movable_pawns(player_id)

	if movable.is_empty():
		# e.g. every pawn still out is in its Home Stretch and the roll overshoots Vaikuntha
		turn_label.text = "Player %d rolled %d - no pawn can move" % [player_id + 1, pending_roll]
		show_message("Player %d rolled %d but has no legal move. Turn passes." % [player_id + 1, pending_roll])
		state = TurnState.MOVING
		await get_tree().create_timer(1.5).timeout
		switch_turn()
		return

	turn_label.text = "Player %d rolled %d - click a pawn" % [player_id + 1, pending_roll]
	for pawn in movable:
		pawn.set_selectable(true)

# Pawns that may use the current roll: not already in Vaikuntha, and not
# overshooting it (Vaikuntha needs the exact roll)
func get_movable_pawns(player_id: int) -> Array:
	var qualified = GameManager.instance.can_enter_home_stretch(player_id)
	return players_pawns[player_id].filter(func(p): return p.can_move(pending_roll, qualified))

func count_pawns_in_vaikuntha(player_id: int) -> int:
	return players_pawns[player_id].filter(func(p): return p.path_state == Pawn.PathState.VAIKUNTHA).size()

# Clicking one of the active player's pawns on the board moves it
func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel") and magnifier_button.button_pressed:
		magnifier_button.button_pressed = false # Esc puts the magnifier away
		return
	if state != TurnState.CHOOSE_PAWN:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var click_pos = get_global_mouse_position()

	# Check the pawn drawn on top first when pawns overlap
	var candidates = get_movable_pawns(GameManager.instance.active_player_index)
	candidates.sort_custom(func(a, b): return a.get_index() > b.get_index())
	for pawn in candidates:
		if pawn.contains_point(click_pos):
			get_viewport().set_input_as_handled()
			_on_pawn_selected(pawn)
			return

func _on_pawn_selected(pawn: Pawn):
	state = TurnState.MOVING
	var mover_id = pawn.owner_id # Kept separately: the pawn is freed if its player goes bankrupt
	for squad_pawn in players_pawns[pawn.owner_id]:
		squad_pawn.set_selectable(false)

	# Draw the moving pawn above the others
	$Pawns.move_child(pawn, -1)

	pawn.move_steps(pending_roll, ask_gate, handle_lap_complete, ask_exit)
	await pawn.movement_finished

	print("Pawn landed on: ", pawn.current_node.get_display_name())

	if pawn.path_state == Pawn.PathState.VAIKUNTHA:
		var arrived = count_pawns_in_vaikuntha(pawn.owner_id)
		show_message("Player %d's Pawn %d landed on the Vaikuntha Lotus (%d/%d)." % [
			pawn.owner_id + 1, pawn.pawn_index + 1, arrived, GameManager.PAWNS_PER_PLAYER])
		refresh_players_panel()

		# The game is won only when all of a player's pawns are in Vaikuntha
		if arrived == GameManager.PAWNS_PER_PLAYER:
			declare_winner(pawn.owner_id, "brought all pawns to Vaikuntha")
			return
		switch_turn()
		return

	# Vadh overrides the tile's economy rules
	if not await resolve_capture(pawn):
		await resolve_landing(pawn)

	var remaining = GameManager.instance.get_remaining_players()
	if remaining.size() == 1:
		declare_winner(remaining[0], "is the last player standing")
		return

	if extra_turn_pending and not GameManager.instance.player_eliminated[mover_id]:
		extra_turn_pending = false
		show_message("Player %d throws again!" % (mover_id + 1))
		begin_turn()
		return
	extra_turn_pending = false

	switch_turn()

# Passing or landing on Rajasuva Yajna pays the Start bonus
func _on_pawn_step(pawn: Pawn, node: BoardNode):
	if node == start_node:
		GameManager.instance.add_gold(pawn.owner_id, GameManager.START_BONUS)
		show_message("Player %d reached %s: +%d Gold" % [pawn.owner_id + 1, node.property_name, GameManager.START_BONUS])
		commentary.trigger(Commentary.COLLECTS_START)

# Captures opponent pawns on the landing tile; returns true if a Vadh happened
func resolve_capture(pawn: Pawn) -> bool:
	var all_pawns: Array = []
	for squad in players_pawns:
		all_pawns.append_array(squad)

	var victims = GameManager.instance.find_vadh_victims(pawn, all_pawns, start_node)
	if victims.is_empty():
		return false

	# The attacker swings at its victims before they are sent home
	pawn.sprite.flip_h = victims[0].global_position.x < pawn.global_position.x
	await pawn.play_fight()

	for victim in victims:
		GameManager.instance.execute_vadh_capture(pawn, victim, start_node)
		show_message("VADH! Player %d captured Player %d's Pawn %d at %s - sent back to %s" % [
			pawn.owner_id + 1, victim.owner_id + 1, victim.pawn_index + 1,
			pawn.current_node.get_display_name(), start_node.property_name])
	return true

# Applies the economy rules of the tile the pawn stopped on
func resolve_landing(pawn: Pawn):
	var gm = GameManager.instance
	var node = pawn.current_node
	var player_id = pawn.owner_id

	# Named corners and kingdoms Shakuni and Narada have something to say about
	var landing_lines = {
		"BoardNodes/MonopolyNodes/Node_10": Commentary.HALL_OF_DICE,
		"BoardNodes/MonopolyNodes/Node_30": Commentary.KAMYAKA_FOREST,
		"BoardNodes/MonopolyNodes/Node_20": Commentary.DWARKA_HAVEN,
		"BoardNodes/MonopolyNodes/Node_5": Commentary.MAGADHA,
		"BoardNodes/MonopolyNodes/Node_1": Commentary.GANDHARA,
		"BoardNodes/MonopolyNodes/Node_35": Commentary.GANDHARA,
	}
	var landing_when = landing_lines.get(str(get_path_to(node)), "")
	if landing_when != "":
		commentary.trigger(landing_when)

	match node.tile_type:
		BoardNode.TileType.TAX:
			if await collect_payment(player_id, node.tile_gold, -1, node.property_name):
				show_message("Player %d paid %d Gold at %s" % [player_id + 1, node.tile_gold, node.property_name])

		BoardNode.TileType.BONUS:
			gm.add_gold(player_id, node.tile_gold)
			show_message("Player %d collected %d Gold at %s" % [player_id + 1, node.tile_gold, node.property_name])

		BoardNode.TileType.ROLL_AGAIN:
			extra_turn_pending = true
			show_message("Player %d landed on %s: roll again" % [player_id + 1, node.property_name])

		BoardNode.TileType.SKIP_TURN:
			gm.player_skip_turns[player_id] += 1
			show_message("Player %d landed on %s and will skip their next turn" % [player_id + 1, node.property_name])

		BoardNode.TileType.CARD:
			var card = gm.draw_card(node.card_deck)
			show_message("%s card: %s" % [node.property_name, card["text"]])
			commentary.trigger(Commentary.DRAWS_CARD)
			await apply_card(pawn, card, node.property_name + " card")

		BoardNode.TileType.MONOPOLY:
			if not node.is_kingdom():
				return
			if node.owner_id == -1:
				await offer_purchase(player_id, node)
			elif node.owner_id != player_id:
				var owner_id = node.owner_id
				var rent = gm.calc_rent(node)
				var detail = describe_buildings(node)
				if node.building_level == 0:
					detail = "full set" if gm.owns_full_set(owner_id, node.color_set) else "no buildings"
				if await collect_payment(player_id, rent, owner_id, "rent on " + node.property_name):
					show_message("Player %d paid %d Gold rent (%s) to Player %d for %s" % [
						player_id + 1, rent, detail, owner_id + 1, node.property_name])
					commentary.trigger(Commentary.PAYS_RENT)

# Charges a player. If their Gold is short but Gold + 75% of their Kingdoms covers it,
# they must sell Kingdoms until they can pay. If even that can't cover it, they go
# bankrupt. creditor_id is the player paid, or -1 for the Bank.
# Returns true if the payment was made.
func collect_payment(player_id: int, amount: int, creditor_id: int, reason: String) -> bool:
	var gm = GameManager.instance

	if gm.total_balance(player_id) < amount:
		go_bankrupt(player_id, creditor_id, amount, reason)
		return false

	if not gm.can_afford(player_id, amount):
		debt_player = player_id
		debt_amount = amount
		debt_reason = reason
		open_sell_panel(player_id)
		while not gm.can_afford(player_id, amount):
			await gm.gold_changed
		debt_player = -1
		sell_panel.visible = false

	gm.add_gold(player_id, -amount)
	if creditor_id >= 0:
		gm.add_gold(creditor_id, amount)
	return true

# Eliminates a player who can't pay. Their Kingdoms go back to the Bank, their
# pawns leave the board, and a player creditor receives everything they had left.
func go_bankrupt(player_id: int, creditor_id: int, amount: int, reason: String):
	var gm = GameManager.instance
	commentary.trigger(Commentary.GOES_BANKRUPT, true)
	var worth = gm.eliminate_player(player_id)
	if creditor_id >= 0:
		gm.add_gold(creditor_id, worth)

	for pawn in players_pawns[player_id]:
		pawn.queue_free()
	players_pawns[player_id] = []

	if sell_player == player_id:
		sell_panel.visible = false

	show_message("Player %d can't pay %d Gold (%s) and is BANKRUPT - eliminated!" % [
		player_id + 1, amount, reason])
	if creditor_id >= 0:
		show_message("Player %d receives Player %d's remaining %d Gold" % [creditor_id + 1, player_id + 1, worth])
	refresh_players_panel()

# Asks the player whether to buy the unowned Kingdom they landed on
func offer_purchase(player_id: int, node: BoardNode):
	var gm = GameManager.instance
	buy_candidate = node
	buy_candidate_player = player_id
	update_buy_prompt()
	buy_prompt.visible = true

	var buy: bool = await purchase_decided
	buy_prompt.visible = false
	buy_candidate = null

	if buy and gm.buy_kingdom(player_id, node):
		refresh_players_panel()
		show_message("Player %d bought %s" % [player_id + 1, node.property_name])
		commentary.trigger([Commentary.BUYS_KINGDOM, Commentary.RIVAL_BUYS_KINGDOM].pick_random())

func update_buy_prompt():
	var affordable = GameManager.instance.can_afford(buy_candidate_player, buy_candidate.purchase_cost)
	buy_label.text = "Buy %s for %d Gold?" % [buy_candidate.property_name, buy_candidate.purchase_cost]
	if not affordable:
		buy_label.text += " (not enough Gold)"
	buy_button.disabled = not affordable

# Asks whether this pawn should leave the outer ring through the gate it is on
func ask_gate(pawn: Pawn, gate: BoardNode) -> bool:
	gate_label.text = "Pawn %d is at %s. Enter the Ludo board?" % [pawn.pawn_index + 1, gate.property_name]
	enter_button.text = "Enter Ludo board"
	stay_button.text = "Stay on outer ring"
	gate_prompt.visible = true

	var enter: bool = await gate_decided
	gate_prompt.visible = false

	if enter:
		show_message("Player %d's Pawn %d enters the Ludo board at %s" % [
			pawn.owner_id + 1, pawn.pawn_index + 1, gate.property_name])
	return enter

# Asks whether a pawn stopped on a Ludo arm tip should leave through that arm's gate.
# Reuses the gate prompt with exit wording.
func ask_exit(pawn: Pawn, gate: BoardNode) -> bool:
	gate_label.text = "Pawn %d can leave through %s. Exit to the outer ring?" % [pawn.pawn_index + 1, gate.property_name]
	enter_button.text = "Exit to outer ring"
	stay_button.text = "Stay on Ludo track"
	gate_prompt.visible = true

	var exit: bool = await gate_decided
	gate_prompt.visible = false

	if exit:
		show_message("Player %d's Pawn %d leaves the Ludo board through %s (lap progress lost)" % [
			pawn.owner_id + 1, pawn.pawn_index + 1, gate.property_name])
	return exit

# A pawn finished a Ludo lap: qualified players turn home, others get the
# lap bonus and choose to loop again or exit to the outer ring
func handle_lap_complete(pawn: Pawn) -> int:
	var gm = GameManager.instance
	var player_id = pawn.owner_id

	if gm.can_enter_home_stretch(player_id):
		show_message("Player %d's Pawn %d completed the lap and turns into the Home Stretch" % [
			player_id + 1, pawn.pawn_index + 1])
		return Pawn.LapRoute.HOME

	gm.add_gold(player_id, GameManager.UNQUALIFIED_LAP_BONUS)
	show_message("Player %d's Pawn %d completed the lap without qualifying (needs %d color set + %d kills): +%d Gold" % [
		player_id + 1, pawn.pawn_index + 1, GameManager.HOME_STRETCH_SETS_REQUIRED,
		GameManager.HOME_STRETCH_KILLS_REQUIRED, GameManager.UNQUALIFIED_LAP_BONUS])

	lap_label.text = "Pawn %d can't go home yet." % (pawn.pawn_index + 1)
	lap_prompt.visible = true
	var route: int = await lap_decided
	lap_prompt.visible = false

	if route == Pawn.LapRoute.EXIT:
		show_message("Pawn %d will leave through %s" % [pawn.pawn_index + 1, pawn.entry_gate.property_name])
	return route

# Ends the game: reaching Vaikuntha, or every other player going bankrupt
func declare_winner(player_id: int, reason: String):
	state = TurnState.GAME_OVER
	sell_panel.visible = false
	turn_label.text = "Player %d %s and WINS!" % [player_id + 1, reason]
	refresh_players_panel()
	commentary.trigger(Commentary.GAME_ENDS, true)

func switch_turn():
	commentary.check_fortunes()
	GameManager.instance.end_turn()
	print("Switched turn to: Player ", GameManager.instance.active_player_index + 1)
	begin_turn()

# Starts the active player's turn: a skip card passes it, a Shakuni card lets
# them pick the roll, otherwise they throw the sticks
func begin_turn():
	var gm = GameManager.instance
	var player_id = gm.active_player_index

	if gm.player_skip_turns[player_id] > 0:
		gm.player_skip_turns[player_id] -= 1
		state = TurnState.MOVING
		turn_label.text = "Player %d skips this turn" % (player_id + 1)
		show_message("Player %d skips this turn" % (player_id + 1))
		refresh_players_panel()
		await get_tree().create_timer(1.5).timeout
		switch_turn()
		return

	if gm.player_shakuni[player_id]:
		gm.player_shakuni[player_id] = false
		refresh_players_panel()
		state = TurnState.ROLLING # Blocks throwing the sticks
		turn_label.text = "Player %d - Shakuni's dice: choose your roll" % (player_id + 1)
		shakuni_prompt.visible = true
		var value: int = await shakuni_chosen
		shakuni_prompt.visible = false
		show_message("Player %d uses Shakuni's dice: %d" % [player_id + 1, value])
		_on_dice_rolled(value)
		return

	state = TurnState.WAIT_THROW
	update_turn_label()

func build_shakuni_prompt():
	var row = %ShakuniRow
	var label = Label.new()
	label.text = "Shakuni's dice:"
	row.add_child(label)

	for value in GameManager.PASA_SCORES:
		var button = Button.new()
		button.text = str(value)
		button.custom_minimum_size = Vector2(44, 0)
		button.pressed.connect(func(): shakuni_chosen.emit(value))
		row.add_child(button)

# Applies a Dharma/Adharma card drawn by this pawn's player
func apply_card(pawn: Pawn, card: Dictionary, reason: String):
	var gm = GameManager.instance
	var player_id = pawn.owner_id
	var amount: int = card.get("amount", 0)

	match card["effect"]:
		"gold":
			if amount >= 0:
				gm.add_gold(player_id, amount)
			else:
				await collect_payment(player_id, -amount, -1, reason)

		"collect_each":
			for opponent in gm.get_remaining_players():
				if opponent != player_id:
					await collect_payment(opponent, amount, player_id, reason)

		"pay_each":
			for opponent in gm.get_remaining_players():
				if opponent != player_id and not gm.player_eliminated[player_id]:
					await collect_payment(player_id, amount, opponent, reason)

		"go_to_start":
			# Card moves don't trigger the new tile's landing rules
			pawn.reset_to_start(start_node)
			if card.get("bonus", false):
				gm.add_gold(player_id, GameManager.START_BONUS)
				show_message("Player %d collects %d Gold at %s" % [player_id + 1, GameManager.START_BONUS, start_node.property_name])
				commentary.trigger(Commentary.COLLECTS_START)

		"enter_ludo":
			var gate = pawn.find_next_gate()
			if gate != null:
				await pawn.enter_ludo_through(gate)
				show_message("Player %d's Pawn %d enters the Ludo board at %s" % [
					player_id + 1, pawn.pawn_index + 1, gate.property_name])

		"skip_self":
			gm.player_skip_turns[player_id] += 1

		"skip_next":
			var rival = gm.next_active_opponent(player_id)
			if rival != player_id:
				gm.player_skip_turns[rival] += 1
				show_message("Player %d will skip their next turn" % (rival + 1))

		"extra_turn":
			extra_turn_pending = true

		"shakuni":
			gm.player_shakuni[player_id] = true

		"free_fort":
			var target = gm.find_free_fort_target(player_id)
			if target != null and gm.build_on(player_id, target, true):
				show_message("A free Fort rises on %s (now %s)" % [target.property_name, describe_buildings(target)])
				commentary.trigger(Commentary.BUILDS_FORT)
			else:
				gm.add_gold(player_id, amount)
				show_message("Nowhere to build - Player %d receives %d Gold instead" % [player_id + 1, amount])

		"burn_fort":
			# The most-built Kingdom loses one step; nothing is refunded
			var target: BoardNode = null
			for node in gm.player_kingdoms[player_id]:
				if node.building_level > 0 and (target == null or node.building_level > target.building_level):
					target = node
			if target != null:
				gm.remove_building_level(target)
				show_message("Fire on %s! Now %s" % [target.property_name, describe_buildings(target)])
			else:
				show_message("Player %d has no Forts to burn" % (player_id + 1))

		"repair_tax":
			var counts = gm.count_buildings(player_id)
			var tax = counts["forts"] * GameManager.REPAIR_TAX_PER_FORT \
				+ counts["palaces"] * GameManager.REPAIR_TAX_PER_PALACE
			if tax > 0:
				if await collect_payment(player_id, tax, -1, reason):
					show_message("Player %d paid %d Gold for repairs" % [player_id + 1, tax])
			else:
				show_message("Player %d has nothing to repair" % (player_id + 1))

	refresh_players_panel()

func update_turn_banner():
	turn_banner.visible = not (buy_prompt.visible or gate_prompt.visible
		or lap_prompt.visible or shakuni_prompt.visible)

func update_turn_label():
	var player_id = GameManager.instance.active_player_index
	turn_label.text = "Player %d - drag and throw the sticks" % (player_id + 1)
