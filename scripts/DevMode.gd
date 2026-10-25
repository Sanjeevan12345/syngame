extends CanvasLayer
# Developer-only test tools. The "Dev Mode" toggle in the top-left corner shows
# a bar to skip the throw and pick the roll yourself, and a Tools button that
# opens a drawer over the left of the board with:
#   Target   - which player and pawn the tools act on
#   Pawns    - teleport to any outer-ring space (optionally applying it), send to
#              the Home Stretch or straight to Vaikuntha
#   Economy  - set Gold, give kingdoms or whole colour sets, set Kills
#   Cards    - draw any chosen Dharma / Adharma card, with its animation
#   Turn     - make it a chosen player's turn, skip a turn, win, go bankrupt
#   Talk     - make Shakuni or Narada say any line; reset the commentary pacing
#   Debug    - game speed, space IDs on the board, a fixed random seed
# The tools use the board's own rule functions, so their effects play out as in a game.

signal forced_roll_requested(value: int)

const DRAWER_WIDTH: float = 470.0
const SPEEDS = [1.0, 2.0, 4.0]

var enabled: bool = false

var toggle_button: CheckButton
var dev_panel: HBoxContainer
var roll_spinbox: SpinBox
var tools_button: Button
var drawer: PanelContainer
var status_label: Label

var board: Node # The main board (MainBoard.gd), this node's parent
var player_option: OptionButton
var pawn_option: OptionButton
var space_option: OptionButton
var kingdom_option: OptionButton
var set_option: OptionButton
var card_option: OptionButton
var line_option: OptionButton
var gold_spinbox: SpinBox
var kills_spinbox: SpinBox
var seed_spinbox: SpinBox
var space_ids: Node2D

var ring_spaces: Array = [] # Outer-ring BoardNodes, in order from Start
var kingdoms: Array = []
var card_entries: Array = [] # [deck, card]
var line_entries: Array = [] # {name, text}

func _ready():
	layer = 10 # Above the game UI
	board = get_parent()

	# Ornate frame along the top edge of the board, styled like the game UI
	var frame = ScaledPanel.new()
	frame.art = ScaledPanel.Art.ORNATE_FRAME
	frame.art_scale = 0.15
	frame.theme = preload("res://scenes/main_ui_theme.tres")
	frame.position = Vector2(80, 0)
	frame.size = Vector2(960, 58)
	add_child(frame)

	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE # Spans the whole frame; let clicks reach Save / Load
	frame.add_child(bar)

	toggle_button = CheckButton.new()
	toggle_button.text = "Dev Mode"
	toggle_button.toggled.connect(set_enabled)
	bar.add_child(toggle_button)

	dev_panel = HBoxContainer.new()
	dev_panel.visible = false
	dev_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(dev_panel)

	var label = Label.new()
	label.text = "Roll:"
	label.add_theme_font_size_override("font_size", 22)
	dev_panel.add_child(label)

	# Any value, so long jumps (e.g. a full 72-tile Ludo lap) can be tested quickly
	roll_spinbox = SpinBox.new()
	roll_spinbox.min_value = 1
	roll_spinbox.max_value = 100
	roll_spinbox.value = 6
	roll_spinbox.custom_minimum_size = Vector2(110, 0) # Leaves room for the top bar's buttons on the right
	dev_panel.add_child(roll_spinbox)

	var roll_button = Button.new()
	roll_button.text = "Roll"
	roll_button.tooltip_text = "Use this roll instead of throwing"
	roll_button.pressed.connect(func(): forced_roll_requested.emit(int(roll_spinbox.value)))
	dev_panel.add_child(roll_button)

	tools_button = Button.new()
	tools_button.text = "Tools"
	tools_button.toggle_mode = true
	tools_button.tooltip_text = "Open the developer tools drawer"
	tools_button.toggled.connect(func(on):
		# Built on first use: the board sets itself up after this node is ready
		if drawer == null:
			build_drawer()
		drawer.visible = on)
	dev_panel.add_child(tools_button)

func _exit_tree():
	Engine.time_scale = 1.0 # Game speed is global; don't carry it to other scenes

func set_enabled(value: bool):
	enabled = value
	dev_panel.visible = value
	if not value:
		tools_button.button_pressed = false
	print("Developer mode ", "ON" if value else "OFF")

# --- Drawer layout ---

