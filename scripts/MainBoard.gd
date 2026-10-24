extends Node2D

const PAWN_SCENE = preload("res://scenes/Pawn.tscn")

enum TurnState { WAIT_THROW, ROLLING, CHOOSE_PAWN, MOVING, GAME_OVER }

@export_range(2, 4) var player_count: int = 2

@onready var turn_label: Label = $UI_Layer/TurnLabel
@onready var message_label: Label = $UI_Layer/MessageLabel
@onready var players_panel: VBoxContainer = $UI_Layer/PlayersPanel
@onready var buy_prompt: HBoxContainer = $UI_Layer/BuyPrompt
@onready var buy_label: Label = $UI_Layer/BuyPrompt/BuyLabel
@onready var buy_button: Button = $UI_Layer/BuyPrompt/BuyButton
@onready var pass_button: Button = $UI_Layer/BuyPrompt/PassButton
@onready var gate_prompt: HBoxContainer = $UI_Layer/GatePrompt
@onready var gate_label: Label = $UI_Layer/GatePrompt/GateLabel
@onready var enter_button: Button = $UI_Layer/GatePrompt/EnterButton
@onready var stay_button: Button = $UI_Layer/GatePrompt/StayButton
@onready var lap_prompt: HBoxContainer = $UI_Layer/LapPrompt
@onready var lap_label: Label = $UI_Layer/LapPrompt/LapLabel
@onready var loop_button: Button = $UI_Layer/LapPrompt/LoopButton
@onready var exit_button: Button = $UI_Layer/LapPrompt/ExitButton
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

# Shakuni card picker, built in code: one button per possible Pasa score
var shakuni_prompt: HBoxContainer
signal shakuni_chosen(value: int)

func _ready():
	# The opening page's choice wins over the Inspector value
	if GameManager.instance.selected_player_count > 0:
		player_count = GameManager.instance.selected_player_count
	GameManager.instance.setup_players(player_count)
	spawn_pawns()
	build_sell_panel()
	build_build_panel()
	build_shakuni_prompt()
	build_players_panel()
	GameManager.instance.gold_changed.connect(func(_id, _gold): refresh_players_panel())
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

	begin_turn()

# Places every player's 3 pawns on Start (Node_0), tinted by player
func spawn_pawns():
	for player_id in player_count:
		var squad: Array = []
		for pawn_index in GameManager.PAWNS_PER_PLAYER:
			var pawn = PAWN_SCENE.instantiate() as Pawn
			pawn.owner_id = player_id
			pawn.pawn_index = pawn_index
			pawn.name = "Pawn_P%d_%d" % [player_id + 1, pawn_index + 1]
			# Players alternate between the two character designs; the colored
			# ring under each pawn tells players apart
			pawn.character = player_id % Pawn.CHARACTERS.size()
			pawn.player_color = GameManager.PLAYER_COLORS[player_id]
			pawn.visual_offset = Vector2((pawn_index - 1) * 14, (player_id - 1.5) * 10)
			$Pawns.add_child(pawn)
			pawn.set_initial_node(start_node)
			pawn.step_finished.connect(_on_pawn_step)
			squad.append(pawn)
		players_pawns.append(squad)

# One line per player showing their gold, Kingdoms, color sets and kills,
# with a Sell button to sell Kingdoms back to the Bank at any time
func build_players_panel():
	for player_id in player_count:
		var row = HBoxContainer.new()
		players_panel.add_child(row)

		var label = Label.new()
		label.add_theme_font_size_override("font_size", 18)
		label.modulate = GameManager.PLAYER_COLORS[player_id]
		row.add_child(label)
		player_labels.append(label)

		var build = Button.new()
		build.text = "Build"
		build.pressed.connect(open_build_panel.bind(player_id))
		row.add_child(build)
		build_buttons.append(build)

		var sell = Button.new()
		sell.text = "Sell"
		sell.pressed.connect(open_sell_panel.bind(player_id))
		row.add_child(sell)
		sell_buttons.append(sell)
	refresh_players_panel()

