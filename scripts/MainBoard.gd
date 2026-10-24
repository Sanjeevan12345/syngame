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
var state: TurnState = TurnState.WAIT_THROW

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
var debt_player: int = -1
var debt_amount: int = 0
var debt_reason: String = ""

func _ready():
	GameManager.instance.setup_players(player_count)
	spawn_pawns()
	build_sell_panel()
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

	update_turn_label()

# Places every player's 3 pawns on Start (Node_0), tinted by player
func spawn_pawns():
	for player_id in player_count:
		var squad: Array = []
		for pawn_index in GameManager.PAWNS_PER_PLAYER:
			var pawn = PAWN_SCENE.instantiate() as Pawn
			pawn.owner_id = player_id
			pawn.pawn_index = pawn_index
			pawn.name = "Pawn_P%d_%d" % [player_id + 1, pawn_index + 1]
			pawn.modulate = GameManager.PLAYER_COLORS[player_id]
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
		sell_buttons[player_id].disabled = not can_sell(player_id)

	# Selling during the buy prompt can make a Kingdom affordable
	if buy_prompt.visible and buy_candidate != null:
		update_buy_prompt()
	refresh_sell_panel()

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
		var button = Button.new()
		button.text = "Sell %s (%s) for %d Gold" % [node.property_name, node.color_set, gm.resale_value(node)]
		button.disabled = not can_sell(sell_player)
		button.pressed.connect(_on_sell_pressed.bind(sell_player, node))
		sell_list.add_child(button)

func _on_sell_pressed(player_id: int, node: BoardNode):
	var value = GameManager.instance.sell_kingdom(player_id, node)
	show_message("Player %d sold %s to the Bank for %d Gold" % [player_id + 1, node.property_name, value])
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
	if not resolve_capture(pawn):
		await resolve_landing(pawn)

	var remaining = GameManager.instance.get_remaining_players()
	if remaining.size() == 1:
		declare_winner(remaining[0], "is the last player standing")
		return

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

	var victims = GameManager.instance.resolve_vadh(pawn, all_pawns, start_node)
	for victim in victims:
		show_message("VADH! Player %d captured Player %d's Pawn %d at %s - sent back to %s" % [
			pawn.owner_id + 1, victim.owner_id + 1, victim.pawn_index + 1,
			pawn.current_node.get_display_name(), start_node.property_name])
	return not victims.is_empty()

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
			var amount: int = card["gold"]
			show_message("%s card: %s (%+d Gold)" % [node.property_name, card["text"], amount])
			if amount >= 0:
				gm.add_gold(player_id, amount)
			else:
				await collect_payment(player_id, -amount, -1, node.property_name + " card")

		BoardNode.TileType.MONOPOLY:
			if not node.is_kingdom():
				return
			if node.owner_id == -1:
				await offer_purchase(player_id, node)
			elif node.owner_id != player_id:
				var owner_id = node.owner_id
				if await collect_payment(player_id, node.base_rent, owner_id, "rent on " + node.property_name):
					show_message("Player %d paid %d Gold rent to Player %d for %s" % [
						player_id + 1, node.base_rent, owner_id + 1, node.property_name])

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
	state = TurnState.WAIT_THROW
	update_turn_label()
	print("Switched turn to: Player ", GameManager.instance.active_player_index + 1)

func update_turn_label():
	var player_id = GameManager.instance.active_player_index
	turn_label.text = "Player %d - drag and throw the sticks" % (player_id + 1)
	turn_label.modulate = GameManager.PLAYER_COLORS[player_id]