func build_drawer():
	drawer = PanelContainer.new()
	drawer.theme = preload("res://scenes/main_ui_theme.tres")
	drawer.position = Vector2(84, 62)
	drawer.size = Vector2(DRAWER_WIDTH, 1000)
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.06, 0.05, 0.94)
	box.border_color = Color("#D9A21B")
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10)
	drawer.add_theme_stylebox_override("panel", box)
	add_child(drawer)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(DRAWER_WIDTH - 20, 990)
	drawer.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.text = "Tools act on the Target player and pawn."
	list.add_child(status_label)

	collect_board_data()

	# Target
	add_header(list, "Target")
	player_option = OptionButton.new()
	for i in board.player_count:
		player_option.add_item("Player %d" % (i + 1))
	pawn_option = OptionButton.new()
	for i in GameManager.PAWNS_PER_PLAYER:
		pawn_option.add_item("Pawn %d" % (i + 1))
	add_row(list, [player_option, pawn_option])

	# Pawns
	add_header(list, "Pawns")
	space_option = OptionButton.new()
	for i in ring_spaces.size():
		space_option.add_item("%d  %s" % [i, ring_spaces[i].get_display_name()])
	add_row(list, [space_option])
	add_row(list, [
		make_button("Teleport", teleport.bind(false), "Move the pawn there without any effect"),
		make_button("Teleport + land", teleport.bind(true), "Move there and apply the space (rent, card, capture...)")])
	add_row(list, [
		make_button("1 step from Lotus", send_home_stretch, "Last Home Stretch space; then roll 1"),
		make_button("Into Vaikuntha", send_to_vaikuntha, "Finish the pawn; all 3 in wins")])

	# Economy
	add_header(list, "Economy")
	gold_spinbox = make_spinbox(0, 99999, 1000, 10)
	add_row(list, [make_label("Gold"), gold_spinbox, make_button("Set", set_gold)])
	add_row(list, [
		make_button("+100", add_gold.bind(100)), make_button("+500", add_gold.bind(500)),
		make_button("-100", add_gold.bind(-100)), make_button("-500", add_gold.bind(-500))])
	kingdom_option = OptionButton.new()
	for node in kingdoms:
		kingdom_option.add_item("%s  (%s, %d)" % [node.property_name, node.color_set, node.purchase_cost])
	add_row(list, [kingdom_option, make_button("Give", give_kingdom)])
	set_option = OptionButton.new()
	for color_set in GameManager.FORT_COST_BY_SET:
		set_option.add_item(color_set)
	add_row(list, [set_option, make_button("Give whole set", give_set)])
	kills_spinbox = make_spinbox(0, 99, 3, 1)
	add_row(list, [make_label("Kills"), kills_spinbox, make_button("Set", set_kills)])

	# Cards
	add_header(list, "Cards")
	card_option = OptionButton.new()
	for entry in card_entries:
		var text: String = entry[1].text
		card_option.add_item("%s: %s" % [["Dharma", "Adharma"][entry[0]], text.left(48) + ("..." if text.length() > 48 else "")])
	card_option.fit_to_longest_item = false
	card_option.clip_text = true # Long lines would widen the drawer
	card_option.custom_minimum_size = Vector2(DRAWER_WIDTH - 40, 0)
	add_row(list, [card_option])
	add_row(list, [make_button("Draw this card", draw_card, "Plays the flying card, then its effect, for the Target player")])

	# Turn & game
	add_header(list, "Turn & Game")
	add_row(list, [
		make_button("Make it their turn", force_turn),
		make_button("Skip this turn", skip_turn)])
	add_row(list, [
		make_button("Win now", trigger_win),
		make_button("Go bankrupt", trigger_bankrupt)])

	# Commentary
	add_header(list, "Commentary")
	line_option = OptionButton.new()
	for entry in line_entries:
		line_option.add_item("%s: %s" % [entry.name, entry.text.left(46) + "..."])
	line_option.fit_to_longest_item = false
	line_option.clip_text = true # Long lines would widen the drawer
	line_option.custom_minimum_size = Vector2(DRAWER_WIDTH - 40, 0)
	add_row(list, [line_option])
	add_row(list, [
		make_button("Say it", say_line),
		make_button("Reset pacing", reset_pacing, "Clears the gaps and cooldowns, so the next event speaks at once")])

	# Debug
	add_header(list, "Debug")
	var speed_row: Array = [make_label("Speed")]
	for speed in SPEEDS:
		speed_row.append(make_button("%dx" % speed, set_speed.bind(speed)))
	add_row(list, speed_row)
	var ids_toggle = CheckButton.new()
	ids_toggle.text = "Show space IDs"
	ids_toggle.toggled.connect(show_space_ids)
	add_row(list, [ids_toggle])
	seed_spinbox = make_spinbox(0, 999999, 12345, 1)
	add_row(list, [make_label("Seed"), seed_spinbox, make_button("Apply", apply_seed, "Fixes card shuffles and other random picks from now on")])

func add_header(list: VBoxContainer, text: String):
	var header = Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color("#D9A21B"))
	list.add_child(header)

func add_row(list: VBoxContainer, controls: Array):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for control in controls:
		row.add_child(control)
	list.add_child(row)

func make_button(text: String, action: Callable, tooltip: String = "") -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	return button