func refresh_players_panel():
	var gm = GameManager.instance
	for player_id in player_count:
		if gm.player_eliminated[player_id]:
			player_labels[player_id].text = "Player %d:  BANKRUPT" % (player_id + 1)
		else:
			player_labels[player_id].text = "P%d: %d Gold | %d Kingdoms | %d/%d Sets | %d/%d Kills | %d/%d Vaikuntha" % [
				player_id + 1, gm.player_suvarnas[player_id], gm.player_kingdoms[player_id].size(),
				gm.count_color_sets(player_id), GameManager.HOME_STRETCH_SETS_REQUIRED,
				gm.player_kills[player_id], GameManager.HOME_STRETCH_KILLS_REQUIRED,
				count_pawns_in_vaikuntha(player_id), GameManager.PAWNS_PER_PLAYER]
			if gm.player_shakuni[player_id]:
				player_labels[player_id].text += " | ★ Shakuni"
			if gm.player_skip_turns[player_id] > 0:
				player_labels[player_id].text += " | Skips %d" % gm.player_skip_turns[player_id]
		sell_buttons[player_id].disabled = not can_sell(player_id)
		build_buttons[player_id].disabled = not can_open_build(player_id)

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
	build_panel.position = Vector2(330, 260)
	build_panel.custom_minimum_size = Vector2(460, 0)
	$UI_Layer.add_child(build_panel)

	var box = VBoxContainer.new()
	build_panel.add_child(box)

	build_title = Label.new()
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
	refresh_players_panel()

func can_sell(player_id: int) -> bool:
	var gm = GameManager.instance
	return state != TurnState.GAME_OVER and not gm.player_eliminated[player_id] \
		and not gm.player_kingdoms[player_id].is_empty()

func build_sell_panel():
	sell_panel = PanelContainer.new()
	sell_panel.visible = false
	sell_panel.position = Vector2(330, 260)
	sell_panel.custom_minimum_size = Vector2(460, 0)
	$UI_Layer.add_child(sell_panel)

	var box = VBoxContainer.new()
	sell_panel.add_child(box)

	sell_title = Label.new()
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

func show_message(text: String):
	print(text)
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

	message_label.text = ""

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

	match node.tile_type:
		BoardNode.TileType.TAX:
			if await collect_payment(player_id, node.tile_gold, -1, node.property_name):
				show_message("Player %d paid %d Gold at %s" % [player_id + 1, node.tile_gold, node.property_name])

		BoardNode.TileType.CARD:
			var card = gm.draw_card(node.card_deck)
			show_message("%s card: %s" % [node.property_name, card["text"]])
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
	turn_label.modulate = GameManager.PLAYER_COLORS[player_id]
	refresh_players_panel()

func switch_turn():
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
		turn_label.modulate = GameManager.PLAYER_COLORS[player_id]
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
		turn_label.modulate = GameManager.PLAYER_COLORS[player_id]
		shakuni_prompt.visible = true
		var value: int = await shakuni_chosen
		shakuni_prompt.visible = false
		show_message("Player %d uses Shakuni's dice: %d" % [player_id + 1, value])
		_on_dice_rolled(value)
		return

	state = TurnState.WAIT_THROW
	update_turn_label()

func build_shakuni_prompt():
	shakuni_prompt = HBoxContainer.new()
	shakuni_prompt.visible = false
	shakuni_prompt.position = Vector2(1140, 445)
	$UI_Layer.add_child(shakuni_prompt)

	var label = Label.new()
	label.text = "Shakuni's dice:"
	shakuni_prompt.add_child(label)

	for value in GameManager.PASA_SCORES:
		var button = Button.new()
		button.text = str(value)
		button.custom_minimum_size = Vector2(44, 0)
		button.pressed.connect(func(): shakuni_chosen.emit(value))
		shakuni_prompt.add_child(button)

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

func update_turn_label():
	var player_id = GameManager.instance.active_player_index
	turn_label.text = "Player %d - drag and throw the sticks" % (player_id + 1)
	turn_label.modulate = GameManager.PLAYER_COLORS[player_id]