func make_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.94, 0.89, 0.78))
	return label

func make_spinbox(minimum: float, maximum: float, value: float, step: float) -> SpinBox:
	var spinbox = SpinBox.new()
	spinbox.min_value = minimum
	spinbox.max_value = maximum
	spinbox.step = step
	spinbox.value = value
	spinbox.custom_minimum_size = Vector2(120, 0)
	return spinbox

func collect_board_data():
	var node: BoardNode = board.start_node
	while node != null and not ring_spaces.has(node):
		ring_spaces.append(node)
		node = node.next_node
	kingdoms = ring_spaces.filter(func(n): return n.is_kingdom())
	for deck in GameManager.CARD_DECKS.size():
		for card in GameManager.CARD_DECKS[deck]:
			card_entries.append([deck, card])
	for when in board.commentary.lines_by_when:
		line_entries.append_array(board.commentary.lines_by_when[when])

# --- Helpers ---

func target_player() -> int:
	return player_option.selected

func target_pawn() -> Pawn:
	var squad: Array = board.players_pawns[target_player()]
	var index = pawn_option.selected
	return squad[index] if index < squad.size() else null

func report(text: String):
	status_label.text = text
	board.show_message("[DEV] " + text)

# Board-changing tools wait until the game is between throws
func board_ready() -> bool:
	if board.state != board.TurnState.WAIT_THROW or board.dice.is_holding:
		status_label.text = "Not now: wait until it's time to throw."
		return false
	if GameManager.instance.player_eliminated[target_player()]:
		status_label.text = "Player %d is out of the game." % (target_player() + 1)
		return false
	return true

# After a tool ran board rules: end the game if one player is left, pass the
# turn if the active player went bankrupt, otherwise wait for the throw again
func settle():
	var gm = GameManager.instance
	var remaining = gm.get_remaining_players()
	if remaining.size() == 1:
		board.declare_winner(remaining[0], "is the last player standing")
		return
	if gm.player_eliminated[gm.active_player_index]:
		board.switch_turn()
		return
	board.state = board.TurnState.WAIT_THROW
	board.update_turn_label()
	board.refresh_players_panel()

# --- Pawns ---

func teleport(apply_space: bool):
	if not board_ready():
		return
	var pawn = target_pawn()
	if pawn == null:
		return
	var space: BoardNode = ring_spaces[space_option.selected]
	pawn.reset_to_start(space) # Puts it on the outer ring, clearing any Ludo progress
	report("Player %d's Pawn %d teleported to %s" % [target_player() + 1, pawn_option.selected + 1, space.get_display_name()])
	if apply_space:
		board.state = board.TurnState.MOVING
		if not await board.resolve_capture(pawn):
			await board.resolve_landing(pawn)
		settle()

# Puts the pawn on the last Home Stretch space, so a roll of 1 finishes it
func send_home_stretch():
	if not board_ready():
		return
	var pawn = target_pawn()
	var last = find_last_home_space()
	if pawn == null or last == null:
		return
	pawn.reset_to_start(last)
	pawn.path_state = Pawn.PathState.HOME_STRETCH
	pawn.set_initial_node(last) # Again, now at the inner board's scale
	report("Player %d's Pawn %d is 1 step from the Lotus" % [target_player() + 1, pawn_option.selected + 1])

func send_to_vaikuntha():
	if not board_ready():
		return
	var pawn = target_pawn()
	var last = find_last_home_space()
	if pawn == null or last == null:
		return
	pawn.reset_to_start(last.next_node)
	pawn.path_state = Pawn.PathState.VAIKUNTHA
	pawn.set_initial_node(last.next_node)
	var arrived = board.count_pawns_in_vaikuntha(target_player())
	report("Player %d's Pawn %d entered Vaikuntha (%d/%d)" % [target_player() + 1, pawn_option.selected + 1, arrived, GameManager.PAWNS_PER_PLAYER])
	board.refresh_players_panel()
	if arrived == GameManager.PAWNS_PER_PLAYER:
		board.declare_winner(target_player(), "brought all pawns to Vaikuntha")

func find_last_home_space() -> BoardNode:
	for node in board.get_node("BoardNodes/HomeNodes").get_children():
		if node is BoardNode and node.next_node != null and node.next_node.tile_type == BoardNode.TileType.THRONE:
			return node
	return null

# --- Economy ---

func set_gold():
	var gm = GameManager.instance
	gm.add_gold(target_player(), int(gold_spinbox.value) - gm.player_suvarnas[target_player()])
	report("Player %d now has %d Gold" % [target_player() + 1, gm.player_suvarnas[target_player()]])

func add_gold(amount: int):
	var gm = GameManager.instance
	gm.add_gold(target_player(), amount)
	report("Player %d: %+d Gold (now %d)" % [target_player() + 1, amount, gm.player_suvarnas[target_player()]])

func give_kingdom():
	transfer(kingdoms[kingdom_option.selected])
	report("Player %d now owns %s" % [target_player() + 1, kingdoms[kingdom_option.selected].property_name])

func give_set():
	var color_set = set_option.get_item_text(set_option.selected)
	for node in GameManager.instance.get_set_kingdoms(color_set):
		transfer(node)
	report("Player %d now owns the whole %s set" % [target_player() + 1, color_set])

# Hands a kingdom to the Target player for free, from the Bank or a rival
func transfer(node: BoardNode):
	var gm = GameManager.instance
	var player = target_player()
	if node.owner_id == player:
		return
	if node.owner_id >= 0:
		gm.player_kingdoms[node.owner_id].erase(node)
	node.set_kingdom_owner(player)
	gm.player_kingdoms[player].append(node)
	board.refresh_players_panel()

func set_kills():
	var gm = GameManager.instance
	gm.player_kills[target_player()] = int(kills_spinbox.value)
	gm.kills_changed.emit(target_player(), gm.player_kills[target_player()])
	report("Player %d now has %d Kills" % [target_player() + 1, gm.player_kills[target_player()]])

# --- Cards ---

func draw_card():
	if not board_ready():
		return
	var pawn = first_pawn_on_board(target_player())
	if pawn == null:
		return
	var entry = card_entries[card_option.selected]
	var deck: int = entry[0]
	var card: Dictionary = entry[1]
	board.state = board.TurnState.MOVING
	report("Drawing %s card for Player %d" % [["Dharma", "Adharma"][deck], target_player() + 1])
	await board.card_table.show_card(deck, card.text)
	await board.apply_card(pawn, card, "[DEV] card")
	settle()

func first_pawn_on_board(player_id: int) -> Pawn:
	var squad: Array = board.players_pawns[player_id]
	var chosen = target_pawn()
	if chosen != null and chosen.path_state != Pawn.PathState.VAIKUNTHA:
		return chosen
	for pawn in squad:
		if pawn.path_state != Pawn.PathState.VAIKUNTHA:
			return pawn
	return null

# --- Turn & game ---

func force_turn():
	if not board_ready():
		return
	var gm = GameManager.instance
	gm.active_player_index = target_player()
	gm.is_waiting_for_input = true
	gm.turn_changed.emit(target_player())
	report("It is now Player %d's turn" % (target_player() + 1))
	board.begin_turn()

func skip_turn():
	if board.state != board.TurnState.WAIT_THROW or board.dice.is_holding:
		status_label.text = "Not now: wait until it's time to throw."
		return
	report("Player %d's turn skipped" % (GameManager.instance.active_player_index + 1))
	board.switch_turn()

func trigger_win():
	if board.state == board.TurnState.GAME_OVER:
		return
	report("Player %d wins by developer decree" % (target_player() + 1))
	board.declare_winner(target_player(), "won by developer decree")

func trigger_bankrupt():
	if not board_ready():
		return
	board.state = board.TurnState.MOVING
	board.go_bankrupt(target_player(), -1, 0, "developer decree")
	settle()

# --- Commentary ---

func say_line():
	var entry = line_entries[line_option.selected]
	board.commentary.popup.say(entry.name, entry.text)

func reset_pacing():
	board.commentary.last_shown_at = -INF
	board.commentary.last_trigger_at.clear()
	status_label.text = "Commentary pacing reset."

# --- Debug ---

func set_speed(speed: float):
	Engine.time_scale = speed
	status_label.text = "Game speed %dx" % speed

func apply_seed():
	seed(int(seed_spinbox.value))
	status_label.text = "Random seed set to %d" % int(seed_spinbox.value)

# Labels every board space: R = outer ring, L = Ludo track, H = Home Stretch
func show_space_ids(on: bool):
	if space_ids == null:
		space_ids = Node2D.new()
		space_ids.z_index = 30
		space_ids.draw.connect(draw_space_ids)
		board.add_child(space_ids)
	space_ids.visible = on
	space_ids.queue_redraw()

func draw_space_ids():
	var font = ThemeDB.fallback_font
	var prefixes = {"MonopolyNodes": "R", "LudoNodes": "L", "HomeNodes": "H"}
	for group in prefixes:
		for node in board.get_node("BoardNodes/" + group).get_children():
			if not node is BoardNode:
				continue
			var text = prefixes[group] + str(node.name).trim_prefix("Node_")
			var size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var at = node.global_position
			space_ids.draw_rect(Rect2(at - size / 2 - Vector2(3, 1), size + Vector2(6, 2)), Color(0, 0, 0, 0.75))
			space_ids.draw_string(font, at + Vector2(-size.x / 2, size.y / 2 - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.4))
